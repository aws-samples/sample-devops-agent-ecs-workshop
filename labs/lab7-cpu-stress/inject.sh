#!/bin/bash
# Lab 7: CPU Stress
# Adds a stress sidecar container to generate CPU load
# Symptom: High CPU utilization, increased response latency

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-catalog}"
BACKUP_DIR="/tmp/lab7_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 7: CPU Stress Injection"
echo "=============================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Region: $AWS_REGION"
echo ""

# Create backup directory
mkdir -p $BACKUP_DIR

# Step 1: Get current task definition
echo "[1/3] Getting current task definition..."
CURRENT_TASK_DEF=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[0].taskDefinition' \
  --output text)

# Save original task definition ARN for restore
echo "$CURRENT_TASK_DEF" > $BACKUP_DIR/original_task_def.txt
echo "  Current: $CURRENT_TASK_DEF"

# Step 2: Create new task definition with stress sidecar
echo "[2/3] Adding CPU stress sidecar container..."

# Get task definition details and save to file
aws ecs describe-task-definition \
  --task-definition $CURRENT_TASK_DEF \
  --region $AWS_REGION \
  --query 'taskDefinition' > $BACKUP_DIR/task_def.json

# Check if cpu-stress container already exists
if jq -e '.containerDefinitions[] | select(.name == "cpu-stress")' $BACKUP_DIR/task_def.json > /dev/null 2>&1; then
  echo "  CPU stress sidecar already exists in task definition"
  echo "  Run './labs/lab7-cpu-stress/fix.sh' first to restore, then try again"
  exit 1
fi

# Create new task definition with stress sidecar using jq
# Use --cpu 1 --cpu-load 70 to generate high but not overwhelming CPU load
# This allows the main container to still pass health checks
jq '
  .containerDefinitions += [{
    "name": "cpu-stress",
    "image": "alpine:latest",
    "essential": false,
    "command": ["sh", "-c", "apk add --no-cache stress-ng && stress-ng --cpu 1 --cpu-load 70 --timeout 0"],
    "cpu": 256,
    "memory": 256,
    "logConfiguration": .containerDefinitions[0].logConfiguration
  }] |
  del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
' $BACKUP_DIR/task_def.json > $BACKUP_DIR/new_task_def.json

# Register new task definition
NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://$BACKUP_DIR/new_task_def.json \
  --region $AWS_REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "  New task definition: $NEW_TASK_DEF_ARN"

# Step 3: Update service with new task definition
echo "[3/3] Updating service with stress sidecar..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --task-definition $NEW_TASK_DEF_ARN \
  --region $AWS_REGION \
  --query 'service.serviceName' \
  --output text > /dev/null

echo "  Service updated. Waiting for deployment..."
echo "  (This may take 1-2 minutes)"

aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION 2>/dev/null || echo "  Service deployment in progress..."

echo ""
echo "Issue injected successfully!"
echo ""
echo "=============================================="
echo "SCENARIO:"
echo "=============================================="
echo "The $SERVICE_NAME service is experiencing high CPU utilization."
echo "Users report slow page loads and timeouts."
echo ""
echo "YOUR TASK:"
echo "1. Use AWS DevOps Agent to investigate the CPU spike"
echo "2. Check CloudWatch Container Insights for CPU metrics"
echo "3. Identify which container is consuming CPU"
echo "4. Determine if it's application load or external stress"
echo ""
echo "HINTS:"
echo "- Check Container Insights CPU metrics"
echo "- Look at ECS service metrics in CloudWatch"
echo "- Examine the task definition for unexpected containers"
echo ""
echo "Run './labs/lab7-cpu-stress/fix.sh' to restore the service"
echo "=============================================="
