#!/bin/bash
# Lab 7: CPU Stress - Fix Script
# Kills stress-ng processes in the container

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-catalog}"
REGION="${AWS_REGION:-us-east-1}"

echo "=== Lab 7: CPU Stress - Fix ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Get running task ARN
echo "[1/3] Finding running task for service $SERVICE_NAME..."
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
echo "  Task ARN: $TASK_ARN"

# Get container name
echo "[2/3] Getting container name..."
CONTAINER_NAME=$(aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASK_ARN \
  --region $REGION \
  --query 'tasks[0].containers[0].name' \
  --output text)
echo "  Container: $CONTAINER_NAME"

# Kill stress processes
echo "[3/3] Killing stress-ng processes..."
aws ecs execute-command \
  --cluster $CLUSTER_NAME \
  --task $TASK_ARN \
  --container $CONTAINER_NAME \
  --interactive \
  --region $REGION \
  --command "/bin/sh -c 'pkill -9 stress-ng 2>/dev/null && echo \"Stress processes killed\" || echo \"No stress processes found\"'"

echo ""
echo "=== Lab 7 Fix Complete ==="
echo ""
echo "CPU stress processes have been killed."
echo "CPU utilization should return to normal within a few minutes."
echo ""
echo "Verify with:"
echo "  aws cloudwatch get-metric-statistics --namespace AWS/ECS \\"
echo "    --metric-name CPUUtilization --dimensions Name=ServiceName,Value=$SERVICE_NAME \\"
echo "    --start-time \$(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ') --end-time \$(date -u '+%Y-%m-%dT%H:%M:%SZ') \\"
echo "    --period 60 --statistics Average"
