#!/bin/bash
# Lab 1: CloudWatch Logs Not Delivered - Inject Script
# This script modifies the catalog service task definition to use a non-existent log group

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="catalog"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab1_backup"

echo "=== Lab 1: CloudWatch Logs Not Delivered - Inject ==="
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

TASK_DEF_FAMILY=$(echo $TASK_DEF_ARN | awk -F'/' '{print $NF}' | awk -F':' '{print $1}')
echo "  Current task definition: $TASK_DEF_ARN"

# Step 2: Save current task definition for rollback
echo "[2/4] Backing up current task definition..."
aws ecs describe-task-definition \
  --task-definition $TASK_DEF_ARN \
  --region $REGION \
  --query 'taskDefinition' > $BACKUP_DIR/original_task_def.json

# Save the original log group name
ORIGINAL_LOG_GROUP=$(cat $BACKUP_DIR/original_task_def.json | jq -r '.containerDefinitions[0].logConfiguration.options."awslogs-group"')
echo "$ORIGINAL_LOG_GROUP" > $BACKUP_DIR/original_log_group.txt
echo "  Original log group: $ORIGINAL_LOG_GROUP"

# Step 3: Create modified task definition with non-existent log group
echo "[3/4] Creating modified task definition with invalid log group..."
BROKEN_LOG_GROUP="/ecs/non-existent-log-group-12345"

# Create new task definition JSON
cat $BACKUP_DIR/original_task_def.json | jq --arg broken "$BROKEN_LOG_GROUP" '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
  .containerDefinitions[0].logConfiguration.options."awslogs-group" = $broken
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
echo "=== Lab 1 Injection Complete ==="
echo ""
echo "Issue injected: Task definition now references non-existent log group"
echo "  Broken log group: $BROKEN_LOG_GROUP"
echo ""
echo "Expected symptoms:"
echo "  - Catalog service tasks failing to start"
echo "  - Service events showing 'ResourceInitializationError'"
echo "  - No new logs appearing in CloudWatch"
echo ""
echo "Investigation prompts for DevOps Agent:"
echo "  'Why is the catalog service failing to start new tasks?'"
echo "  'Check the ECS service events for the catalog service'"
echo "  'What is the log configuration for the catalog service task definition?'"
echo ""
echo "To fix: ./labs/lab1-logs-not-delivered/fix.sh"
