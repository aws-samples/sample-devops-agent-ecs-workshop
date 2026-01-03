#!/bin/bash
# Lab 6: Security Group Blocked - Inject Script
# This script removes the security group rule allowing catalog service to connect to RDS

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="catalog"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab6_backup"

echo "=== Lab 6: Security Group Blocked - Inject ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Create backup directory
mkdir -p $BACKUP_DIR

# Step 1: Find the RDS security group
echo "[1/4] Finding RDS security group..."
RDS_SG_ID=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters "Name=tag:Name,Values=*catalog*db*" "Name=tag:ecsdevopsagent,Values=true" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ -z "$RDS_SG_ID" ] || [ "$RDS_SG_ID" == "None" ]; then
  # Try alternative search
  RDS_SG_ID=$(aws ec2 describe-security-groups \
    --region $REGION \
    --filters "Name=group-name,Values=*catalog*rds*" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)
fi

if [ -z "$RDS_SG_ID" ] || [ "$RDS_SG_ID" == "None" ]; then
  echo "ERROR: Could not find RDS security group"
  echo "Looking for security groups with tags containing 'catalog' and 'db'"
  exit 1
fi
echo "  RDS Security Group: $RDS_SG_ID"
echo "$RDS_SG_ID" > $BACKUP_DIR/rds_sg_id.txt

# Step 2: Find the catalog service security group
echo "[2/4] Finding catalog service security group..."
CATALOG_SG_ID=$(aws ec2 describe-security-groups \
  --region $REGION \
  --filters "Name=tag:Name,Values=*catalog*service*" "Name=tag:ecsdevopsagent,Values=true" \
  --query 'SecurityGroups[0].GroupId' \
  --output text 2>/dev/null)

if [ -z "$CATALOG_SG_ID" ] || [ "$CATALOG_SG_ID" == "None" ]; then
  CATALOG_SG_ID=$(aws ec2 describe-security-groups \
    --region $REGION \
    --filters "Name=group-name,Values=*catalog*" \
    --query 'SecurityGroups[?!contains(GroupName, `rds`) && !contains(GroupName, `db`)].GroupId' \
    --output text 2>/dev/null | head -1)
fi

if [ -z "$CATALOG_SG_ID" ] || [ "$CATALOG_SG_ID" == "None" ]; then
  echo "ERROR: Could not find catalog service security group"
  exit 1
fi
echo "  Catalog Service Security Group: $CATALOG_SG_ID"
echo "$CATALOG_SG_ID" > $BACKUP_DIR/catalog_sg_id.txt

# Step 3: Find and save the ingress rule
echo "[3/4] Finding MySQL ingress rule from catalog to RDS..."
RULE_EXISTS=$(aws ec2 describe-security-groups \
  --group-ids $RDS_SG_ID \
  --region $REGION \
  --query "SecurityGroups[0].IpPermissions[?FromPort==\`3306\` && contains(UserIdGroupPairs[].GroupId, '$CATALOG_SG_ID')]" \
  --output json)

if [ "$RULE_EXISTS" == "[]" ]; then
  echo "WARNING: No ingress rule found from catalog SG to RDS on port 3306"
  echo "The rule may already be removed or uses different configuration"
fi

# Save rule info for restoration
echo "3306" > $BACKUP_DIR/port.txt

# Step 4: Remove the ingress rule
echo "[4/4] Removing security group ingress rule..."
aws ec2 revoke-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group $CATALOG_SG_ID \
  --region $REGION 2>/dev/null || echo "  Rule may already be removed"

echo ""
echo "=== Lab 6 Injection Complete ==="
echo ""
echo "Issue injected: RDS security group no longer allows traffic from catalog service"
echo "  RDS Security Group: $RDS_SG_ID"
echo "  Catalog Security Group: $CATALOG_SG_ID"
echo "  Blocked Port: 3306 (MySQL)"
echo ""
echo "Expected symptoms:"
echo "  - Catalog returns errors when fetching products"
echo "  - Service is running and appears healthy"
echo "  - Database connection timeouts in CloudWatch logs"
echo "  - RDS appears healthy (no connection issues from its perspective)"
echo ""
echo "Investigation prompts for DevOps Agent:"
echo "  'The catalog service cannot connect to the database. What is wrong?'"
echo "  'Check the CloudWatch logs for the catalog service - are there database connection errors?'"
echo "  'What security groups are attached to the catalog service and the RDS database?'"
echo ""
echo "To fix: ./labs/lab6-security-group-blocked/fix.sh"
