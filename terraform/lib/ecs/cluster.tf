resource "aws_ecs_cluster" "cluster" {
  name = "${var.environment_name}-cluster"

  # Container Insights with enhanced observability (recommended)
  # Values: "enhanced" (recommended), "enabled" (basic), "disabled"
  setting {
    name  = "containerInsights"
    value = var.container_insights_setting
  }

  # Enable CloudWatch Container Insights configuration
  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = var.logs_kms_key_arn != null ? true : false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec.name
      }
    }
  }

  tags = var.tags
}

# Log group for ECS task logs
resource "aws_cloudwatch_log_group" "ecs_tasks" {
  name              = "${var.environment_name}-tasks"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

# Log group for ECS Exec sessions
resource "aws_cloudwatch_log_group" "ecs_exec" {
  name              = "${var.environment_name}-ecs-exec"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "retailstore.local"
  description = "Service discovery namespace"
  vpc         = var.vpc_id

  tags = var.tags
}
