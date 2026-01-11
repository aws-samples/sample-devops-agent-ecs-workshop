#!/bin/bash
# Lab 10: Auto-Scaling Not Working - Fix Script
# Re-enables alarm actions and removes stress sidecar

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-catalog}"
BACKUP_DIR="/tmp/lab10_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 10: Auto-Scaling Not Working - Fix"
echo "=============================================="
echo ""

# Step 1: Re-enable alarm actions
echo "[1/3] Re-enabling CloudWatch alarm actions..."

if [ -f "$BACKUP_DIR/alarm_names.txt" ]; then
    ALARM_NAMES=$(cat $BACKUP_DIR/alarm_names.txt)
    for ALARM in $ALARM_NAMES; do
        aws cloudwatch enable-alarm-actions --alarm-names "$ALARM" --region $AWS_REGION 2>/dev/null || true
        echo "  Enabled: $ALARM"
    done
else
    # Find alarms by prefix
    ALARM_NAMES=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "TargetTracking-service/$CLUSTER_NAME/$SERVICE_NAME" \
        --region $AWS_REGION \
        --query 'MetricAlarms[*].AlarmName' \
        --output text 2>/dev/null)
    
    if [ -n "$ALARM_NAMES" ] && [ "$ALARM_NAMES" != "None" ]; then
        for ALARM in $ALARM_NAMES; do
            aws cloudwatch enable-alarm-actions --alarm-names "$ALARM" --region $AWS_REGION 2>/dev/null || true
            echo "  Enabled: $ALARM"
        done
    fi
fi

# Step 2: Restore original task definition (remove stress sidecar)
echo ""
echo "[2/3] Removing CPU stress sidecar..."

if [ -f "$BACKUP_DIR/original_task_def.txt" ]; then
    ORIGINAL_TASK_DEF=$(cat $BACKUP_DIR/original_task_def.txt)
    echo "  Restoring: $ORIGINAL_TASK_DEF"
    
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --task-definition $ORIGINAL_TASK_DEF \
        --force-new-deployment \
        --region $AWS_REGION > /dev/null
else
    echo "  No backup found. Creating new task definition without stress sidecar..."
    
    CURRENT_TASK_DEF=$(aws ecs describe-services \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --region $AWS_REGION \
        --query 'services[0].taskDefinition' \
        --output text)
    
    aws ecs describe-task-definition \
        --task-definition $CURRENT_TASK_DEF \
        --region $AWS_REGION \
        --query 'taskDefinition' > /tmp/current_task_def.json
    
    jq '
      .containerDefinitions = [.containerDefinitions[] | select(.name != "cpu-stress")] |
      del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
    ' /tmp/current_task_def.json > /tmp/fixed_task_def.json
    
    NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
        --cli-input-json file:///tmp/fixed_task_def.json \
        --region $AWS_REGION \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)
    
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --task-definition $NEW_TASK_DEF_ARN \
        --force-new-deployment \
        --region $AWS_REGION > /dev/null
fi

# Step 3: Wait for service to stabilize
echo ""
echo "[3/3] Waiting for service to stabilize..."
aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --region $AWS_REGION 2>/dev/null || echo "  Service deployment in progress..."

# Clean up
rm -rf $BACKUP_DIR

echo ""
echo "Auto-scaling restored! Alarm actions enabled and stress sidecar removed."
echo ""
echo "=============================================="
