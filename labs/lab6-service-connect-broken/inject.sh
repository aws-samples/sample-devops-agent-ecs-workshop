#!/bin/bash
# Lab 6: Service Connect / Inter-Service Communication Broken
# Issue: Modify the UI service to point to wrong service endpoints
# Symptom: UI loads but catalog/cart features don't work
#
# NOTE: This application uses ECS Service Connect for inter-service communication.
# Services communicate via client aliases (e.g., http://catalog, http://carts)
# NOT via traditional service discovery DNS names.

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="ui"
BACKUP_DIR="/tmp/lab6_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 6: Service Connect Communication Broken"
echo "=============================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Region: $AWS_REGION"
echo ""
echo "Injecting issue..."

# Create backup directory
mkdir -p $BACKUP_DIR

# Get current task definition
TASK_DEF_ARN=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --query 'services[0].taskDefinition' --output text --region $AWS_REGION)
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_DEF_ARN --region $AWS_REGION)

# Save original task definition ARN for restore
echo "$TASK_DEF_ARN" > $BACKUP_DIR/original_task_def_arn.txt

# Save original environment variables for reference
ORIGINAL_ENV=$(echo "$TASK_DEF" | jq '.taskDefinition.containerDefinitions[0].environment')
echo "$ORIGINAL_ENV" > $BACKUP_DIR/original_env.json
echo "Original environment saved to $BACKUP_DIR/original_env.json"

# Get existing environment variables and modify only the endpoint ones
# The issue: pointing to wrong service names that don't exist in Service Connect
NEW_TASK_DEF=$(echo $TASK_DEF | jq '.taskDefinition | 
  .containerDefinitions[0].environment = (.containerDefinitions[0].environment | map(
    if .name == "RETAIL_UI_ENDPOINTS_CATALOG" then .value = "http://catalog-broken"
    elif .name == "ENDPOINTS_CATALOG" then .value = "http://catalog-broken"
    elif .name == "RETAIL_UI_ENDPOINTS_CARTS" then .value = "http://carts"
    elif .name == "RETAIL_UI_ENDPOINTS_CHECKOUT" then .value = "http://checkout"
    elif .name == "RETAIL_UI_ENDPOINTS_ORDERS" then .value = "http://orders"
    else .
    end
  )) |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')

# Register new task definition
NEW_TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json "$NEW_TASK_DEF" --region $AWS_REGION --query 'taskDefinition.taskDefinitionArn' --output text)
echo "New task definition: $NEW_TASK_DEF_ARN"

# Update service
aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --task-definition $NEW_TASK_DEF_ARN --force-new-deployment --region $AWS_REGION > /dev/null

echo ""
echo "Issue injected successfully!"
echo ""
echo "=============================================="
echo "SCENARIO:"
echo "=============================================="
echo "The retail store UI loads, but the product catalog is empty."
echo "Customers can access the site but cannot see any products."
echo "The catalog service appears healthy in ECS console."
echo ""
echo "YOUR TASK:"
echo "1. Use AWS DevOps Agent to investigate why the catalog isn't loading"
echo "2. Check if the catalog service is running and healthy"
echo "3. Examine how the UI service connects to backend services"
echo "4. Identify the endpoint misconfiguration"
echo ""
echo "HINTS:"
echo "- The UI service uses environment variables for service endpoints"
echo "- Check the task definition's environment configuration"
echo "- This application uses ECS Service Connect for inter-service communication"
echo "- Service Connect client aliases are simple service names (e.g., 'catalog')"
echo ""
echo "Run './labs/lab6-service-connect-broken/fix.sh' when ready to restore"
echo "=============================================="
