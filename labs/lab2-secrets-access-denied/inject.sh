#!/bin/bash
# Lab 2: Unable to Pull Secrets - Inject Script
# This script detaches the Secrets Manager policy from the orders service task execution role

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="orders"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab2_backup"

echo "=== Lab 2: Unable to Pull Secrets - Inject ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Create backup directory
mkdir -p $BACKUP_DIR

# Step 1: Get task definition and execution role
echo "[1/4] Getting task definition and execution role..."
TASK_DEF_ARN=$(aws ecs describe-services \
  --cluster $CLUSTER_NAME \
  --services $SERVICE_NAME \
  --region $REGION \
  --query 'services[0].taskDefinition' \
  --output text)

EXECUTION_ROLE_ARN=$(aws ecs describe-task-definition \
  --task-definition $TASK_DEF_ARN \
  --region $REGION \
  --query 'taskDefinition.executionRoleArn' \
  --output text)

EXECUTION_ROLE_NAME=$(echo $EXECUTION_ROLE_ARN | awk -F'/' '{print $NF}')
echo "  Task definition: $TASK_DEF_ARN"
echo "  Execution role: $EXECUTION_ROLE_NAME"

# Step 2: Find Secrets Manager policy
echo "[2/4] Finding Secrets Manager policy..."
SECRETS_POLICY_ARN=$(aws iam list-attached-role-policies \
  --role-name $EXECUTION_ROLE_NAME \
  --query 'AttachedPolicies[?contains(PolicyName, `ecret`) || contains(PolicyName, `Secret`)].PolicyArn' \
  --output text | head -1)

if [ -z "$SECRETS_POLICY_ARN" ] || [ "$SECRETS_POLICY_ARN" == "None" ]; then
  # Try to find inline policies with secrets access
  echo "  No attached Secrets Manager policy found, checking inline policies..."
  INLINE_POLICIES=$(aws iam list-role-policies --role-name $EXECUTION_ROLE_NAME --query 'PolicyNames' --output text)
  
  if [ -n "$INLINE_POLICIES" ]; then
    for policy in $INLINE_POLICIES; do
      POLICY_DOC=$(aws iam get-role-policy --role-name $EXECUTION_ROLE_NAME --policy-name $policy --query 'PolicyDocument' --output json)
      if echo "$POLICY_DOC" | grep -q "secretsmanager"; then
        echo "  Found inline policy with Secrets Manager access: $policy"
        echo "$policy" > $BACKUP_DIR/inline_policy_name.txt
        echo "$POLICY_DOC" > $BACKUP_DIR/inline_policy_doc.json
        
        # Delete the inline policy
        echo "[3/4] Removing inline policy..."
        aws iam delete-role-policy --role-name $EXECUTION_ROLE_NAME --policy-name $policy
        echo "$EXECUTION_ROLE_NAME" > $BACKUP_DIR/execution_role_name.txt
        echo "INLINE" > $BACKUP_DIR/policy_type.txt
        break
      fi
    done
  fi
else
  echo "  Found attached policy: $SECRETS_POLICY_ARN"
  echo "$SECRETS_POLICY_ARN" > $BACKUP_DIR/secrets_policy_arn.txt
  echo "$EXECUTION_ROLE_NAME" > $BACKUP_DIR/execution_role_name.txt
  echo "ATTACHED" > $BACKUP_DIR/policy_type.txt
  
  # Step 3: Detach the policy
  echo "[3/4] Detaching Secrets Manager policy..."
  aws iam detach-role-policy \
    --role-name $EXECUTION_ROLE_NAME \
    --policy-arn $SECRETS_POLICY_ARN
fi

# Step 4: Force new deployment
echo "[4/4] Forcing new deployment..."
aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --force-new-deployment \
  --region $REGION \
  --query 'service.serviceName' \
  --output text > /dev/null

echo ""
echo "=== Lab 2 Injection Complete ==="
