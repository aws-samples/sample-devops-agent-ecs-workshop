#!/bin/bash
# Lab 1: CloudWatch Logs Not Delivered - Fix Script
# This script restores the catalog service task definition to use the correct log group

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="catalog"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab1_backup"

echo "=== Lab 1: CloudWatch Logs Not Delivered - Fix ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_DIR/original_task_def.json" ]; then
  echo "ERROR: Backup not found at $BACKUP_DIR/original_task_def.json"
  echo "The inject script may not have been run, or backup was deleted."
  exit 1
fi

# Step 1: Get original log group
echo "[1/3] Reading original configuration..."
ORIGINAL_LOG_GROUP=$(cat $BACKUP_DIR/original_log_group.txt)
echo "  Original log group: $ORIGINAL_LOG_GROUP"

# Step 2: Register restored task definition
echo "[2/3] Registering restored task definition..."
cat $BACKUP_DIR/original_task_def.json | jq '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
' > $BACKUP_DIR/restored_task_def.json

RESTORED_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://$BACKUP_DIR/restored_task_def.json \
  --region $REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)
echo "  Restored task definition: $RESTORED_TASK_DEF_ARN"

# Step 3: Update service
echo "[3/3] Updating service to use restored task definition..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $RESTORED_TASK_DEF_ARN \
  --force-new-deployment \
  --region $REGION \
  --query 'service.serviceName' \
  --output text > /dev/null

echo ""
echo "=== Lab 1 Fix Complete ==="
echo ""
echo "The catalog service has been restored with the correct log group."
echo "New tasks should start successfully within 1-2 minutes."
echo ""
echo "Verify with:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME \\"
echo "    --query 'services[0].[runningCount,desiredCount]' --output text"
