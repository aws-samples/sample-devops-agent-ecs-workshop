# Fault Injection Scripts

This directory contains chaos engineering scripts for performance-based troubleshooting labs (Labs 7-10). These scripts inject real faults into running ECS services using ECS Exec.

## Overview

| Script | Target | Effect | Duration | Rollback |
|--------|--------|--------|----------|----------|
| `inject-cpu-stress.sh` | catalog | CPU stress via stress-ng | 5 min | `rollback-cpu-stress.sh` |
| `inject-memory-stress.sh` | carts | Memory pressure via stress-ng | 5 min | `rollback-memory-stress.sh` |
| `inject-dynamodb-latency.sh` | carts | Network latency to DynamoDB | 5 min | `rollback-dynamodb-latency.sh` |
| `inject-rds-sg-block.sh` | catalog, orders | Block RDS security group | Manual | `rollback-rds-sg-block.sh` |
| `inject-rds-stress.sh` | catalog | Heavy database queries | 2 min | Auto-terminates |

## Prerequisites

- ECS Exec must be enabled on the cluster (enabled by default in this deployment)
- AWS CLI configured with appropriate permissions
- Session Manager plugin installed

## Usage

### Inject a Fault

```bash
# From the repository root
cd devops-agent-ecs

# CPU stress on catalog service
./fault-injection/inject-cpu-stress.sh

# Memory stress on carts service
./fault-injection/inject-memory-stress.sh

# DynamoDB latency on carts service
./fault-injection/inject-dynamodb-latency.sh

# Block RDS security group
./fault-injection/inject-rds-sg-block.sh

# RDS stress queries
./fault-injection/inject-rds-stress.sh
```

### Rollback a Fault

```bash
# Rollback CPU stress
./fault-injection/rollback-cpu-stress.sh

# Rollback memory stress
./fault-injection/rollback-memory-stress.sh

# Rollback DynamoDB latency
./fault-injection/rollback-dynamodb-latency.sh

# Rollback RDS security group block
./fault-injection/rollback-rds-sg-block.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `retail-store-ecs-cluster` | ECS cluster name |
| `SERVICE_NAME` | varies by script | Target ECS service |
| `AWS_REGION` | `us-east-1` | AWS region |
| `STRESS_DURATION` | `300` | Duration in seconds (5 min) |
| `CPU_WORKERS` | `2` | Number of CPU stress workers |
| `MEMORY_PERCENT` | `80` | Target memory percentage |
| `LATENCY_MS` | `500` | Network latency in milliseconds |

### Custom Configuration

```bash
# Example: Run CPU stress for 10 minutes with 4 workers
STRESS_DURATION=600 CPU_WORKERS=4 ./fault-injection/inject-cpu-stress.sh

# Example: Run memory stress at 90% utilization
MEMORY_PERCENT=90 ./fault-injection/inject-memory-stress.sh

# Example: Add 1 second latency to DynamoDB
LATENCY_MS=1000 ./fault-injection/inject-dynamodb-latency.sh
```

## How It Works

### CPU Stress (`inject-cpu-stress.sh`)
Uses ECS Exec to install and run `stress-ng` inside the container, spawning CPU workers that consume processing power.

### Memory Stress (`inject-memory-stress.sh`)
Uses ECS Exec to run `stress-ng` memory workers that allocate and touch memory pages, creating memory pressure.

### DynamoDB Latency (`inject-dynamodb-latency.sh`)
Uses Linux traffic control (`tc`) via ECS Exec to add network latency to DynamoDB endpoint traffic.

### RDS Security Group Block (`inject-rds-sg-block.sh`)
Modifies the RDS security group to remove the ingress rule allowing traffic from ECS services, simulating network isolation.

### RDS Stress (`inject-rds-stress.sh`)
Executes heavy, inefficient SQL queries (ORDER BY RAND(), cross joins) against the RDS database to consume CPU and I/O.

## Safety Notes

- All stress scripts have a default timeout and auto-terminate
- RDS security group changes require manual rollback
- Scripts are designed for lab/testing environments only
- Always run rollback scripts before destroying infrastructure

## Configuration Labs

For configuration-based labs (Labs 1-6), see the `../labs/` directory.
