#!/bin/bash
# Lab 5: Task Resource Limits (OOM) - Inject Script
# This script modifies the checkout service task definition to use extremely low memory limits

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="checkout"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab5_backup"

echo "=== Lab 5: Task Resource Limits (OOM) - Inject ==="
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

# Save original memory settings
ORIGINAL_MEMORY=$(cat $BACKUP_DIR/original_task_def.json | jq -r '.memory // .containerDefinitions[0].memory')
echo "$ORIGINAL_MEMORY" > $BACKUP_DIR/original_memory.txt
echo "  Original memory: ${ORIGINAL_MEMORY}MB"

# Step 3: Create modified task definition with low memory
echo "[3/4] Creating modified task definition with low memory (128MB)..."
LOW_MEMORY="128"

cat $BACKUP_DIR/original_task_def.json | jq --arg mem "$LOW_MEMORY" '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
  .memory = $mem |
  .containerDefinitions[0].memory = ($mem | tonumber)
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
echo "=== Lab 5 Injection Complete ==="
echo ""
echo "Issue injected: Checkout service memory reduced to 128MB (was ${ORIGINAL_MEMORY}MB)"
echo ""
echo "Expected symptoms:"
echo "  - Tasks crash immediately after starting"
echo "  - Exit code 137 (OOM kill: 128 + 9 SIGKILL)"
echo "  - Checkout unavailable - customers cannot complete purchases"
echo "  - Rapid task cycling as ECS keeps trying to start new tasks"
echo ""
echo "Investigation prompts for DevOps Agent:"
echo "  'Why is the checkout service crashing? The tasks keep restarting.'"
echo "  'What is the exit code for the stopped checkout tasks? Is it an OOM kill?'"
echo "  'Show me the memory configuration for the checkout service task definition'"
echo ""
echo "To fix: ./labs/lab5-task-resource-limits/fix.sh"
