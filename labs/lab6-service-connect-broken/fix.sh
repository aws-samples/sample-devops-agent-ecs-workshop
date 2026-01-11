#!/bin/bash
# Lab 6: Service Connect Communication Broken - Fix Script
# Restores the correct service endpoints in UI task definition

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="ui"
BACKUP_DIR="/tmp/lab6_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 6: Service Connect Communication Broken - Fix"
echo "=============================================="
echo ""

# Check if backup file exists
if [ -f "$BACKUP_DIR/original_task_def_arn.txt" ]; then
    ORIGINAL_TASK_DEF=$(cat $BACKUP_DIR/original_task_def_arn.txt)
    echo "Restoring original task definition: $ORIGINAL_TASK_DEF"
    
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --task-definition $ORIGINAL_TASK_DEF \
        --force-new-deployment \
        --region $AWS_REGION > /dev/null
else
    echo "No backup found. Creating new task definition with correct endpoints..."
    
    # Get current task definition and fix it
    TASK_DEF_ARN=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --query 'services[0].taskDefinition' --output text --region $AWS_REGION)
    TASK_DEF=$(aws ecs describe-task-definition --task-definition $TASK_DEF_ARN --region $AWS_REGION)
    
    # Fix the endpoints
    NEW_TASK_DEF=$(echo $TASK_DEF | jq '.taskDefinition | 
      .containerDefinitions[0].environment = (.containerDefinitions[0].environment | map(
        if .name == "RETAIL_UI_ENDPOINTS_CATALOG" then .value = "http://catalog"
        elif .name == "ENDPOINTS_CATALOG" then .value = "http://catalog"
        else .
        end
      )) |
      del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')
    
    NEW_TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json "$NEW_TASK_DEF" --region $AWS_REGION --query 'taskDefinition.taskDefinitionArn' --output text)
    
    aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --task-definition $NEW_TASK_DEF_ARN --force-new-deployment --region $AWS_REGION > /dev/null
fi

echo ""
echo "Service endpoints restored!"
echo "The UI service will reconnect to the catalog shortly."
echo ""
echo "=============================================="
