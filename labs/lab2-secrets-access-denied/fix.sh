#!/bin/bash
# Lab 2: Unable to Pull Secrets - Fix Script
# This script reattaches the Secrets Manager policy to the orders service task execution role

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="orders"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab2_backup"

echo "=== Lab 2: Unable to Pull Secrets - Fix ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_DIR/execution_role_name.txt" ]; then
  echo "ERROR: Backup not found at $BACKUP_DIR"
  echo "The inject script may not have been run, or backup was deleted."
  exit 1
fi

EXECUTION_ROLE_NAME=$(cat $BACKUP_DIR/execution_role_name.txt)
POLICY_TYPE=$(cat $BACKUP_DIR/policy_type.txt 2>/dev/null || echo "ATTACHED")

echo "[1/2] Restoring Secrets Manager access..."
echo "  Execution role: $EXECUTION_ROLE_NAME"

if [ "$POLICY_TYPE" == "INLINE" ]; then
  # Restore inline policy
  POLICY_NAME=$(cat $BACKUP_DIR/inline_policy_name.txt)
  POLICY_DOC=$(cat $BACKUP_DIR/inline_policy_doc.json)
  
  echo "  Restoring inline policy: $POLICY_NAME"
  aws iam put-role-policy \
    --role-name $EXECUTION_ROLE_NAME \
    --policy-name $POLICY_NAME \
    --policy-document "$POLICY_DOC"
else
  # Reattach managed policy
  SECRETS_POLICY_ARN=$(cat $BACKUP_DIR/secrets_policy_arn.txt)
  echo "  Reattaching policy: $SECRETS_POLICY_ARN"
  
  aws iam attach-role-policy \
    --role-name $EXECUTION_ROLE_NAME \
    --policy-arn $SECRETS_POLICY_ARN
fi

# Step 2: Force new deployment
echo "[2/2] Forcing new deployment..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --force-new-deployment \
  --region $REGION \
  --query 'service.serviceName' \
  --output text > /dev/null

echo ""
echo "=== Lab 2 Fix Complete ==="
echo ""
echo "The orders service task execution role has been restored."
echo "New tasks should start successfully within 1-2 minutes."
echo ""
echo "Verify with:"
echo "  aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME \\"
echo "    --query 'services[0].[runningCount,desiredCount]' --output text"
