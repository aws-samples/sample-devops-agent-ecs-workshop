#!/bin/bash
# Lab 8: Auto-Scaling Not Working - Fix Script
# This script re-enables CloudWatch alarm actions

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="${SERVICE_NAME:-ui}"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab8_backup"

echo "=== Lab 8: Auto-Scaling Not Working - Fix ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_DIR/alarm_names.txt" ]; then
  echo "Backup not found. Finding alarms directly..."
  ALARM_NAMES=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "TargetTracking-service/$CLUSTER_NAME/$SERVICE_NAME" \
    --region $REGION \
    --query 'MetricAlarms[*].AlarmName' \
    --output text)
else
  ALARM_NAMES=$(cat $BACKUP_DIR/alarm_names.txt)
fi

if [ -z "$ALARM_NAMES" ] || [ "$ALARM_NAMES" == "None" ]; then
  echo "ERROR: No auto-scaling alarms found for service $SERVICE_NAME"
  exit 1
fi

# Re-enable alarm actions
echo "[1/1] Re-enabling alarm actions..."
for ALARM in $ALARM_NAMES; do
  aws cloudwatch enable-alarm-actions \
    --alarm-names "$ALARM" \
    --region $REGION
  echo "  Enabled actions for: $ALARM"
done

echo ""
echo "=== Lab 8 Fix Complete ==="
echo ""
echo "Auto-scaling alarm actions have been re-enabled."
echo "If CPU is still high, the service should now scale out."
echo ""
echo "Verify with:"
echo "  aws cloudwatch describe-alarms --alarm-names $ALARM_NAMES \\"
echo "    --query 'MetricAlarms[*].[AlarmName,ActionsEnabled,StateValue]' --output table"
echo ""
echo "Check service task count:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME \\"
echo "    --query 'services[0].[desiredCount,runningCount]' --output text"
