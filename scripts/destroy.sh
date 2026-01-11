#!/bin/bash
#
# ECS DevOps Agent Lab - Complete Destroy Script
# This script cleans up all resources including dependencies that may block terraform destroy
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform/ecs/default"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get VPC ID from terraform state or by tag
get_vpc_id() {
    cd "$TERRAFORM_DIR"
    
    # Try to get from terraform output first
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || true)
    
    if [ -z "$VPC_ID" ]; then
        # Fallback: find VPC by tag
        VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=tag:ecsdevopsagent,Values=true" \
            --query 'Vpcs[0].VpcId' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || true)
    fi
    
    echo "$VPC_ID"
}

# Delete VPC Endpoints that block subnet deletion
cleanup_vpc_endpoints() {
    local vpc_id=$1
    
    if [ -z "$vpc_id" ] || [ "$vpc_id" == "None" ]; then
        log_warn "No VPC ID found, skipping VPC endpoint cleanup"
        return
    fi
    
    log_info "Checking for VPC endpoints in VPC: $vpc_id"
    
    ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'VpcEndpoints[*].VpcEndpointId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || true)
    
    if [ -n "$ENDPOINTS" ] && [ "$ENDPOINTS" != "None" ]; then
        for endpoint in $ENDPOINTS; do
            log_info "Deleting VPC endpoint: $endpoint"
            aws ec2 delete-vpc-endpoints \
                --vpc-endpoint-ids "$endpoint" \
                --region "$AWS_REGION" 2>/dev/null || log_warn "Failed to delete endpoint $endpoint"
        done
        log_info "Waiting for VPC endpoints to be deleted..."
        sleep 30
    else
        log_info "No VPC endpoints found"
    fi
}

# Delete NAT Gateways
cleanup_nat_gateways() {
    local vpc_id=$1
    
    if [ -z "$vpc_id" ] || [ "$vpc_id" == "None" ]; then
        return
    fi
    
    log_info "Checking for NAT Gateways in VPC: $vpc_id"
    
    NAT_GATEWAYS=$(aws ec2 describe-nat-gateways \
        --filter "Name=vpc-id,Values=$vpc_id" "Name=state,Values=available,pending" \
        --query 'NatGateways[*].NatGatewayId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || true)
    
    if [ -n "$NAT_GATEWAYS" ] && [ "$NAT_GATEWAYS" != "None" ]; then
        for nat in $NAT_GATEWAYS; do
            log_info "Deleting NAT Gateway: $nat"
            aws ec2 delete-nat-gateway \
                --nat-gateway-id "$nat" \
                --region "$AWS_REGION" 2>/dev/null || log_warn "Failed to delete NAT Gateway $nat"
        done
        log_info "Waiting for NAT Gateways to be deleted (this may take a few minutes)..."
        sleep 60
    else
        log_info "No NAT Gateways found"
    fi
}

# Delete Load Balancers
cleanup_load_balancers() {
    local vpc_id=$1
    
    if [ -z "$vpc_id" ] || [ "$vpc_id" == "None" ]; then
        return
    fi
    
    log_info "Checking for Load Balancers in VPC: $vpc_id"
    
    # Get ALBs in the VPC
    ALBS=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?VpcId=='$vpc_id'].LoadBalancerArn" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || true)
    
    if [ -n "$ALBS" ] && [ "$ALBS" != "None" ]; then
        for alb in $ALBS; do
            log_info "Deleting Load Balancer: $alb"
            
            # First delete listeners
            LISTENERS=$(aws elbv2 describe-listeners \
                --load-balancer-arn "$alb" \
                --query 'Listeners[*].ListenerArn' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || true)
            
            for listener in $LISTENERS; do
                aws elbv2 delete-listener \
                    --listener-arn "$listener" \
                    --region "$AWS_REGION" 2>/dev/null || true
            done
            
            # Delete the load balancer
            aws elbv2 delete-load-balancer \
                --load-balancer-arn "$alb" \
                --region "$AWS_REGION" 2>/dev/null || log_warn "Failed to delete ALB $alb"
        done
        log_info "Waiting for Load Balancers to be deleted..."
        sleep 30
    else
        log_info "No Load Balancers found"
    fi
}

