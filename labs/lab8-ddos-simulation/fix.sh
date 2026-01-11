#!/bin/bash
# Lab 8: DDoS Attack Simulation - Fix Script
# Stops all attack tasks and cleans up

set -e

BACKUP_DIR="/tmp/lab8_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 8: DDoS Attack Simulation - Fix"
echo "=============================================="
echo ""

# Get cluster name
if [ -f "$BACKUP_DIR/cluster_name.txt" ]; then
    CLUSTER_NAME=$(cat $BACKUP_DIR/cluster_name.txt)
else
    CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
fi

echo "Stopping attack tasks..."

# Stop tasks from backup file
if [ -f "$BACKUP_DIR/attack_task_arns.txt" ]; then
    TASK_ARNS=$(cat $BACKUP_DIR/attack_task_arns.txt)
    for TASK_ARN in $TASK_ARNS; do
        if [ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ]; then
            aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN --region $AWS_REGION 2>/dev/null || true
            echo "  Stopped: $(echo $TASK_ARN | awk -F'/' '{print $NF}')"
        fi
    done
fi

# Also find and stop any running http-flood-attack tasks
echo ""
echo "Finding any remaining attack tasks..."
RUNNING_TASKS=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --family http-flood-attack \
    --desired-status RUNNING \
    --region $AWS_REGION \
    --query 'taskArns[]' \
    --output text 2>/dev/null)

if [ -n "$RUNNING_TASKS" ] && [ "$RUNNING_TASKS" != "None" ]; then
    for TASK_ARN in $RUNNING_TASKS; do
        aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN --region $AWS_REGION 2>/dev/null || true
        echo "  Stopped: $(echo $TASK_ARN | awk -F'/' '{print $NF}')"
    done
fi

# Deregister the attack task definition
echo ""
echo "Cleaning up task definitions..."
TASK_DEFS=$(aws ecs list-task-definitions \
    --family-prefix http-flood-attack \
    --region $AWS_REGION \
    --query 'taskDefinitionArns[]' \
    --output text 2>/dev/null)

for TD in $TASK_DEFS; do
    aws ecs deregister-task-definition --task-definition $TD --region $AWS_REGION > /dev/null 2>&1 || true
done

# Clean up backup files
rm -rf $BACKUP_DIR

echo ""
echo "DDoS attack stopped! All attack tasks terminated."
echo ""
echo "=============================================="
