#!/bin/bash
# Lab 5: Task Resource Limits (OOM) - Inject Script
# This script modifies the checkout service to trigger OOM by adding memory stress
# Note: Fargate minimum memory is 512MB, so we use stress to exceed the limit

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

# Save original settings
ORIGINAL_MEMORY=$(cat $BACKUP_DIR/original_task_def.json | jq -r '.memory // .containerDefinitions[0].memory')
echo "$ORIGINAL_MEMORY" > $BACKUP_DIR/original_memory.txt
echo "  Original memory: ${ORIGINAL_MEMORY}MB"

# Step 3: Create modified task definition with memory stress sidecar
echo "[3/4] Creating modified task definition with memory stress..."

# Add a stress sidecar container that will consume memory and cause OOM
# The main container stays the same, but the sidecar eats all available memory
# Get task memory limit and calculate stress amount to exceed it
TASK_MEMORY=$(cat $BACKUP_DIR/original_task_def.json | jq -r '.memory')
STRESS_MEMORY=$((TASK_MEMORY + 512))  # Request more than task limit to guarantee OOM

# Remove any existing memory-stress container first, then add fresh one
cat $BACKUP_DIR/original_task_def.json | jq --arg stress_mem "${STRESS_MEMORY}M" '
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy) |
  .containerDefinitions = [.containerDefinitions[] | select(.name != "memory-stress")] |
  .containerDefinitions += [{
    "name": "memory-stress",
    "image": "polinux/stress",
    "essential": true,
    "command": ["stress", "--vm", "1", "--vm-bytes", $stress_mem, "--vm-hang", "0"],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": .containerDefinitions[0].logConfiguration.options["awslogs-group"],
        "awslogs-region": .containerDefinitions[0].logConfiguration.options["awslogs-region"],
        "awslogs-stream-prefix": "memory-stress"
      }
    }
  }]
' > $BACKUP_DIR/broken_task_def.json

echo "  Task memory: ${TASK_MEMORY}MB, Stress will request: ${STRESS_MEMORY}MB"

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
echo "Issue injected: Added memory-stress sidecar that requests ${STRESS_MEMORY}MB (task limit: ${ORIGINAL_MEMORY}MB)"
echo ""
echo "Expected symptoms:"
echo "  - Tasks crash shortly after starting due to OOM"
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
