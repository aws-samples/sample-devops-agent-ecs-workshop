#!/bin/bash
# ECS RDS Stress Injection Script
# Uses ECS Exec to run database stress queries from a container

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-catalog}"
REGION="${AWS_REGION:-us-east-1}"
STRESS_DURATION="${STRESS_DURATION:-120}"  # 2 minutes default
CONCURRENT_QUERIES="${CONCURRENT_QUERIES:-10}"

echo "=== ECS RDS Stress Injection ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Duration: ${STRESS_DURATION}s"
echo "Concurrent Queries: $CONCURRENT_QUERIES"
echo ""

# Step 1: Get running task ARN
echo "[1/4] Finding running task for service $SERVICE_NAME..."
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
echo "[2/4] Getting container name..."
CONTAINER_NAME=$(aws ecs describe-tasks \
  --cluster $CLUSTER_NAME \
  --tasks $TASK_ARN \
  --region $REGION \
  --query 'tasks[0].containers[0].name' \
  --output text)
echo "  Container: $CONTAINER_NAME"

# Step 3: Get RDS endpoint from environment
echo "[3/4] Getting database connection info..."
echo "  Note: Using environment variables from the container"

# Step 4: Execute stress queries via ECS Exec
echo "[4/4] Injecting RDS stress via ECS Exec..."
echo ""
echo "Starting database stress test..."

# Create a stress script that runs heavy queries
STRESS_SCRIPT='
END_TIME=$(($(date +%s) + '"$STRESS_DURATION"'))
QUERY_COUNT=0

# Install mysql client if needed
apt-get update -qq && apt-get install -y -qq mariadb-client >/dev/null 2>&1 || \
apk add --no-cache mariadb-client >/dev/null 2>&1 || \
yum install -y mariadb >/dev/null 2>&1 || true

echo "Starting RDS stress for '"$STRESS_DURATION"' seconds with '"$CONCURRENT_QUERIES"' concurrent queries..."

# Run stress queries in background
for i in $(seq 1 '"$CONCURRENT_QUERIES"'); do
  (
    while [ $(date +%s) -lt $END_TIME ]; do
      # Heavy SELECT with sorting and aggregation
      mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e \
        "SELECT COUNT(*), AVG(price), MAX(price), MIN(price) FROM product ORDER BY RAND() LIMIT 1000;" 2>/dev/null || true
      # Cross join for CPU stress
      mysql -h $DB_HOST -u $DB_USER -p$DB_PASSWORD $DB_NAME -e \
        "SELECT p1.id, p2.id FROM product p1, product p2 LIMIT 10000;" 2>/dev/null || true
      QUERY_COUNT=$((QUERY_COUNT + 2))
    done
  ) &
done

echo "Stress queries running in background..."
wait
echo "RDS stress complete. Executed approximately $(('"$CONCURRENT_QUERIES"' * '"$STRESS_DURATION"' / 2)) queries"
'

aws ecs execute-command \
  --cluster $CLUSTER_NAME \
  --task $TASK_ARN \
  --container $CONTAINER_NAME \
  --interactive \
  --region $REGION \
  --command "/bin/sh -c '$STRESS_SCRIPT'" || echo "Note: Stress may continue in background"

echo ""
echo "=== RDS Stress Injection Complete ==="
echo ""
echo "Injected: $CONCURRENT_QUERIES concurrent query streams for ${STRESS_DURATION} seconds"
echo ""
echo "Expected symptoms:"
echo "  - Increased RDS CPU utilization"
echo "  - Higher database connections"
echo "  - Increased read/write latency"
echo "  - Potential connection pool exhaustion"
echo "  - Slower API response times"
echo ""
echo "Monitor:"
echo "  aws cloudwatch get-metric-statistics --namespace AWS/RDS \\"
echo "    --metric-name CPUUtilization --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \\"
echo "    --start-time \$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \\"
echo "    --end-time \$(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Average"
echo ""
echo "Rollback: Stress auto-stops after ${STRESS_DURATION}s"
