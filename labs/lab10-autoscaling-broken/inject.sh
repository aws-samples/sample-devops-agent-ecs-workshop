#!/bin/bash
# Lab 10: Auto-Scaling Not Working
# Issue: CloudWatch alarm actions disabled + CPU stress via sidecar
# Symptom: High CPU but service doesn't scale

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-catalog}"
BACKUP_DIR="/tmp/lab10_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 10: Auto-Scaling Not Working"
echo "=============================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Region: $AWS_REGION"
echo ""
echo "Setting up auto-scaling..."

# Create backup directory
mkdir -p $BACKUP_DIR

RESOURCE_ID="service/${CLUSTER_NAME}/${SERVICE_NAME}"
POLICY_NAME="${CLUSTER_NAME}-${SERVICE_NAME}-cpu-scaling"

# Step 1: Create auto-scaling target for catalog service
echo "[1/5] Creating auto-scaling target..."
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id "$RESOURCE_ID" \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 1 \
  --max-capacity 4 \
  --region $AWS_REGION

echo "  Auto-scaling target created (min: 1, max: 4)"

# Step 2: Create target tracking scaling policy (20% CPU threshold)
echo "[2/5] Creating CPU-based scaling policy..."
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id "$RESOURCE_ID" \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name "$POLICY_NAME" \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 20.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleOutCooldown": 60,
    "ScaleInCooldown": 300
  }' \
  --region $AWS_REGION > /dev/null

echo "  Scaling policy created (target: 20% CPU)"

# Wait for alarms to be created
echo "  Waiting for CloudWatch alarms to be created..."
sleep 10

# Step 3: Find and disable auto-scaling alarms
echo "[3/5] Disabling alarm actions (injecting the issue)..."
ALARM_NAMES=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix "TargetTracking-service/$CLUSTER_NAME/$SERVICE_NAME" \
  --region $AWS_REGION \
  --query 'MetricAlarms[*].AlarmName' \
  --output text)

if [ -z "$ALARM_NAMES" ] || [ "$ALARM_NAMES" == "None" ]; then
  echo "  Waiting for alarms to be created..."
  sleep 10
  ALARM_NAMES=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "TargetTracking-service/$CLUSTER_NAME/$SERVICE_NAME" \
    --region $AWS_REGION \
    --query 'MetricAlarms[*].AlarmName' \
    --output text)
fi

if [ -n "$ALARM_NAMES" ] && [ "$ALARM_NAMES" != "None" ]; then
  echo "$ALARM_NAMES" > $BACKUP_DIR/alarm_names.txt
  for ALARM in $ALARM_NAMES; do
    aws cloudwatch disable-alarm-actions --alarm-names "$ALARM" --region $AWS_REGION
    echo "  Disabled: $ALARM"
  done
fi

# Step 4: Get current task definition and add stress sidecar
echo "[4/5] Adding CPU stress sidecar container..."

CURRENT_TASK_DEF=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $AWS_REGION \
  --query 'services[0].taskDefinition' \
  --output text)

echo "$CURRENT_TASK_DEF" > $BACKUP_DIR/original_task_def.txt

aws ecs describe-task-definition \
  --task-definition $CURRENT_TASK_DEF \
  --region $AWS_REGION \
  --query 'taskDefinition' > $BACKUP_DIR/task_def.json

# Check if cpu-stress container already exists
if jq -e '.containerDefinitions[] | select(.name == "cpu-stress")' $BACKUP_DIR/task_def.json > /dev/null 2>&1; then
  echo "  CPU stress sidecar already exists in task definition"
  echo "  Run './labs/lab10-autoscaling-broken/fix.sh' first to restore, then try again"
  exit 1
fi

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

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://$BACKUP_DIR/new_task_def.json \
  --region $AWS_REGION \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "  New task definition: $NEW_TASK_DEF_ARN"

# Step 5: Update service with new task definition
echo "[5/5] Updating service with stress sidecar..."
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
echo "The ${SERVICE_NAME} service now has auto-scaling configured."
echo "A CPU stress sidecar is consuming resources (should trigger scaling at 20%)."
echo "But the service isn't scaling! Users are complaining about slow response times."
echo ""
echo "YOUR TASK:"
echo "1. Use AWS DevOps Agent to investigate why auto-scaling isn't working"
echo "2. Check CloudWatch metrics and alarms"
echo "3. Examine the auto-scaling configuration"
echo "4. Identify why the alarm isn't triggering scaling actions"
echo ""
echo "HINTS:"
echo "- Check if CloudWatch alarms are in ALARM state"
echo "- Look at the alarm's 'ActionsEnabled' setting"
echo "- Review Application Auto Scaling policies"
echo ""
echo "Run './labs/lab10-autoscaling-broken/fix.sh' when ready to restore"
echo "=============================================="
