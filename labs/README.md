# Troubleshooting Labs

This directory contains all lab scripts for the ECS DevOps Agent troubleshooting workshop.

## Lab Overview

| Lab | Directory | Issue | Target | Type |
|-----|-----------|-------|--------|------|
| 1 | `lab1-logs-not-delivered/` | CloudWatch Logs Not Delivered | catalog | Configuration |
| 2 | `lab2-secrets-access-denied/` | Unable to Pull Secrets | orders | Configuration |
| 3 | `lab3-health-check-failures/` | Health Check Failures | ui | Configuration |
| 4 | `lab4-service-discovery-broken/` | Service Connect Broken | ui | Configuration |
| 5 | `lab5-task-resource-limits/` | Task Resource Limits (OOM) | checkout | Configuration |
| 6 | `lab6-security-group-blocked/` | Security Group Blocked | catalog → RDS | Configuration |
| 7 | `lab7-cpu-stress/` | CPU Stress | catalog | Performance |
| 8 | `lab8-memory-stress/` | Memory Stress | carts | Performance |
| 9 | `lab9-dynamodb-latency/` | DynamoDB Latency | carts | Performance |
| 10 | `lab10-rds-stress/` | RDS Stress | catalog | Performance |

## Usage

Each lab has scripts:
- `inject.sh` - Introduces the fault
- `fix.sh` or `rollback.sh` - Restores the original configuration

### Running a Lab

```bash
# From the repository root
cd devops-agent-ecs

# Inject the fault
./labs/lab1-logs-not-delivered/inject.sh

# Use DevOps Agent to investigate...

# Fix the issue
./labs/lab1-logs-not-delivered/fix.sh
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `retail-store-ecs-cluster` | ECS cluster name |
| `AWS_REGION` | `us-east-1` | AWS region |
| `STRESS_DURATION` | `300` | Duration in seconds (performance labs) |
| `CPU_WORKERS` | `2` | Number of CPU stress workers |
| `MEMORY_PERCENT` | `80` | Target memory percentage |
| `LATENCY_MS` | `500` | Network latency in milliseconds |

## Lab Types

### Configuration Labs (1-6)
These modify ECS task definitions, IAM policies, or security groups to simulate misconfigurations. Use `fix.sh` to restore.

### Performance Labs (7-10)
These inject real faults using ECS Exec (stress-ng, tc). Use `rollback.sh` to restore, or wait for auto-timeout.
