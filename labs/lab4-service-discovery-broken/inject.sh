#!/bin/bash
# Lab 4: Service Connect Communication Broken - Inject Script
# This script modifies the UI service environment variable to point to a non-existent service endpoint

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="ui"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab4_backup"

echo "=== Lab 4: Service Connect Communication Broken - Inject ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Create backup directory
mkdir -p $BACKUP_DIR

# Step 1: Get current task definition
echo "[1/4] Getting current task definition..."
TASK_DEF_ARN=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $REGION \
  --query 'services[0].taskDefinition' \
  --output text)

echo "  Current task definition: $TASK_DEF_ARN"

# Step 2: Save current task definition for rollback
echo "[2/4] Backing up current task definition..."
aws ecs describe-task-definition \
  --task-definition $TASK_DEF_ARN \
  --region $REGION \
  --query 'taskDefinition' > $BACKUP_DIR/original_task_def.json

# Step 3: Create modified task definition with broken catalog endpoint
echo "[3/4] Creating modified task definition with broken service endpoint..."

# Modify the RETAIL_UI_ENDPOINTS_CATALOG environment variable
cat $BACKUP_DIR/original_task_def.json | jq '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
  .containerDefinitions[0].environment = [
    .containerDefinitions[0].environment[] |
    if .name == "RETAIL_UI_ENDPOINTS_CATALOG" or .name == "ENDPOINTS_CATALOG" then
      .value = "http://catalog-broken"
    else
      .
    end
  ]
' > $BACKUP_DIR/broken_task_def.json

# Register new task definition
NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://$BACKUP_DIR/broken_task_def.json \
  --region $REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)
echo "  New task definition: $NEW_TASK_DEF_ARN"

# Step 4: Update service to use broken task definition
echo "[4/4] Updating service to use broken task definition..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $NEW_TASK_DEF_ARN \
  --force-new-deployment \
  --region $REGION \
  --query 'service.serviceName' \
  --output text > /dev/null

echo ""
echo "=== Lab 4 Injection Complete ==="
echo ""
echo "Issue injected: UI service now points to non-existent catalog endpoint"
echo "  Broken endpoint: http://catalog-broken"
echo "  Correct endpoint: http://catalog"
echo ""
echo "Expected symptoms:"
echo "  - UI loads but catalog is empty"
echo "  - Catalog service appears healthy"
echo "  - UI logs show connection errors to 'catalog-broken'"
echo ""
echo "Investigation prompts for DevOps Agent:"
echo "  'The product catalog is empty but the catalog service looks healthy. What is wrong?'"
echo "  'How does the UI service connect to the catalog service? Check the environment variables.'"
echo "  'Show me the Service Connect configuration for the retail store services'"
echo ""
echo "To fix: ./labs/lab4-service-discovery-broken/fix.sh"
