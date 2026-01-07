#!/bin/bash
# Lab 8: Auto-Scaling Not Working - Inject Script
# This script disables CloudWatch alarm actions and injects CPU stress
# Result: CPU spikes but service doesn't scale

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-ui}"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab8_backup"
STRESS_DURATION="${STRESS_DURATION:-300}"  # 5 minutes default
CPU_WORKERS="${CPU_WORKERS:-2}"

echo "=== Lab 8: Auto-Scaling Not Working - Inject ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Create backup directory
mkdir -p $BACKUP_DIR

# Step 1: Find the auto-scaling alarms for this service
echo "[1/5] Finding auto-scaling alarms for service $SERVICE_NAME..."
ALARM_NAMES=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix "TargetTracking-service/$CLUSTER_NAME/$SERVICE_NAME" \
  --region $REGION \
  --query 'MetricAlarms[*].AlarmName' \
  --output text)

if [ -z "$ALARM_NAMES" ] || [ "$ALARM_NAMES" == "None" ]; then
  echo "ERROR: No auto-scaling alarms found for service $SERVICE_NAME"
  echo "Make sure auto-scaling is configured for this service."
  exit 1
fi

echo "  Found alarms: $ALARM_NAMES"

# Step 2: Backup alarm names
echo "[2/5] Backing up alarm configuration..."
echo "$ALARM_NAMES" > $BACKUP_DIR/alarm_names.txt
echo "  Saved alarm names to $BACKUP_DIR/alarm_names.txt"

# Step 3: Disable alarm actions
echo "[3/5] Disabling alarm actions (breaking auto-scaling)..."
for ALARM in $ALARM_NAMES; do
  aws cloudwatch disable-alarm-actions \
    --alarm-names "$ALARM" \
    --region $REGION
  echo "  Disabled actions for: $ALARM"
done

# Step 4: Get running task for CPU stress
echo "[4/5] Finding running task for CPU stress injection..."
TASK_ARN=$(aws ecs list-tasks \
  --cluster $CLUSTER_NAME \
  --service-name $SERVICE_NAME \
  --desired-status RUNNING \
  --region $REGION \
  --query 'taskArns[0]' \
  --output text)

if [ "$TASK_ARN" == "None" ] || [ -z "$TASK_ARN" ]; then
  echo "ERROR: No running tasks found for service $SERVICE_NAME"
  exit 1
fi

TASK_ID=$(echo $TASK_ARN | awk -F'/' '{print $NF}')
echo "  Task ARN: $TASK_ARN"

# Get container name
CONTAINER_NAME=$(aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASK_ARN \
  --region $REGION \
  --query 'tasks[0].containers[0].name' \
  --output text)
echo "  Container: $CONTAINER_NAME"

# Step 5: Inject CPU stress via ECS Exec
echo "[5/5] Injecting CPU stress via ECS Exec..."
echo ""

aws ecs execute-command \
  --cluster $CLUSTER_NAME \
  --task $TASK_ARN \
  --container $CONTAINER_NAME \
  --interactive \
  --region $REGION \
  --command "/bin/sh -c 'apt-get update -qq && apt-get install -y -qq stress-ng >/dev/null 2>&1 || apk add --no-cache stress-ng >/dev/null 2>&1 || yum install -y stress-ng >/dev/null 2>&1; nohup stress-ng --cpu $CPU_WORKERS --timeout ${STRESS_DURATION}s > /tmp/stress.log 2>&1 & echo CPU stress started with $CPU_WORKERS workers for ${STRESS_DURATION}s; sleep 2; ps aux | grep stress'"

echo ""
echo "=== Lab 8 Injection Complete ==="
echo ""
echo "Issues injected:"
echo "  1. CloudWatch alarm actions DISABLED - scaling won't trigger"
echo "  2. CPU stress running - utilization will spike"
echo ""
echo "Expected symptoms:"
echo "  - CPU utilization high in CloudWatch metrics"
echo "  - CloudWatch alarm in ALARM state"
echo "  - But service does NOT scale out (stays at current task count)"
echo "  - Application may become slow/unresponsive"
echo ""
echo "Investigation prompts for DevOps Agent:"
echo "  'Why isn't my ECS service scaling even though CPU is high?'"
echo "  'Check the auto-scaling configuration for the $SERVICE_NAME service'"
echo "  'Show me the CloudWatch alarms for the $SERVICE_NAME service'"
echo ""
echo "To fix: ./labs/lab8-autoscaling-broken/fix.sh"
