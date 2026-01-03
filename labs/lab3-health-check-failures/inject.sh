#!/bin/bash
# Lab 3: Health Check Failures - Inject Script
# This script modifies the UI service task definition to use an incorrect health check endpoint

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="ui"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab3_backup"

echo "=== Lab 3: Health Check Failures - Inject ==="
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

# Step 3: Create modified task definition with wrong health check
echo "[3/4] Creating modified task definition with invalid health check..."
WRONG_HEALTH_PATH="/wrong-health-endpoint"

# Create new task definition JSON with broken health check
cat $BACKUP_DIR/original_task_def.json | jq --arg wrong "$WRONG_HEALTH_PATH" '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
  .containerDefinitions[0].healthCheck.command = ["CMD-SHELL", "curl -f http://localhost:8080" + $wrong + " || exit 1"]
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
echo "=== Lab 3 Injection Complete ==="
echo ""
echo "Issue injected: Health check now uses non-existent endpoint"
echo "  Broken health check path: $WRONG_HEALTH_PATH"
echo ""
echo "Expected symptoms:"
echo "  - Tasks continuously restart"
echo "  - Service never stabilizes"
echo "  - Service events show 'unhealthy' messages"
echo "  - Intermittent 503 errors for customers"
echo ""
echo "Investigation prompts for DevOps Agent:"
echo "  'Why does the UI service keep restarting tasks?'"
echo "  'Show me the service events for the UI service - are there health check failures?'"
echo "  'What health check configuration is the UI service using?'"
echo ""
echo "To fix: ./labs/lab3-health-check-failures/fix.sh"
