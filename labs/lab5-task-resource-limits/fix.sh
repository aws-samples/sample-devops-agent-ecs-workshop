#!/bin/bash
# Lab 5: Task Resource Limits (OOM) - Fix Script
# This script restores the checkout service task definition by removing the memory stress sidecar

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="checkout"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab5_backup"

echo "=== Lab 5: Task Resource Limits (OOM) - Fix ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_DIR/original_task_def.json" ]; then
  echo "ERROR: Backup not found at $BACKUP_DIR/original_task_def.json"
  echo "The inject script may not have been run, or backup was deleted."
  exit 1
fi

# Step 1: Get original memory
echo "[1/2] Reading original configuration..."
ORIGINAL_MEMORY=$(cat $BACKUP_DIR/original_memory.txt)
echo "  Restoring original task definition (memory: ${ORIGINAL_MEMORY}MB, no stress sidecar)"

# Step 2: Register restored task definition
echo "[2/2] Registering restored task definition..."
cat $BACKUP_DIR/original_task_def.json | jq '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
  .containerDefinitions = [.containerDefinitions[] | select(.name != "memory-stress")]
' > $BACKUP_DIR/restored_task_def.json

RESTORED_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://$BACKUP_DIR/restored_task_def.json \
  --region $REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)
echo "  Restored task definition: $RESTORED_TASK_DEF_ARN"

# Update service
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $RESTORED_TASK_DEF_ARN \
  --force-new-deployment \
  --region $REGION \
  --query 'service.serviceName' \
  --output text > /dev/null

echo ""
echo "=== Lab 5 Fix Complete ==="
echo ""
echo "The checkout service has been restored (memory-stress sidecar removed)."
echo "Tasks should start and stay running within 1-2 minutes."
echo ""
echo "Verify with:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME \\"
echo "    --query 'services[0].[runningCount,desiredCount]' --output text"