# Delete ECS Services and Cluster
cleanup_ecs() {
    local cluster_name="${CLUSTER_NAME:-retail-store-ecs-cluster}"
    
    log_info "Checking for ECS cluster: $cluster_name"
    
    # Check if cluster exists
    CLUSTER_EXISTS=$(aws ecs describe-clusters \
        --clusters "$cluster_name" \
        --query 'clusters[0].status' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || echo "MISSING")
    
    if [ "$CLUSTER_EXISTS" == "ACTIVE" ]; then
        # Get all services
        SERVICES=$(aws ecs list-services \
            --cluster "$cluster_name" \
            --query 'serviceArns[*]' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || true)
        
        if [ -n "$SERVICES" ] && [ "$SERVICES" != "None" ]; then
            for service_arn in $SERVICES; do
                service_name=$(echo "$service_arn" | awk -F'/' '{print $NF}')
                log_info "Scaling down and deleting ECS service: $service_name"
                
                # Scale to 0
                aws ecs update-service \
                    --cluster "$cluster_name" \
                    --service "$service_name" \
                    --desired-count 0 \
                    --region "$AWS_REGION" 2>/dev/null || true
                
                # Delete service
                aws ecs delete-service \
                    --cluster "$cluster_name" \
                    --service "$service_name" \
                    --force \
                    --region "$AWS_REGION" 2>/dev/null || log_warn "Failed to delete service $service_name"
            done
            log_info "Waiting for ECS services to be deleted..."
            sleep 30
        fi
        
        # Delete cluster
        log_info "Deleting ECS cluster: $cluster_name"
        aws ecs delete-cluster \
            --cluster "$cluster_name" \
            --region "$AWS_REGION" 2>/dev/null || log_warn "Failed to delete cluster"
    else
        log_info "ECS cluster not found or already deleted"
    fi
}

# Delete network interfaces (ENIs) that may block subnet deletion
cleanup_network_interfaces() {
    local vpc_id=$1
    
    if [ -z "$vpc_id" ] || [ "$vpc_id" == "None" ]; then
        return
    fi
    
    log_info "Checking for orphaned network interfaces in VPC: $vpc_id"
    
    # Get all subnets in the VPC
    SUBNETS=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'Subnets[*].SubnetId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || true)
    
    if [ -n "$SUBNETS" ] && [ "$SUBNETS" != "None" ]; then
        for subnet in $SUBNETS; do
            ENIS=$(aws ec2 describe-network-interfaces \
                --filters "Name=subnet-id,Values=$subnet" \
                --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
                --output text \
                --region "$AWS_REGION" 2>/dev/null || true)
            
            for eni in $ENIS; do
                if [ -n "$eni" ] && [ "$eni" != "None" ]; then
                    log_info "Deleting orphaned ENI: $eni"
                    aws ec2 delete-network-interface \
                        --network-interface-id "$eni" \
                        --region "$AWS_REGION" 2>/dev/null || log_warn "Failed to delete ENI $eni"
                fi
            done
        done
    fi
}

# Remove terraform state lock if exists
cleanup_terraform_lock() {
    cd "$TERRAFORM_DIR"
    
    if [ -f ".terraform.tfstate.lock.info" ]; then
        log_warn "Found terraform state lock file, removing..."
        rm -f .terraform.tfstate.lock.info
    fi
}

# Main destroy function
main() {
    log_info "=========================================="
    log_info "ECS DevOps Agent Lab - Destroy Script"
    log_info "=========================================="
    log_info "Region: $AWS_REGION"
    
    # Confirm destruction
    echo ""
    read -p "This will destroy ALL lab resources. Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Destruction cancelled"
        exit 0
    fi
    
    # Get VPC ID
    VPC_ID=$(get_vpc_id)
    log_info "VPC ID: ${VPC_ID:-Not found}"
    
    # Step 1: Clean up ECS resources first
    log_info ""
    log_info "Step 1: Cleaning up ECS resources..."
    cleanup_ecs
    
    # Step 2: Clean up Load Balancers
    log_info ""
    log_info "Step 2: Cleaning up Load Balancers..."
    cleanup_load_balancers "$VPC_ID"
    
    # Step 3: Clean up VPC Endpoints
    log_info ""
    log_info "Step 3: Cleaning up VPC Endpoints..."
    cleanup_vpc_endpoints "$VPC_ID"
    
    # Step 4: Clean up NAT Gateways
    log_info ""
    log_info "Step 4: Cleaning up NAT Gateways..."
    cleanup_nat_gateways "$VPC_ID"
    
    # Step 5: Clean up orphaned network interfaces
    log_info ""
    log_info "Step 5: Cleaning up orphaned network interfaces..."
    cleanup_network_interfaces "$VPC_ID"
    
    # Step 6: Remove terraform lock if present
    log_info ""
    log_info "Step 6: Checking terraform state lock..."
    cleanup_terraform_lock
    
    # Step 7: Run terraform destroy
    log_info ""
    log_info "Step 7: Running terraform destroy..."
    cd "$TERRAFORM_DIR"
    
    # Initialize terraform if needed
    if [ ! -d ".terraform" ]; then
        terraform init
    fi
    
    # Run destroy with auto-approve
    terraform destroy -auto-approve
    
    log_info ""
    log_info "=========================================="
    log_info "Destroy completed successfully!"
    log_info "=========================================="
}

# Run main function
main "$@"
