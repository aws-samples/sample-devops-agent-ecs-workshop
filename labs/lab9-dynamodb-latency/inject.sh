#!/bin/bash
# ECS DynamoDB Latency Injection Script
# Uses ECS Exec to add network latency to DynamoDB endpoints using tc

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-carts}"
REGION="${AWS_REGION:-us-east-1}"
LATENCY_MS="${LATENCY_MS:-500}"  # 500ms latency default
DURATION="${DURATION:-300}"  # 5 minutes default

echo "=== ECS DynamoDB Latency Injection ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Latency: ${LATENCY_MS}ms"
echo "Duration: ${DURATION}s"
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

# Step 3: Inject network latency via ECS Exec
echo "[3/3] Injecting network latency via ECS Exec..."
echo ""
echo "Adding ${LATENCY_MS}ms latency to DynamoDB traffic..."

# Note: This requires NET_ADMIN capability on the container
# The script uses tc (traffic control) to add latency
LATENCY_SCRIPT='
# Install iproute2 for tc command
apt-get update -qq && apt-get install -y -qq iproute2 >/dev/null 2>&1 || \
apk add --no-cache iproute2 >/dev/null 2>&1 || \
yum install -y iproute >/dev/null 2>&1

# Get DynamoDB endpoint IPs
DYNAMODB_IPS=$(getent hosts dynamodb.'"$REGION"'.amazonaws.com | awk "{print \$1}" | head -5)

if [ -z "$DYNAMODB_IPS" ]; then
  echo "Warning: Could not resolve DynamoDB endpoint, applying latency to all traffic"
  tc qdisc add dev eth0 root netem delay '"$LATENCY_MS"'ms 2>/dev/null || \
  tc qdisc change dev eth0 root netem delay '"$LATENCY_MS"'ms
else
  echo "DynamoDB IPs: $DYNAMODB_IPS"
  # Add latency to DynamoDB traffic
  tc qdisc add dev eth0 root handle 1: prio 2>/dev/null || true
  tc qdisc add dev eth0 parent 1:3 handle 30: netem delay '"$LATENCY_MS"'ms 2>/dev/null || \
  tc qdisc change dev eth0 parent 1:3 handle 30: netem delay '"$LATENCY_MS"'ms
  
  for IP in $DYNAMODB_IPS; do
    tc filter add dev eth0 protocol ip parent 1:0 prio 3 u32 match ip dst $IP/32 flowid 1:3 2>/dev/null || true
  done
fi

echo "Latency injection active for '"$DURATION"' seconds"
echo "Current tc rules:"
tc qdisc show dev eth0

# Schedule cleanup
(sleep '"$DURATION"' && tc qdisc del dev eth0 root 2>/dev/null && echo "Latency removed") &

echo "Latency will auto-remove after '"$DURATION"' seconds"
'

aws ecs execute-command \
  --cluster $CLUSTER_NAME \
  --task $TASK_ARN \
  --container $CONTAINER_NAME \
  --interactive \
  --region $REGION \
  --command "/bin/sh -c '$LATENCY_SCRIPT'" || echo "Note: May require NET_ADMIN capability"

echo ""
echo "=== DynamoDB Latency Injection Complete ==="
echo ""
echo "Injected: ${LATENCY_MS}ms latency to DynamoDB traffic for ${DURATION} seconds"
echo ""
echo "Expected symptoms:"
echo "  - Slow cart operations (add/remove/view)"
echo "  - Increased API response times"
echo "  - Potential timeouts in cart service"
echo "  - Higher latency in CloudWatch metrics"
echo ""
echo "Monitor:"
echo "  aws cloudwatch get-metric-statistics --namespace AWS/DynamoDB \\"
echo "    --metric-name SuccessfulRequestLatency --dimensions Name=TableName,Value=<table-name> Name=Operation,Value=GetItem \\"
echo "    --start-time \$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \\"
echo "    --end-time \$(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Average"
echo ""
echo "Rollback (auto-removes after ${DURATION}s, or manually):"
echo "  ./fault-injection/rollback-dynamodb-latency.sh"
