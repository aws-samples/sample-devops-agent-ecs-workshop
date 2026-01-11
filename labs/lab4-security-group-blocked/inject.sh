#!/bin/bash
# Lab 4: Database Connectivity - Security Group Blocked
# Issue: Remove the RDS security group rule allowing catalog service access
# Symptom: Catalog service can't connect to MySQL, products don't load

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-retail-store-ecs}"
BACKUP_DIR="/tmp/lab4_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 4: Database Security Group Blocked"
echo "=============================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo ""
echo "Injecting network issue..."

# Create backup directory
mkdir -p $BACKUP_DIR

# Find the RDS security group
RDS_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=*${ENVIRONMENT_NAME}*catalog*db*" \
    --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$RDS_SG_ID" ] || [ "$RDS_SG_ID" == "None" ]; then
    # Try alternative naming with ecsdevopsagent tag
    RDS_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=*catalog*db*" "Name=tag:ecsdevopsagent,Values=true" \
        --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
fi

if [ -z "$RDS_SG_ID" ] || [ "$RDS_SG_ID" == "None" ]; then
    # Try by group name
    RDS_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=*catalog*rds*" \
        --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
fi

if [ -z "$RDS_SG_ID" ] || [ "$RDS_SG_ID" == "None" ]; then
    echo "ERROR: Could not find RDS security group. Trying to find by RDS instance..."
    
    # Find via RDS instance
    RDS_INSTANCE=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, 'catalog')].VpcSecurityGroups[0].VpcSecurityGroupId" \
        --output text --region $AWS_REGION 2>/dev/null | head -1)
    
    if [ -n "$RDS_INSTANCE" ] && [ "$RDS_INSTANCE" != "None" ]; then
        RDS_SG_ID=$RDS_INSTANCE
    else
        echo "ERROR: Could not find RDS security group. Manual setup required."
        exit 1
    fi
fi

echo "Found RDS Security Group: $RDS_SG_ID"

# Get the catalog service security group (task SG that connects to RDS)
CATALOG_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=*${ENVIRONMENT_NAME}*catalog*task*" \
    --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)

if [ -z "$CATALOG_SG_ID" ] || [ "$CATALOG_SG_ID" == "None" ]; then
    CATALOG_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=*catalog*service*" "Name=tag:ecsdevopsagent,Values=true" \
        --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
fi

if [ -z "$CATALOG_SG_ID" ] || [ "$CATALOG_SG_ID" == "None" ]; then
    CATALOG_SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=*catalog*task*" \
        --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)
fi

if [ -z "$CATALOG_SG_ID" ] || [ "$CATALOG_SG_ID" == "None" ]; then
    echo "ERROR: Could not find catalog service security group"
    exit 1
fi

echo "Found Catalog Service Security Group: $CATALOG_SG_ID"

# Save for restoration
echo "$RDS_SG_ID" > $BACKUP_DIR/rds_sg_id.txt
echo "$CATALOG_SG_ID" > $BACKUP_DIR/catalog_sg_id.txt

# Find and remove the ingress rule from catalog to RDS
RULE_ID=$(aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$RDS_SG_ID" \
    --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='$CATALOG_SG_ID'].SecurityGroupRuleId" \
    --output text --region $AWS_REGION 2>/dev/null)

if [ -n "$RULE_ID" ] && [ "$RULE_ID" != "None" ]; then
    echo "$RULE_ID" > $BACKUP_DIR/rule_id.txt
    aws ec2 revoke-security-group-ingress --group-id $RDS_SG_ID --security-group-rule-ids $RULE_ID --region $AWS_REGION
    echo "Removed security group rule: $RULE_ID"
else
    # Try removing by source security group
    aws ec2 revoke-security-group-ingress --group-id $RDS_SG_ID \
        --protocol tcp --port 3306 --source-group $CATALOG_SG_ID --region $AWS_REGION 2>/dev/null || true
    echo "3306" > $BACKUP_DIR/port.txt
    echo "Removed ingress rule for port 3306"
fi

# Force catalog service to reconnect
aws ecs update-service --cluster $CLUSTER_NAME --service catalog --force-new-deployment --region $AWS_REGION > /dev/null

echo ""
echo "Issue injected successfully!"
echo ""
echo "=============================================="
echo "SCENARIO:"
echo "=============================================="
echo "The product catalog suddenly stopped loading."
echo "The catalog service is running but returns errors."
echo "Database connection timeouts in the logs."
echo ""
echo "YOUR TASK:"
echo "1. Use AWS DevOps Agent to investigate catalog service errors"
echo "2. Check CloudWatch logs for connection errors"
echo "3. Examine the network path between ECS and RDS"
echo "4. Identify the security group misconfiguration"
echo ""
echo "HINTS:"
echo "- Check catalog service logs for MySQL connection errors"
echo "- Examine security groups attached to RDS and ECS tasks"
echo "- Verify inbound rules allow traffic on port 3306"
echo ""
echo "Run './labs/lab4-security-group-blocked/fix.sh' when ready to restore"
echo "=============================================="
