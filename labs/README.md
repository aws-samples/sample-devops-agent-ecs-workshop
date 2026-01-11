# Troubleshooting Labs

This directory contains all lab scripts for the ECS DevOps Agent troubleshooting workshop.

## ⚠️ Platform Requirements

**These scripts require a bash shell environment (Linux/macOS).**

**Windows Users:** Use one of these options:
- **[AWS CloudShell](https://console.aws.amazon.com/cloudshell)** (Recommended) - Browser-based, no setup required
- **WSL2** (Windows Subsystem for Linux)
- **Git Bash** (comes with Git for Windows)
- **SSH into a Linux EC2 instance**

**Prerequisites:**
- AWS CLI configured with appropriate credentials
- `jq` installed (`jq --version` to verify)

## Lab Overview

| Lab | Directory | Issue | Target | Type |
|-----|-----------|-------|--------|------|
| 1 | `lab1-logs-not-delivered/` | CloudWatch Logs Not Delivered | catalog | Configuration |
| 2 | `lab2-secrets-access-denied/` | Unable to Pull Secrets | orders | Configuration |
| 3 | `lab3-health-check-failures/` | Health Check Failures | ui | Configuration |
| 4 | `lab4-security-group-blocked/` | Security Group Blocked (DB Connectivity) | catalog → RDS | Configuration |
| 5 | `lab5-task-resource-limits/` | Task Resource Limits (OOM) | checkout | Configuration |
| 6 | `lab6-service-connect-broken/` | Service Connect Communication Broken | ui → catalog | Configuration |
| 7 | `lab7-cpu-stress/` | CPU Stress | catalog | Performance |
| 8 | `lab8-ddos-simulation/` | DDoS Attack Simulation | ui/ALB | Performance |
| 9 | `lab9-dynamodb-attack/` | DynamoDB Attack | carts | Performance |
| 10 | `lab10-autoscaling-broken/` | Auto-Scaling Not Working | catalog | Performance |

## Usage

Each lab has two scripts:
- `inject.sh` - Introduces the fault
- `fix.sh` - Restores the original configuration

### Running a Lab

```bash
# From the repository root
cd sample-devops-agent-ecs-workshop

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
| `AWS_REGION` | Auto-detected or `us-east-1` | AWS region |
| `NUM_ATTACK_TASKS` | `3` | Number of attack tasks (Labs 8, 9) |
| `NUM_STRESS_TASKS` | `5` | Number of DynamoDB stress tasks (Lab 9) |

## Lab Types

### Configuration Labs (1-6)
These modify ECS task definitions, IAM policies, or security groups to simulate misconfigurations. Use `fix.sh` to restore.

### Performance Labs (7-10)
These inject real faults using sidecar containers or rogue ECS tasks. Use `fix.sh` to restore.

## Troubleshooting

**Script fails with "command not found":**
- Ensure you're running in a bash shell
- Windows users: Use CloudShell, WSL2, or Git Bash

**Script fails with "jq: command not found":**
- Install jq: `brew install jq` (macOS) or `apt-get install jq` (Linux)

**Script fails with AWS permission errors:**
- Ensure your AWS credentials have Administrator access
- Check that `AWS_REGION` is set correctly
