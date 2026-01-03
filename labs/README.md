# Troubleshooting Labs

This directory contains inject/fix scripts for the configuration-based troubleshooting labs (Labs 1-6).

## Lab Overview

| Lab | Directory | Issue | Target Service |
|-----|-----------|-------|----------------|
| 1 | `lab1-logs-not-delivered/` | CloudWatch Logs Not Delivered | catalog |
| 2 | `lab2-secrets-access-denied/` | Unable to Pull Secrets | orders |
| 3 | `lab3-health-check-failures/` | Health Check Failures | ui |
| 4 | `lab4-service-discovery-broken/` | Service Connect Broken | ui |
| 5 | `lab5-task-resource-limits/` | Task Resource Limits (OOM) | checkout |
| 6 | `lab6-security-group-blocked/` | Security Group Blocked | catalog → RDS |

## Usage

Each lab has two scripts:
- `inject.sh` - Introduces the fault
- `fix.sh` - Restores the original configuration

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

## Performance Labs (7-10)

For performance-based labs, use the scripts in `../fault-injection/`:

| Lab | Inject Script | Rollback Script |
|-----|---------------|-----------------|
| 7 | `inject-cpu-stress.sh` | `rollback-cpu-stress.sh` |
| 8 | `inject-memory-stress.sh` | `rollback-memory-stress.sh` |
| 9 | `inject-dynamodb-latency.sh` | `rollback-dynamodb-latency.sh` |
| 10 | `inject-rds-stress.sh` | (auto-terminates) |

## Backup Files

Each inject script creates backups in `/tmp/labN_backup/` for restoration.
