#!/bin/bash
# ECS RDS Security Group Rollback Script
# Restores security group ingress rules from backup

set -e

REGION="${AWS_REGION:-us-east-1}"
BACKUP_FILE="${1:-}"

echo "=== ECS RDS Security Group Rollback ==="
echo "Region: $REGION"
echo ""

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <backup-file>"
  echo ""
  echo "The backup file was created by inject-rds-sg-block.sh"
  echo "Look for files matching: /tmp/rds-sg-backup-*.json"
  echo ""
  echo "Available backup files:"
  ls -la /tmp/rds-sg-backup-*.json 2>/dev/null || echo "  No backup files found in /tmp/"
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found: $BACKUP_FILE"
  exit 1
fi

echo "Backup file: $BACKUP_FILE"
echo ""

# Read and restore each security group
echo "[1/1] Restoring security group rules..."

while IFS= read -r line; do
  if [ -z "$line" ] || [ "$line" == "[]" ]; then
    continue
  fi
  
  SG_ID=$(echo "$line" | jq -r '.sg_id // empty')
  RULES=$(echo "$line" | jq -c '.rules // empty')
  
  if [ -n "$SG_ID" ] && [ -n "$RULES" ] && [ "$RULES" != "null" ] && [ "$RULES" != "[]" ]; then
    echo "  Restoring rules for security group: $SG_ID"
    aws ec2 authorize-security-group-ingress \
      --group-id $SG_ID \
      --ip-permissions "$RULES" \
      --region $REGION 2>/dev/null || echo "    Warning: Some rules may already exist"
    echo "    Rules restored for $SG_ID"
  fi
done < "$BACKUP_FILE"

echo ""
echo "=== RDS Security Group Rollback Complete ==="
echo ""
echo "Security group rules have been restored."
echo "Services should reconnect to RDS within a few seconds."
