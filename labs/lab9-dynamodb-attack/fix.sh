#!/bin/bash
# Lab 9: DynamoDB Attack Simulation - Fix Script
# Stops attack tasks and restores DynamoDB capacity

set -e

BACKUP_DIR="/tmp/lab9_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 9: DynamoDB Attack Simulation - Fix"
echo "=============================================="
echo ""

# Get cluster name
if [ -f "$BACKUP_DIR/cluster_name.txt" ]; then
    CLUSTER_NAME=$(cat $BACKUP_DIR/cluster_name.txt)
else
    CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
fi

# Step 1: Stop attack tasks
echo "[1/3] Stopping attack tasks..."

if [ -f "$BACKUP_DIR/stress_task_arns.txt" ]; then
    TASK_ARNS=$(cat $BACKUP_DIR/stress_task_arns.txt)
    for TASK_ARN in $TASK_ARNS; do
        if [ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ]; then
            aws ecs stop-task --cluster $CLUSTER_NAME --task $TASK_ARN --region $AWS_REGION 2>/dev/null || true
            echo "  Stopped: $(echo $TASK_ARN | awk -F'/' '{print $NF}')"
        fi
    done
fi

# Find and stop any remaining attack tasks
RUNNING_TASKS=$(aws ecs list-tasks \
    --cluster $CLUSTER_NAME \
    --family dynamodb-stress-attack \
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

# Step 2: Restore DynamoDB capacity
echo ""
echo "[2/3] Restoring DynamoDB capacity..."

if [ -f "$BACKUP_DIR/table_name.txt" ]; then
    TABLE_NAME=$(cat $BACKUP_DIR/table_name.txt)
    
    if [ -f "$BACKUP_DIR/billing_mode.txt" ]; then
        ORIGINAL_BILLING=$(cat $BACKUP_DIR/billing_mode.txt)
        
        if [ "$ORIGINAL_BILLING" == "PAY_PER_REQUEST" ]; then
            echo "  Restoring to on-demand capacity..."
            aws dynamodb update-table \
                --table-name $TABLE_NAME \
                --billing-mode PAY_PER_REQUEST \
                --region $AWS_REGION > /dev/null 2>&1 || true
        elif [ -f "$BACKUP_DIR/original_rcu.txt" ]; then
            ORIGINAL_RCU=$(cat $BACKUP_DIR/original_rcu.txt)
            ORIGINAL_WCU=$(cat $BACKUP_DIR/original_wcu.txt 2>/dev/null || echo "$ORIGINAL_RCU")
            echo "  Restoring to ${ORIGINAL_RCU} RCU / ${ORIGINAL_WCU} WCU..."
            aws dynamodb update-table \
                --table-name $TABLE_NAME \
                --provisioned-throughput ReadCapacityUnits=$ORIGINAL_RCU,WriteCapacityUnits=$ORIGINAL_WCU \
                --region $AWS_REGION > /dev/null 2>&1 || true
        fi
    fi
    
    echo "  Waiting for table to update..."
    aws dynamodb wait table-exists --table-name $TABLE_NAME --region $AWS_REGION 2>/dev/null || true
fi

# Step 3: Clean up task definitions
echo ""
echo "[3/3] Cleaning up..."

TASK_DEFS=$(aws ecs list-task-definitions \
    --family-prefix dynamodb-stress-attack \
    --region $AWS_REGION \
    --query 'taskDefinitionArns[]' \
    --output text 2>/dev/null)

for TD in $TASK_DEFS; do
    aws ecs deregister-task-definition --task-definition $TD --region $AWS_REGION > /dev/null 2>&1 || true
done

rm -rf $BACKUP_DIR

echo ""
echo "DynamoDB attack stopped! Service restored."
echo ""
echo "=============================================="
