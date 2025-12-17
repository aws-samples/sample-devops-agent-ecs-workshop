#!/bin/bash
# ECS RDS Security Group Block Script
# Blocks RDS access by removing security group ingress rules

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${ENVIRONMENT:-retail-store-ecs}"

echo "=== ECS RDS Security Group Block ==="
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo ""

# Step 1: Find RDS instances by tag
echo "[1/4] Finding RDS instances for environment..."
RDS_INSTANCES=$(aws rds describe-db-instances \
  --region $REGION \
  --query "DBInstances[?contains(DBInstanceIdentifier, '${ENVIRONMENT}')].DBInstanceIdentifier" \
  --output text)

if [ -z "$RDS_INSTANCES" ]; then
  echo "ERROR: No RDS instances found for environment $ENVIRONMENT"
  exit 1
fi

echo "  Found RDS instances: $RDS_INSTANCES"

# Step 2: Get security groups for RDS
echo "[2/4] Getting RDS security groups..."
SG_IDS=""
for INSTANCE in $RDS_INSTANCES; do
  SG=$(aws rds describe-db-instances \
    --db-instance-identifier $INSTANCE \
    --region $REGION \
    --query 'DBInstances[0].VpcSecurityGroups[*].VpcSecurityGroupId' \
    --output text)
  SG_IDS="$SG_IDS $SG"
done
SG_IDS=$(echo $SG_IDS | tr ' ' '\n' | sort -u | tr '\n' ' ')
echo "  Security Groups: $SG_IDS"

# Step 3: Save current rules for rollback
echo "[3/4] Saving current security group rules for rollback..."
BACKUP_FILE="/tmp/rds-sg-backup-$(date +%s).json"
echo "[]" > $BACKUP_FILE

for SG_ID in $SG_IDS; do
  aws ec2 describe-security-groups \
    --group-ids $SG_ID \
    --region $REGION \
    --query 'SecurityGroups[0].IpPermissions' >> $BACKUP_FILE.tmp
done
echo "  Backup saved to: $BACKUP_FILE"

# Step 4: Revoke all ingress rules
echo "[4/4] Revoking ingress rules to block RDS access..."
for SG_ID in $SG_IDS; do
  echo "  Processing security group: $SG_ID"
  
  # Get current ingress rules
  RULES=$(aws ec2 describe-security-groups \
    --group-ids $SG_ID \
    --region $REGION \
    --query 'SecurityGroups[0].IpPermissions' \
    --output json)
  
  if [ "$RULES" != "[]" ] && [ -n "$RULES" ]; then
    # Save rules for this SG
    echo "{\"sg_id\": \"$SG_ID\", \"rules\": $RULES}" >> $BACKUP_FILE
    
    # Revoke all ingress rules
    aws ec2 revoke-security-group-ingress \
      --group-id $SG_ID \
      --ip-permissions "$RULES" \
      --region $REGION 2>/dev/null || echo "    Warning: Some rules may have already been revoked"
    echo "    Revoked ingress rules for $SG_ID"
  else
    echo "    No ingress rules to revoke for $SG_ID"
  fi
done

echo ""
echo "=== RDS Security Group Block Complete ==="
echo ""
echo "Blocked: All ingress traffic to RDS security groups"
echo "Backup file: $BACKUP_FILE"
echo ""
echo "Expected symptoms:"
echo "  - Database connection timeouts"
echo "  - Catalog service errors (RDS MariaDB)"
echo "  - Orders service errors (RDS MariaDB)"
echo "  - 5XX errors in ALB metrics"
echo "  - Error spikes in CloudWatch Logs"
echo ""
echo "Monitor:"
echo "  aws cloudwatch get-metric-statistics --namespace AWS/RDS \\"
echo "    --metric-name DatabaseConnections --dimensions Name=DBInstanceIdentifier,Value=<instance-id> \\"
echo "    --start-time \$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \\"
echo "    --end-time \$(date -u +%Y-%m-%dT%H:%M:%SZ) --period 60 --statistics Sum"
echo ""
echo "Rollback:"
echo "  ./fault-injection/rollback-rds-sg-block.sh $BACKUP_FILE"
