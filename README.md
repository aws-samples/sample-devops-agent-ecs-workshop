![Banner](./docs/images/banner.png)

<div align="center">
  <div align="center">

[![Stars](https://img.shields.io/github/stars/aws-containers/retail-store-sample-app)](Stars)
![GitHub License](https://img.shields.io/github/license/aws-containers/retail-store-sample-app?color=green)
![Dynamic JSON Badge](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fraw.githubusercontent.com%2Faws-containers%2Fretail-store-sample-app%2Frefs%2Fheads%2Fmain%2F.release-please-manifest.json&query=%24%5B%22.%22%5D&label=release)
![GitHub Release Date](https://img.shields.io/github/release-date/aws-containers/retail-store-sample-app)

  </div>

  <strong>
  <h2>AWS Containers Retail Sample</h2>
  </strong>
</div>

This is a sample application designed to illustrate various concepts related to containers on AWS. It presents a sample retail store application including a product catalog, shopping cart and checkout.

It provides:

- A demo store-front application with themes, pages to show container and application topology information, generative AI chat bot and utility functions for experimentation and demos.
- An optional distributed component architecture using various languages and frameworks
- A variety of different persistence backends for the various components like MariaDB (or MySQL), DynamoDB and Redis
- The ability to run in different container orchestration technologies like Docker Compose, Kubernetes etc.
- Pre-built container images for both x86-64 and ARM64 CPU architectures
- All components instrumented for Prometheus metrics and OpenTelemetry OTLP tracing
- Support for Istio on Kubernetes
- Load generator which exercises all of the infrastructure

See the [features documentation](./docs/features.md) for more information.

**This project is intended for educational purposes only and not for production use**

![Screenshot](/docs/images/screenshot.png)

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

| Component                  | Language | Container Image                                                             | Helm Chart                                                                        | Description                             |
| -------------------------- | -------- | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | --------------------------------------- |
| [UI](./src/ui/)            | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-ui)       | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-ui-chart)       | Store user interface                    |
| [Catalog](./src/catalog/)  | Go       | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-catalog)  | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-catalog-chart)  | Product catalog API                     |
| [Cart](./src/cart/)        | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-cart)     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-cart-chart)     | User shopping carts API                 |
| [Orders](./src/orders)     | Java     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-orders)   | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-orders-chart)   | User orders API                         |
| [Checkout](./src/checkout) | Node     | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-checkout) | [Link](https://gallery.ecr.aws/aws-containers/retail-store-sample-checkout-chart) | API to orchestrate the checkout process |

## Quickstart

The following sections provide quickstart instructions for various platforms.

### Docker

This deployment method will run the application as a single container on your local machine using `docker`.

Pre-requisites:

- Docker installed locally

Run the container:

```
docker run -it --rm -p 8888:8080 public.ecr.aws/aws-containers/retail-store-sample-ui:1.0.0
```

Open the frontend in a browser window:

```
http://localhost:8888
```

To stop the container in `docker` use Ctrl+C.

### Docker Compose

This deployment method will run the application on your local machine using `docker-compose`.

Pre-requisites:

- Docker installed locally

Download the latest Docker Compose file and use `docker compose` to run the application containers:

```
wget https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/docker-compose.yaml

DB_PASSWORD='<some password>' docker compose --file docker-compose.yaml up
```

Open the frontend in a browser window:

```
http://localhost:8888
```

To stop the containers in `docker compose` use Ctrl+C. To delete all the containers and related resources run:

```
docker compose -f docker-compose.yaml down
```

### Kubernetes

This deployment method will run the application in an existing Kubernetes cluster.

Pre-requisites:

- Kubernetes cluster
- `kubectl` installed locally

Use `kubectl` to run the application:

```
kubectl apply -f https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml
kubectl wait --for=condition=available deployments --all
```

Get the URL for the frontend load balancer like so:

```
kubectl get svc ui
```

To remove the application use `kubectl` again:

```
kubectl delete -f https://github.com/aws-containers/retail-store-sample-app/releases/latest/download/kubernetes.yaml
```

### Terraform (Amazon ECS)

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

## Fault Injection

The `fault-injection/` directory contains scripts for chaos engineering experiments on ECS. These scripts use ECS Exec to inject real faults into running containers.

### Prerequisites

- ECS Exec must be enabled on the cluster (enabled by default in this deployment)
- AWS CLI configured with appropriate permissions
- Session Manager plugin installed: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html

### Available Scenarios

| Script | Description | Target Service |
|--------|-------------|----------------|
| `inject-cpu-stress.sh` | CPU stress using stress-ng | catalog |
| `inject-memory-stress.sh` | Memory stress using stress-ng | carts |
| `inject-dynamodb-latency.sh` | Network latency to DynamoDB | carts |
| `inject-rds-sg-block.sh` | Block RDS security group access | catalog, orders |
| `inject-rds-stress.sh` | Database stress queries | catalog |

### Usage

```bash
# CPU Stress (default: 2 workers, 5 minutes)
./fault-injection/inject-cpu-stress.sh

# With custom parameters
CLUSTER_NAME=my-cluster SERVICE_NAME=ui CPU_WORKERS=4 STRESS_DURATION=60 \
  ./fault-injection/inject-cpu-stress.sh

# Memory Stress (default: 80% memory, 5 minutes)
MEMORY_PERCENT=90 ./fault-injection/inject-memory-stress.sh

# DynamoDB Latency (default: 500ms, 5 minutes)
LATENCY_MS=1000 ./fault-injection/inject-dynamodb-latency.sh

# RDS Security Group Block
./fault-injection/inject-rds-sg-block.sh

# RDS Stress Queries
./fault-injection/inject-rds-stress.sh
```

### Rollback

Each injection script has a corresponding rollback script:

```bash
./fault-injection/rollback-cpu-stress.sh
./fault-injection/rollback-memory-stress.sh
./fault-injection/rollback-dynamodb-latency.sh
./fault-injection/rollback-rds-sg-block.sh /tmp/rds-sg-backup-<timestamp>.json
```

Note: CPU, memory, and DynamoDB latency injections auto-rollback after the specified duration.

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
