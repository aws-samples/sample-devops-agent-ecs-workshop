#!/bin/bash
# Lab 9: DynamoDB Attack Simulation
# Deploys multiple aggressive stress tasks that hammer DynamoDB
# Creates visible throttling that looks like a DDoS attack

set -e

BACKUP_DIR="/tmp/lab9_backup"
NUM_STRESS_TASKS="${NUM_STRESS_TASKS:-5}"  # Run 5 parallel stress tasks

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

mkdir -p $BACKUP_DIR

echo "=============================================="
echo "Lab 9: DynamoDB Stress Attack Simulation"
echo "=============================================="
echo ""

# Auto-discover cluster name if not set
if [ -z "$CLUSTER_NAME" ]; then
  CLUSTER_NAME=$(aws ecs list-clusters --region $AWS_REGION --query 'clusterArns[0]' --output text 2>/dev/null | awk -F'/' '{print $NF}')
  if [ -z "$CLUSTER_NAME" ] || [ "$CLUSTER_NAME" == "None" ]; then
    CLUSTER_NAME="retail-store-ecs-cluster"
  fi
fi
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"

# Step 1: Discover DynamoDB table
echo ""
echo "[1/5] Discovering DynamoDB table..."
TABLE_NAME=$(aws dynamodb list-tables --region $AWS_REGION --query "TableNames[?contains(@, 'cart') || contains(@, 'Cart')]" --output text 2>/dev/null | head -1)

if [ -z "$TABLE_NAME" ] || [ "$TABLE_NAME" == "None" ]; then
  echo "ERROR: No carts DynamoDB table found in region $AWS_REGION"
  exit 1
fi
echo "  Found table: $TABLE_NAME"

# Step 2: Switch to provisioned capacity with LOW limits to guarantee throttling
echo ""
echo "[2/5] Switching DynamoDB to provisioned capacity (low limits)..."

# Backup current settings
TABLE_INFO=$(aws dynamodb describe-table --table-name $TABLE_NAME --region $AWS_REGION 2>/dev/null)
BILLING_MODE=$(echo "$TABLE_INFO" | jq -r '.Table.BillingModeSummary.BillingMode // "PROVISIONED"')
echo "$BILLING_MODE" > $BACKUP_DIR/billing_mode.txt
echo "$TABLE_NAME" > $BACKUP_DIR/table_name.txt

# Get GSI names if any
GSI_NAMES=$(echo "$TABLE_INFO" | jq -r '.Table.GlobalSecondaryIndexes[]?.IndexName // empty' 2>/dev/null)
echo "$GSI_NAMES" > $BACKUP_DIR/gsi_names.txt

if [ "$BILLING_MODE" == "PAY_PER_REQUEST" ]; then
  echo "  Current: On-demand capacity"
  echo "  Switching to provisioned with 5 RCU/5 WCU..."
  
  # Build GSI throughput updates if GSIs exist
  GSI_UPDATES=""
  if [ -n "$GSI_NAMES" ]; then
    for gsi in $GSI_NAMES; do
      if [ -n "$GSI_UPDATES" ]; then
        GSI_UPDATES="$GSI_UPDATES,"
      fi
      GSI_UPDATES="${GSI_UPDATES}{\"Update\":{\"IndexName\":\"$gsi\",\"ProvisionedThroughput\":{\"ReadCapacityUnits\":5,\"WriteCapacityUnits\":5}}}"
    done
  fi
  
  if [ -n "$GSI_UPDATES" ]; then
    aws dynamodb update-table \
      --table-name $TABLE_NAME \
      --billing-mode PROVISIONED \
      --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
      --global-secondary-index-updates "[$GSI_UPDATES]" \
      --region $AWS_REGION > /dev/null
  else
    aws dynamodb update-table \
      --table-name $TABLE_NAME \
      --billing-mode PROVISIONED \
      --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
      --region $AWS_REGION > /dev/null
  fi
  
  echo "  Waiting for table to update..."
  aws dynamodb wait table-exists --table-name $TABLE_NAME --region $AWS_REGION
  sleep 10
else
  CURRENT_RCU=$(echo "$TABLE_INFO" | jq -r '.Table.ProvisionedThroughput.ReadCapacityUnits')
  CURRENT_WCU=$(echo "$TABLE_INFO" | jq -r '.Table.ProvisionedThroughput.WriteCapacityUnits')
  echo "$CURRENT_RCU" > $BACKUP_DIR/original_rcu.txt
  echo "$CURRENT_WCU" > $BACKUP_DIR/original_wcu.txt
  echo "  Current: ${CURRENT_RCU} RCU, ${CURRENT_WCU} WCU"
  
  if [ "$CURRENT_RCU" -gt 5 ]; then
    echo "  Reducing to 5 RCU/5 WCU..."
    aws dynamodb update-table \
      --table-name $TABLE_NAME \
      --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
      --region $AWS_REGION > /dev/null
    sleep 10
  fi
fi

echo "  Table now has 5 RCU (will throttle easily)"

