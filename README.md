![Banner](./docs/images/banner.png)

<div align="center">
  <strong>
  <h2>ECS DevOps Agent Lab</h2>
  </strong>
</div>

## About This Lab

This lab provides a production-ready Amazon ECS deployment environment for testing and demonstrating ECS DevOps agents and automation tools. It deploys a multi-service retail store application with comprehensive observability and fault injection capabilities.

### What You'll Learn

- Deploy a distributed microservices application to Amazon ECS using Terraform
- Configure production-grade observability with CloudWatch Container Insights
- Execute chaos engineering experiments using ECS Exec
- Monitor and troubleshoot containerized applications on AWS

### Key Features

- **One-Command Deployment**: Deploy the entire infrastructure with `terraform apply`
- **Production-Grade Observability**: CloudWatch dashboards, alarms, and enhanced Container Insights
- **Chaos Engineering Ready**: Pre-built fault injection scripts for CPU, memory, network, and database stress testing
- **DevOps Agent Integration**: All resources tagged with `ecsdevopsagent=true` for agent discovery

**This project is intended for educational purposes only and not for production use**

![Screenshot](/docs/images/screenshot.png)

## Table of Contents

- [About This Lab](#about-this-lab)
- [Getting Started](#getting-started)
- [Application Architecture](#application-architecture)
- [Deployment (Amazon ECS)](#deployment-amazon-ecs)
- [Observability](#observability)
- [AWS DevOps Agent Integration](#aws-devops-agent-integration)
- [Fault Injection Scenarios](#fault-injection-scenarios)
- [Security](#security)
- [License](#license)

## Getting Started

### Install Git

If you don't have Git installed, install it first:

```bash
# Linux (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install git

# Linux (RHEL/CentOS/Amazon Linux)
sudo yum install git

# macOS (using Homebrew)
brew install git

# Verify installation
git --version
```

### Clone the Repository

> **First time using GitLab?** If you haven't set up SSH access for GitLab, follow the [GitLab SSH Configuration Guide](https://gitlab.pages.aws.dev/docs/Platform/ssh.html#ssh-config) first.

```bash
# Clone the repository
git clone git@ssh.gitlab.aws.dev:kulkshya/ecs-retail-app.git

# Navigate to the project directory
cd ecs-retail-app
```

> **Note:** If the above clone command fails, try using the alternative GitLab URL:
> ```bash
> git clone git@gitlab.aws.dev:kulkshya/ecs-retail-app.git
> ```

> **🔧 Troubleshooting Git Clone Issues?** If you're encountering persistent issues with `git clone` (SSH key problems, network restrictions, etc.), you can download the repository as a ZIP file instead:
> 1. Navigate to the repository in your browser: https://gitlab.aws.dev/kulkshya/ecs-retail-app
> 2. Click the **Download** button (or **Code** → **Download source code**)
> 3. Select **Download ZIP** (or your preferred format)
> 4. Extract the ZIP file to your desired location

## Application Architecture

The application has been deliberately over-engineered to generate multiple de-coupled components. These components generally have different infrastructure dependencies, and may support multiple "backends" (example: Carts service supports MongoDB or DynamoDB).

![Architecture](/docs/images/architecture.png)

| Component                  | Language | Container Image                                                             | Description                             |
| -------------------------- | -------- | --------------------------------------------------------------------------- | --------------------------------------- |
| [UI](./src/ui/)            | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-ui)       | Store user interface                    |
| [Catalog](./src/catalog/)  | Go       | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-catalog)  | Product catalog API                     |
| [Cart](./src/cart/)        | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-cart)     | User shopping carts API                 |
| [Orders](./src/orders)     | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-orders)   | User orders API                         |
| [Checkout](./src/checkout) | Node     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-checkout) | API to orchestrate the checkout process |

## Deployment (Amazon ECS)

Deploy the application to Amazon ECS using Terraform with production-grade observability.

#### Prerequisites

1. **AWS CLI** - Install and configure with appropriate credentials
   ```bash
   # Install AWS CLI (Linux)
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   
   # Configure credentials
   aws configure
   # Or use SSO
   aws configure sso
   ```

2. **Terraform** >= 1.0
   ```bash
   # Install Terraform (Linux)
   sudo yum install -y yum-utils
   sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
   sudo yum -y install terraform
   
   # Verify installation
   terraform --version
   ```

3. **Session Manager Plugin** (required for ECS Exec and fault injection)
   ```bash
   # Install Session Manager plugin (Linux)
   curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
   sudo dpkg -i session-manager-plugin.deb
   
   # Verify installation
   session-manager-plugin --version
   ```

4. **AWS Permissions** - Your IAM user/role needs permissions for:
   - ECS (clusters, services, tasks, task definitions)
   - EC2 (VPC, subnets, security groups, NAT gateway)
   - RDS (DB instances, subnet groups)
   - DynamoDB (tables)
   - ElastiCache (Redis clusters)
   - Amazon MQ (brokers)
   - CloudWatch (logs, metrics, dashboards, alarms)
   - IAM (roles, policies)
   - Application Load Balancer
   - S3 (if ALB access logs enabled)

#### Deployment Steps

```bash
# Navigate to the Terraform directory
cd terraform/ecs/default

# Initialize Terraform (downloads providers and modules)
terraform init

# Preview the changes (optional but recommended)
terraform plan

# Deploy the infrastructure (takes ~15-20 minutes)
terraform apply

# Type 'yes' when prompted to confirm
```

> **Important:** All resources created by this Terraform deployment are tagged with `ecsdevopsagent=true`. This tag is used to identify resources managed by this project and enables integration with ECS DevOps agents and automation tools.

#### Deployment Outputs

After deployment completes, Terraform outputs:
- `ui_service_url` - Application URL (ALB endpoint)
- `cloudwatch_dashboard_url` - CloudWatch dashboard URL
- `ecs_cluster_name` - ECS cluster name
- `ecs_tasks_log_group` - CloudWatch log group for task logs
- `ecs_exec_log_group` - CloudWatch log group for ECS Exec sessions

#### Verify Deployment

```bash
# Get the application URL
terraform output ui_service_url

# Test the application
curl -I $(terraform output -raw ui_service_url)

# View ECS cluster status
aws ecs describe-clusters --clusters $(terraform output -raw ecs_cluster_name)

# List running services
aws ecs list-services --cluster $(terraform output -raw ecs_cluster_name)
```

#### Cleanup

To destroy all resources and avoid ongoing charges:
```bash
terraform destroy
# Type 'yes' when prompted to confirm
```

> **Note:** Destruction takes ~10-15 minutes. Ensure all resources are deleted to avoid unexpected charges.

## Observability

The ECS deployment includes production-grade observability features powered by AWS-native services:

### CloudWatch Container Insights (Enhanced)

Container Insights with enhanced observability is enabled by default (`container_insights_setting = "enhanced"`), providing:
- Automatic collection of CPU, memory, network, and storage metrics
- Per-container and per-task metrics
- Performance log events for troubleshooting

### Logging

- ECS task logs sent to CloudWatch Logs with configurable retention
- ECS Exec session logging for audit trails
- Optional KMS encryption for log groups
- Optional VPC Flow Logs for network analysis

### Metrics & Dashboards

- Pre-configured CloudWatch dashboard with CPU, memory, task count, and ALB metrics
- Service-level metrics for all microservices (ui, catalog, carts, checkout, orders)

### Alarms

When `cloudwatch_alarms_enabled = true` (default):
- CPU/Memory utilization alarms per service (threshold: 80%)
- Running task count alarms (alerts when no tasks running)
- ALB 5XX error alarms
- ALB latency alarms (p95 > 2s)
- Log-based error spike detection

### Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `container_insights_setting` | `"enhanced"` | Container Insights mode (`enhanced` or `disabled`) |
| `log_retention_days` | `30` | CloudWatch Logs retention period |
| `logs_kms_key_arn` | `null` | Optional KMS key for log encryption |
| `cloudwatch_alarms_enabled` | `true` | Enable CloudWatch alarms |
| `alarm_sns_topic_arn` | `null` | SNS topic for alarm notifications |
| `alb_access_logs_enabled` | `false` | Enable ALB access logs to S3 |
| `vpc_flow_logs_enabled` | `false` | Enable VPC Flow Logs |

### Deployed Resources

The ECS deployment creates:
- VPC with public/private subnets and NAT Gateway
- ECS Cluster with Fargate capacity providers
- 5 ECS services: ui, catalog, carts, checkout, orders
- Application Load Balancer
- RDS MariaDB instances (catalog, orders)
- ElastiCache Redis (checkout)
- Amazon MQ broker (orders)
- DynamoDB table (carts)
- CloudWatch log groups, dashboard, and alarms

## AWS DevOps Agent Integration

AWS DevOps Agent is a frontier AI agent that helps accelerate incident response and improve system reliability. It automatically correlates data across your operational toolchain, identifies probable root causes, and recommends targeted mitigations. This section provides step-by-step guidance for integrating the DevOps Agent with your ECS-based Retail Store deployment.

> **Note:** AWS DevOps Agent is currently in **public preview** and available in the **US East (N. Virginia) Region** (`us-east-1`). While the agent runs in `us-east-1`, it can monitor applications deployed in any AWS Region.

### Create an Agent Space

An **Agent Space** defines the scope of what AWS DevOps Agent can access as it performs tasks. Think of it as a logical boundary that groups related resources, applications, and infrastructure for investigation purposes.

#### Step-by-Step: Create an Agent Space

1. **Navigate to AWS DevOps Agent Console**
   ```
   https://console.aws.amazon.com/devops-agent/home?region=us-east-1
   ```

2. **Create the Agent Space**
   - Click **Create Agent Space**
   - Enter a name: `retail-store-ecs-lab` (or your preferred name)
   - Optionally add a description: "Agent Space for AWS Retail Store Sample Application on ECS"

3. **Configure IAM Roles**
   
   The console will guide you to create the required IAM roles. AWS DevOps Agent needs permissions to:
   - Introspect AWS resources in your account(s)
   - Access CloudWatch metrics and logs
   - Query X-Ray traces
   - Read ECS cluster and service information

4. **Enable the Web App**
   - Check the option to **Enable AWS DevOps Agent web app**
   - This provides a web interface for operators to trigger and monitor investigations

5. **Click Create**
   - Wait for the Agent Space to be created (typically 1-2 minutes)

#### Mandatory Resource Tags

All AWS resources in this lab are tagged with:

```
ecsdevopsagent = "true"
```

This tag is **critical** for the DevOps Agent to:
- Automatically discover resources associated with the Retail Store application
- Correlate related resources during investigations
- Scope troubleshooting to the correct infrastructure

The Terraform deployment automatically applies this tag to all resources.

### View Topology Graph

The **Topology** view provides a visual map of your system components and their relationships. AWS DevOps Agent automatically builds this topology by analyzing your infrastructure.

#### Accessing the Topology View

1. Open your Agent Space in the AWS Console
2. Click the **Topology** tab
3. View the automatically discovered resources and relationships

#### What the Topology Shows

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        DevOps Agent Topology View                            │
│                                                                              │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                    │
│  │    ECS      │────▶│     RDS     │     │  DynamoDB   │                    │
│  │   Cluster   │     │   MariaDB   │     │   Table     │                    │
│  └──────┬──────┘     └─────────────┘     └─────────────┘                    │
│         │                                                                    │
│  ┌──────▼──────┐     ┌─────────────┐     ┌─────────────┐                    │
│  │ ECS Services│────▶│  Amazon MQ  │     │ ElastiCache │                    │
│  │ (5 services)│     │  RabbitMQ   │     │   Redis     │                    │
│  └─────────────┘     └─────────────┘     └─────────────┘                    │
│                                                                              │
│  ┌─────────────┐     ┌─────────────┐                                        │
│  │  CloudWatch │     │     ALB     │                                        │
│  │   Alarms    │     │             │                                        │
│  └─────────────┘     └─────────────┘                                        │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Operator Access

Operator access allows your on-call engineers and DevOps team to interact with the AWS DevOps Agent through a dedicated web application.

#### Enabling Operator Access

1. Navigate to your Agent Space
2. Click **Operator access** in the left navigation
3. Click **Enable operator access** if not already enabled

#### Starting an Investigation

From the Operator Web App:

1. Click **Start Investigation**
2. Choose a starting point:
   - **Latest alarm** - Investigate the most recent CloudWatch alarm
   - **High CPU usage** - Analyze CPU utilization across resources
   - **Error rate spike** - Investigate application error increases
   - **Custom** - Describe the issue in your own words

3. Provide investigation details:
   - **Investigation details** - Describe what you're investigating
   - **Date and time** - When the incident occurred
   - **AWS Account ID** - The account containing the affected resources

4. Click **Start** and watch the investigation unfold in real-time

#### Safety Mechanisms

| Mechanism | Description |
|-----------|-------------|
| **Read-Only by Default** | The agent only reads data; it does not modify resources |
| **Scoped Access** | Access is limited to resources within the Agent Space |
| **Audit Logging** | All agent actions are logged to CloudTrail |
| **Human-in-the-Loop** | Mitigation recommendations require human approval |

### Official Documentation

| Resource | URL | Description |
|----------|-----|-------------|
| **Product Page** | https://aws.amazon.com/devops-agent | Overview and sign-up |
| **AWS News Blog** | [Launch Announcement](https://aws.amazon.com/blogs/aws/aws-devops-agent-helps-you-accelerate-incident-response-and-improve-system-reliability-preview/) | Detailed walkthrough |
| **User Guide** | [Creating an Agent Space](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-creating-an-agent-space.html) | Step-by-step setup |

---

## Fault Injection Scenarios

The `fault-injection/` directory contains scripts for chaos engineering experiments on ECS. These scripts use ECS Exec to inject real faults into running containers, allowing you to test the DevOps Agent's investigation capabilities.

### Prerequisites

- ECS Exec must be enabled on the cluster (enabled by default in this deployment)
- AWS CLI configured with appropriate permissions
- Session Manager plugin installed: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

### Demo Workflow

For a training session, follow this workflow:

```
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  1. Inject Fault    │────▶│  2. Observe Symptoms│────▶│  3. Start           │
│  (run inject script)│     │  (monitoring tools) │     │  Investigation      │
└─────────────────────┘     └─────────────────────┘     └──────────┬──────────┘
                                                                   │
                                                                   ▼
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────┐
│  6. Rollback Fault  │◀────│  5. Review & Approve│◀────│  4. Agent Analyzes  │
│  (run rollback      │     │  Recommendations    │     │  & Correlates Data  │
│   script)           │     │                     │     │                     │
└─────────────────────┘     └─────────────────────┘     └─────────────────────┘
```

### Available Scenarios

| Scenario | Inject Script | Rollback Script | Target Service |
|----------|---------------|-----------------|----------------|
| [CPU Stress](#1-cpu-stress-injection) | `inject-cpu-stress.sh` | `rollback-cpu-stress.sh` | catalog |
| [Memory Stress](#2-memory-stress-injection) | `inject-memory-stress.sh` | `rollback-memory-stress.sh` | carts |
| [DynamoDB Latency](#3-dynamodb-latency-injection) | `inject-dynamodb-latency.sh` | `rollback-dynamodb-latency.sh` | carts |
| [RDS Security Group Block](#4-rds-security-group-block) | `inject-rds-sg-block.sh` | `rollback-rds-sg-block.sh` | catalog, orders |
| [RDS Stress Test](#5-rds-database-stress-test) | `inject-rds-stress.sh` | (auto-terminates) | catalog |

---

### 1. CPU Stress Injection

Simulates high CPU utilization in the Catalog service using stress-ng.

**What it does:**
- Spawns CPU stress workers inside the running container
- Default: 2 workers for 5 minutes

**Expected symptoms:**
- CPU utilization spikes in CloudWatch Container Insights
- Increased response latency for product catalog
- Potential task throttling or health check failures

**Run the scenario:**
```bash
# Inject the fault (default: 2 workers, 5 minutes)
./fault-injection/inject-cpu-stress.sh

# With custom parameters
CPU_WORKERS=4 STRESS_DURATION=120 ./fault-injection/inject-cpu-stress.sh

# Rollback (or wait for auto-rollback)
./fault-injection/rollback-cpu-stress.sh
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Product catalog is responding slowly. Users are complaining about slow page loads when browsing products."

> **Investigation Starting Point:** "Check the catalog ECS service. Look at CPU metrics and task health in CloudWatch Container Insights."

---

### 2. Memory Stress Injection

Simulates memory pressure in the Carts service using stress-ng.

**What it does:**
- Allocates memory inside the running container
- Default: 80% of available memory for 5 minutes

**Expected symptoms:**
- Memory utilization spikes in CloudWatch Container Insights
- Potential OOMKill events and task restarts
- Cart operations may fail or timeout

**Run the scenario:**
```bash
# Inject the fault (default: 80% memory, 5 minutes)
./fault-injection/inject-memory-stress.sh

# With custom parameters
MEMORY_PERCENT=90 STRESS_DURATION=180 ./fault-injection/inject-memory-stress.sh

# Rollback (or wait for auto-rollback)
./fault-injection/rollback-memory-stress.sh
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Cart service is unstable. Users are seeing errors when adding items to cart. Tasks seem to be restarting."

> **Investigation Starting Point:** "Check the carts ECS service for task restarts and OOMKill events. Look at memory usage patterns in Container Insights."

---

### 3. DynamoDB Latency Injection

Adds artificial network latency to DynamoDB calls from the Carts service.

**What it does:**
- Uses `tc qdisc netem` to inject network latency
- Default: 500ms latency for 5 minutes

**Expected symptoms:**
- Cart operations slow (add to cart, view cart)
- DynamoDB latency increase visible in CloudWatch
- Application timeouts during checkout

**Run the scenario:**
```bash
# Inject the fault (default: 500ms, 5 minutes)
./fault-injection/inject-dynamodb-latency.sh

# With custom parameters
LATENCY_MS=1000 STRESS_DURATION=300 ./fault-injection/inject-dynamodb-latency.sh

# Rollback (or wait for auto-rollback)
./fault-injection/rollback-dynamodb-latency.sh
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Adding items to cart is super slow. Used to be instant but now takes 3-5 seconds. Checkout is also sluggish."

> **Investigation Starting Point:** "Check DynamoDB metrics for the carts table. Look at latency and any throttling. Also check the carts ECS service."

---

### 4. RDS Security Group Block

Simulates an accidental security group change that blocks ECS tasks from connecting to RDS.

**What it does:**
- Removes the ingress rule allowing ECS tasks to access RDS on port 3306
- RDS instance remains healthy but unreachable

**Expected symptoms:**
- Catalog and Orders service failures
- "Connection timed out" errors in task logs
- ALB returning 500/502/504 errors
- RDS shows healthy in console but unreachable

**Run the scenario:**
```bash
# Inject the fault
./fault-injection/inject-rds-sg-block.sh

# Monitor application failures
aws logs tail /ecs/retail-store-ecs --follow

# Rollback (requires backup file path)
./fault-injection/rollback-rds-sg-block.sh /tmp/rds-sg-backup-<timestamp>.json
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Catalog and orders are completely down. Getting 500 errors. RDS shows healthy in the console but apps can't seem to connect."

> **Investigation Starting Point:** "Check the RDS security groups and VPC configuration. The database is up but something is blocking connections from ECS tasks."

---

### 5. RDS Database Stress Test

Creates heavy load on the RDS MariaDB instance to simulate database performance degradation.

**What it does:**
- Runs complex queries causing full table scans
- Generates lock contention and high CPU usage

**Expected symptoms:**
- RDS CPU utilization: 70-100%
- Slow queries visible in RDS Performance Insights
- Catalog service timeouts and errors

**Run the scenario:**
```bash
# Inject the fault
./fault-injection/inject-rds-stress.sh

# Monitor RDS metrics in AWS Console
# RDS > Performance Insights > retail-store-ecs-catalog

# The stress test auto-terminates after completion
```

**DevOps Agent Investigation Prompts:**

> **Investigation Details:** "Product catalog is timing out. Database seems to be under heavy load. Users can't browse products."

> **Investigation Starting Point:** "Check the RDS MariaDB instance for the catalog service. Look at Performance Insights for slow queries and CPU usage."

---

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLUSTER_NAME` | `retail-store-ecs-cluster` | ECS cluster name |
| `SERVICE_NAME` | varies | Target ECS service |
| `AWS_REGION` | `us-east-1` | AWS region |
| `STRESS_DURATION` | `300` | Duration in seconds |
| `CPU_WORKERS` | `2` | Number of CPU stress workers |
| `MEMORY_PERCENT` | `80` | Target memory percentage |
| `LATENCY_MS` | `500` | Network latency in milliseconds |

### Rollback Notes

- **CPU, Memory, DynamoDB Latency**: Auto-rollback after the specified duration
- **RDS Security Group Block**: Requires manual rollback with the backup file path

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the MIT-0 License.

This package depends on and may incorporate or retrieve a number of third-party
software packages (such as open source packages) at install-time or build-time
or run-time ("External Dependencies"). The External Dependencies are subject to
license terms that you must accept in order to use this package. If you do not
accept all of the applicable license terms, you should not use this package. We
recommend that you consult your company’s open source approval policy before
proceeding.

Provided below is a list of External Dependencies and the applicable license
identification as indicated by the documentation associated with the External
Dependencies as of Amazon's most recent review.

THIS INFORMATION IS PROVIDED FOR CONVENIENCE ONLY. AMAZON DOES NOT PROMISE THAT
THE LIST OR THE APPLICABLE TERMS AND CONDITIONS ARE COMPLETE, ACCURATE, OR
UP-TO-DATE, AND AMAZON WILL HAVE NO LIABILITY FOR ANY INACCURACIES. YOU SHOULD
CONSULT THE DOWNLOAD SITES FOR THE EXTERNAL DEPENDENCIES FOR THE MOST COMPLETE
AND UP-TO-DATE LICENSING INFORMATION.

YOUR USE OF THE EXTERNAL DEPENDENCIES IS AT YOUR SOLE RISK. IN NO EVENT WILL
AMAZON BE LIABLE FOR ANY DAMAGES, INCLUDING WITHOUT LIMITATION ANY DIRECT,
INDIRECT, CONSEQUENTIAL, SPECIAL, INCIDENTAL, OR PUNITIVE DAMAGES (INCLUDING
FOR ANY LOSS OF GOODWILL, BUSINESS INTERRUPTION, LOST PROFITS OR DATA, OR
COMPUTER FAILURE OR MALFUNCTION) ARISING FROM OR RELATING TO THE EXTERNAL
DEPENDENCIES, HOWEVER CAUSED AND REGARDLESS OF THE THEORY OF LIABILITY, EVEN
IF AMAZON HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. THESE LIMITATIONS
AND DISCLAIMERS APPLY EXCEPT TO THE EXTENT PROHIBITED BY APPLICABLE LAW.

MariaDB Community License - [LICENSE](https://mariadb.com/kb/en/mariadb-licenses/)
MySQL Community Edition - [LICENSE](https://github.com/mysql/mysql-server/blob/8.0/LICENSE)
