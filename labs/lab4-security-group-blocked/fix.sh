#!/bin/bash
# Lab 4: Database Connectivity - Security Group Blocked - Fix Script
# Restores the RDS security group rule allowing catalog service access

set -e

CLUSTER_NAME="${CLUSTER_NAME:-retail-store-ecs-cluster}"
BACKUP_DIR="/tmp/lab4_backup"

# Use existing AWS_REGION if set, otherwise try IMDS, then default
if [ -z "$AWS_REGION" ]; then
  AWS_REGION=$(curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo "us-east-1")
fi

echo "=============================================="
echo "Lab 4: Database Security Group Blocked - Fix"
echo "=============================================="
echo ""

# Check if backup files exist
if [ ! -f "$BACKUP_DIR/rds_sg_id.txt" ] || [ ! -f "$BACKUP_DIR/catalog_sg_id.txt" ]; then
    echo "ERROR: Backup files not found. Cannot restore."
    echo "Please manually add the security group rule."
    exit 1
fi

RDS_SG_ID=$(cat $BACKUP_DIR/rds_sg_id.txt)
CATALOG_SG_ID=$(cat $BACKUP_DIR/catalog_sg_id.txt)

echo "Restoring security group rule..."
echo "  RDS Security Group: $RDS_SG_ID"
echo "  Catalog Security Group: $CATALOG_SG_ID"

# Add the ingress rule back
aws ec2 authorize-security-group-ingress \
    --group-id $RDS_SG_ID \
    --protocol tcp \
    --port 3306 \
    --source-group $CATALOG_SG_ID \
    --region $AWS_REGION 2>/dev/null || echo "  Rule may already exist"

# Force catalog service to reconnect
aws ecs update-service --cluster $CLUSTER_NAME --service catalog --force-new-deployment --region $AWS_REGION > /dev/null

echo ""
echo "Security group rule restored!"
echo "The catalog service will reconnect to the database shortly."
echo ""
echo "=============================================="