# Step 3: Get network config
echo ""
echo "[3/5] Getting network configuration..."
CARTS_SERVICE=$(aws ecs list-services --cluster $CLUSTER_NAME --region $AWS_REGION \
  --query "serviceArns[?contains(@, 'cart')]" --output text 2>/dev/null | head -1 | awk -F'/' '{print $NF}')

if [ -z "$CARTS_SERVICE" ] || [ "$CARTS_SERVICE" == "None" ]; then
  CARTS_SERVICE="carts"
fi

NETWORK_CONFIG=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $CARTS_SERVICE --region $AWS_REGION \
  --query 'services[0].networkConfiguration.awsvpcConfiguration' --output json 2>/dev/null)

SUBNETS=$(echo "$NETWORK_CONFIG" | jq -r '.subnets | join(",")')
SECURITY_GROUPS=$(echo "$NETWORK_CONFIG" | jq -r '.securityGroups | join(",")')

TASK_DEF_ARN=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $CARTS_SERVICE --region $AWS_REGION \
  --query 'services[0].taskDefinition' --output text 2>/dev/null)

TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_DEF_ARN --region $AWS_REGION --query 'taskDefinition' 2>/dev/null)
EXECUTION_ROLE=$(echo "$TASK_DEF" | jq -r '.executionRoleArn')
TASK_ROLE=$(echo "$TASK_DEF" | jq -r '.taskRoleArn')
LOG_GROUP=$(echo "$TASK_DEF" | jq -r '.containerDefinitions[0].logConfiguration.options["awslogs-group"]')

echo "  Subnets: $SUBNETS"

# Step 4: Register aggressive stress task definition
echo ""
echo "[4/5] Registering aggressive stress task definition..."

cat > $BACKUP_DIR/stress_task_def.json <<TASKDEF
{
  "family": "dynamodb-stress-attack",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024",
  "memory": "2048",
  "executionRoleArn": "${EXECUTION_ROLE}",
  "taskRoleArn": "${TASK_ROLE}",
  "containerDefinitions": [
    {
      "name": "attacker",
      "image": "amazon/aws-cli:latest",
      "essential": true,
      "entryPoint": ["sh", "-c"],
      "command": [
        "echo 'ATTACK STARTED on ${TABLE_NAME}'; echo 'Launching continuous scan flood...'; while true; do for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do aws dynamodb scan --table-name ${TABLE_NAME} --region ${AWS_REGION} --select COUNT 2>&1 | grep -E 'Count|Throttl' & done; wait; done"
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "${LOG_GROUP}",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "dynamodb-attack"
        }
      }
    }
  ]
}
TASKDEF

aws ecs register-task-definition \
  --cli-input-json file://$BACKUP_DIR/stress_task_def.json \
  --region $AWS_REGION > /dev/null

echo "  Registered dynamodb-stress-attack task"

# Step 5: Launch multiple stress tasks
echo ""
echo "[5/5] Launching $NUM_STRESS_TASKS parallel attack tasks..."

TASK_ARNS=""
for i in $(seq 1 $NUM_STRESS_TASKS); do
  TASK_ARN=$(aws ecs run-task \
    --cluster $CLUSTER_NAME \
    --task-definition dynamodb-stress-attack \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=DISABLED}" \
    --region $AWS_REGION \
    --query 'tasks[0].taskArn' \
    --output text 2>/dev/null)
  
  echo "  Started task $i: $(echo $TASK_ARN | awk -F'/' '{print $NF}')"
  TASK_ARNS="$TASK_ARNS $TASK_ARN"
done

echo "$TASK_ARNS" > $BACKUP_DIR/stress_task_arns.txt
echo "$CLUSTER_NAME" > $BACKUP_DIR/cluster_name.txt

echo ""
echo "Waiting for attack tasks to start..."
sleep 15

echo ""
echo "=== ATTACK SIMULATION ACTIVE ==="
echo ""
echo "=============================================="
echo "SCENARIO:"
echo "=============================================="
echo "ALERT: Unusual DynamoDB activity detected!"
echo "The carts service is experiencing severe throttling."
echo "Users cannot add items to cart - all operations failing."
echo "CloudWatch shows massive spike in ThrottledRequests."
echo ""
echo "WHAT'S HAPPENING:"
echo "- $NUM_STRESS_TASKS rogue tasks are flooding DynamoDB with scans"
echo "- Table capacity reduced to 5 RCU (easily overwhelmed)"
echo "- Legitimate carts service requests are being throttled"
echo "- This simulates a DDoS or runaway process scenario"
echo ""
echo "YOUR TASK:"
echo "1. Investigate the DynamoDB throttling alerts"
echo "2. Find the source of excessive read requests"
echo "3. Identify the rogue ECS tasks"
echo "4. Stop the attack and restore service"
echo ""
echo "INVESTIGATION PROMPTS:"
echo "- 'DynamoDB is being throttled heavily. What's consuming all the read capacity?'"
echo "- 'carts table is throttled'"
echo "- 'why is DynamoDB throttling?'"
echo ""
echo "Run './labs/lab9-dynamodb-attack/fix.sh' to stop the attack"
echo "=============================================="
