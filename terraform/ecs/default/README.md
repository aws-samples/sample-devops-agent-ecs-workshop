# AWS Containers Retail Sample - ECS Terraform (Default)

This Terraform module creates all the necessary infrastructure and deploys the retail sample application on [Amazon Elastic Container Service](https://aws.amazon.com/ecs/).

## Architecture

The module deploys a complete microservices architecture with the following components:

**Compute**
- ECS Cluster with Fargate capacity provider
- 5 ECS Services (UI, Catalog, Cart, Checkout, Orders)
- Application Load Balancer for traffic distribution

**Data Stores**
- Aurora MySQL - Catalog database
- Aurora PostgreSQL - Orders database
- DynamoDB - Cart storage
- ElastiCache Redis - Checkout session state
- Amazon MQ (RabbitMQ) - Order message queue

**Networking**
- VPC with public and private subnets across multiple AZs
- NAT Gateway for outbound internet access
- Security Groups controlling service-to-service communication

## Features

- VPC with public and private subnets across multiple AZs
- ECS cluster using Fargate for serverless compute
- 5 microservices: UI, Catalog, Cart, Checkout, Orders
- Data stores: Aurora MySQL (Catalog), Aurora PostgreSQL (Orders), DynamoDB, ElastiCache Redis, Amazon MQ
- ECS Service Connect for service-to-service communication
- Application Load Balancer with health checks
- CloudWatch Container Insights (Enhanced) for observability
- CloudWatch Alarms for CPU, memory, and ALB metrics
- All resources tagged with `ecsdevopsagent=true` for DevOps Agent discovery
- Optional OpenTelemetry integration

## Cost Warning

This will create resources in your AWS account which will incur costs (~$3-4/hour). You are responsible for these costs. Remember to run `terraform destroy` when finished.

## Usage

Pre-requisites for this are:

- AWS, Terraform and kubectl installed locally
- AWS CLI configured and authenticated with account to deploy to

After cloning this repository run the following commands:

```shell
cd terraform/ecs/default

terraform init
terraform plan
terraform apply
```

The final command will prompt for confirmation that you wish to create the specified resources. After confirming the process will take at least 15 minutes to complete. You can then retrieve the HTTP endpoint for the UI from Terraform outputs:

```shell
terraform output -raw application_url
```

Enter the URL in a web browser to access the application.

## Reference

This section documents the variables and outputs of the Terraform configuration.

### Inputs

| Name                         | Description                                                                                                                                               | Type     | Default            | Required |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------ | :------: |
| `environment_name`           | Name of the environment which will be used for all resources created                                                                                      | `string` | `retail-store-ecs` |   yes    |
| `opentelemetry_enabled`      | Flag to enable OpenTelemetry, which will install the AWS Distro for OpenTelemetry and configure trace collection                                          | `bool`   | `false`            |    no    |
| `container_insights_setting` | Container Insights setting for ECS cluster. Must be either 'enhanced' or 'disabled'. When OpenTelemetry is enabled, defaults to 'enhanced'                | `string` | `disabled`         |    no    |
| `lifecycle_events_enabled`   | Enable ECS lifecycle events to CloudWatch Logs for Container Insights performance dashboard. Only available when container_insights_setting is 'enhanced' | `bool`   | `false`            |    no    |
| `log_group_retention_days`   | Number of days to retain logs in CloudWatch Log Groups                                                                                                    | `number` | `30`               |    no    |

### Outputs

| Name              | Description                               |
| ----------------- | ----------------------------------------- |
| `application_url` | URL where the application can be accessed |
