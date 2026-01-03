#!/bin/bash
# Lab 6: Security Group Blocked - Fix Script
# This script restores the security group rule allowing catalog service to connect to RDS

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
SERVICE_NAME="catalog"
REGION="${AWS_REGION:-us-east-1}"
BACKUP_DIR="/tmp/lab6_backup"

echo "=== Lab 6: Security Group Blocked - Fix ==="
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo ""

# Check if backup exists
if [ ! -f "$BACKUP_DIR/rds_sg_id.txt" ] || [ ! -f "$BACKUP_DIR/catalog_sg_id.txt" ]; then
  echo "ERROR: Backup not found at $BACKUP_DIR"
  echo "The inject script may not have been run, or backup was deleted."
  exit 1
fi

RDS_SG_ID=$(cat $BACKUP_DIR/rds_sg_id.txt)
CATALOG_SG_ID=$(cat $BACKUP_DIR/catalog_sg_id.txt)

echo "[1/1] Restoring security group ingress rule..."
echo "  RDS Security Group: $RDS_SG_ID"
echo "  Catalog Security Group: $CATALOG_SG_ID"
echo "  Port: 3306 (MySQL)"

aws ec2 authorize-security-group-ingress \
  --group-id $RDS_SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group $CATALOG_SG_ID \
  --region $REGION 2>/dev/null || echo "  Rule may already exist"

echo ""
echo "=== Lab 6 Fix Complete ==="
echo ""
echo "The security group rule has been restored."
echo "Catalog service should be able to connect to RDS immediately."
echo ""
echo "Verify with:"
echo "  curl -s \$(terraform output -raw ui_service_url)/catalog | head -20"
