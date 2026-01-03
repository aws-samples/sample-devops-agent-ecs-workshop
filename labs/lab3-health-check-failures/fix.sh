#!/bin/bash
# Lab 3: Health Check Failures - Fix Script
# This script restores the UI service task definition with the correct health check endpoint

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="ui"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab3_backup"

echo "=== Lab 3: Health Check Failures - Fix ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_DIR/original_task_def.json" ]; then
  echo "ERROR: Backup not found at $BACKUP_DIR/original_task_def.json"
  echo "The inject script may not have been run, or backup was deleted."
  exit 1
fi

# Step 1: Register restored task definition
echo "[1/2] Registering restored task definition..."
cat $BACKUP_DIR/original_task_def.json | jq '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
' > $BACKUP_DIR/restored_task_def.json

RESTORED_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://$BACKUP_DIR/restored_task_def.json \
  --region $REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)
echo "  Restored task definition: $RESTORED_TASK_DEF_ARN"

# Step 2: Update service
echo "[2/2] Updating service to use restored task definition..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $RESTORED_TASK_DEF_ARN \
  --force-new-deployment \
  --region $REGION \
  --query 'service.serviceName' \
  --output text > /dev/null

echo ""
echo "=== Lab 3 Fix Complete ==="
echo ""
echo "The UI service has been restored with the correct health check."
echo "Tasks should become healthy within 1-2 minutes."
echo ""
echo "Verify with:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME \\"
echo "    --query 'services[0].[runningCount,desiredCount]' --output text"
