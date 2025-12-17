#!/bin/bash
# ECS CPU Stress Injection Script
# Uses ECS Exec to run stress-ng inside the container to generate real CPU load

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-catalog}"
REGION="${AWS_REGION:-us-east-1}"
STRESS_DURATION="${STRESS_DURATION:-300}"  # 5 minutes default
CPU_WORKERS="${CPU_WORKERS:-2}"

echo "=== ECS CPU Stress Injection ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Duration: ${STRESS_DURATION}s"
echo "CPU Workers: $CPU_WORKERS"
echo ""

# Step 1: Get running task ARN
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

TASK_ID=$(echo $TASK_ARN | awk -F'/' '{print $NF}')
echo "  Task ARN: $TASK_ARN"
echo "  Task ID: $TASK_ID"

# Step 2: Get container name
echo "[2/3] Getting container name..."
CONTAINER_NAME=$(aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASK_ARN \
  --region $REGION \
  --query 'tasks[0].containers[0].name' \
  --output text)
echo "  Container: $CONTAINER_NAME"

# Step 3: Execute stress command via ECS Exec
echo "[3/3] Injecting CPU stress via ECS Exec..."
echo ""
echo "Installing stress-ng and starting CPU stress..."

# Run stress in background using nohup so it continues after exec disconnects
aws ecs execute-command \
  --cluster $CLUSTER_NAME \
  --task $TASK_ARN \
  --container $CONTAINER_NAME \
  --interactive \
  --region $REGION \
  --command "/bin/sh -c 'apt-get update -qq && apt-get install -y -qq stress-ng >/dev/null 2>&1 || apk add --no-cache stress-ng >/dev/null 2>&1 || yum install -y stress-ng >/dev/null 2>&1; nohup stress-ng --cpu $CPU_WORKERS --timeout ${STRESS_DURATION}s --metrics-brief > /tmp/stress.log 2>&1 &; echo CPU stress started with $CPU_WORKERS workers for ${STRESS_DURATION}s; sleep 2; ps aux | grep stress'"

echo ""
echo "=== CPU Stress Injection Complete ==="
echo ""
echo "Injected: $CPU_WORKERS CPU workers for ${STRESS_DURATION} seconds"
echo ""
echo "Expected symptoms:"
echo "  - CPU utilization spike in CloudWatch Container Insights"
echo "  - Increased response latency"
echo "  - Potential CPU throttling (if limits set)"
echo "  - Service degradation visible in dashboard"
echo ""
echo "Monitor:"
echo "  aws cloudwatch get-metric-statistics --namespace ECS/ContainerInsights \\"
echo "    --metric-name CpuUtilized --dimensions Name=ClusterName,Value=$CLUSTER_NAME \\"
echo "    Name=ServiceName,Value=$SERVICE_NAME --start-time \$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \\"
echo "    --end-time \$(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Average"
echo ""
echo "  CloudWatch Dashboard: Check the ECS dashboard for CPU metrics"
echo ""
echo "Rollback (stress auto-stops after ${STRESS_DURATION}s, or manually):"
echo "  ./fault-injection/rollback-cpu-stress.sh"
