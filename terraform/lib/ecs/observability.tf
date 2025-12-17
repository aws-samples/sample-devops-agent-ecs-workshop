# =============================================================================
# ECS Observability Module
# Production-grade observability: logging, metrics, tracing, alerts, dashboards
# =============================================================================

data "aws_region" "observability" {}
data "aws_caller_identity" "observability" {}

# -----------------------------------------------------------------------------
# Variables for observability features
# -----------------------------------------------------------------------------

locals {
  log_group_name     = "${var.environment_name}-tasks"
  cluster_name       = "${var.environment_name}-cluster"
  alb_name           = "${var.environment_name}-ui"
  dashboard_name     = "${var.environment_name}-ecs-dashboard"
  alarm_name_prefix  = var.environment_name
  services           = ["ui", "catalog", "carts", "checkout", "orders"]
}

# Note: Main ECS task log group is defined in cluster.tf (aws_cloudwatch_log_group.ecs_tasks)

# -----------------------------------------------------------------------------
# ALB Access Logs (S3)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "alb_logs" {
  count  = var.alb_access_logs_enabled ? 1 : 0
  bucket = "${var.environment_name}-alb-logs-${data.aws_caller_identity.observability.account_id}"

  tags = merge(var.tags, {
    Purpose = "ALB Access Logs"
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count  = var.alb_access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = var.alb_logs_retention_days
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count  = var.alb_access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count  = var.alb_access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_elb_service_account" "main" {
  count = var.alb_access_logs_enabled ? 1 : 0
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count  = var.alb_access_logs_enabled ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_elb_service_account.main[0].arn
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs[0].arn}/*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.alb_logs[0].arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# VPC Flow Logs
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  count             = var.vpc_flow_logs_enabled ? 1 : 0
  name              = "${var.environment_name}-vpc-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = merge(var.tags, {
    Purpose = "VPC Flow Logs"
  })
}

resource "aws_iam_role" "vpc_flow_logs" {
  count = var.vpc_flow_logs_enabled ? 1 : 0
  name  = "${var.environment_name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  count = var.vpc_flow_logs_enabled ? 1 : 0
  name  = "${var.environment_name}-vpc-flow-logs"
  role  = aws_iam_role.vpc_flow_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs[0].arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "vpc" {
  count                = var.vpc_flow_logs_enabled ? 1 : 0
  iam_role_arn         = aws_iam_role.vpc_flow_logs[0].arn
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  traffic_type         = "ALL"
  vpc_id               = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.environment_name}-vpc-flow-logs"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms for ECS Services
# -----------------------------------------------------------------------------

# CPU Utilization Alarm per service
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  for_each = var.cloudwatch_alarms_enabled ? toset(local.services) : toset([])

  alarm_name          = "${local.alarm_name_prefix}-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CpuUtilized"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS ${each.key} service CPU utilization is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = each.key
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# Memory Utilization Alarm per service
resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  for_each = var.cloudwatch_alarms_enabled ? toset(local.services) : toset([])

  alarm_name          = "${local.alarm_name_prefix}-${each.key}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilized"
  namespace           = "ECS/ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS ${each.key} service memory utilization is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = each.key
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# Running Task Count Alarm (service health)
resource "aws_cloudwatch_metric_alarm" "ecs_running_tasks" {
  for_each = var.cloudwatch_alarms_enabled ? toset(local.services) : toset([])

  alarm_name          = "${local.alarm_name_prefix}-${each.key}-no-running-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "ECS ${each.key} service has no running tasks"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = local.cluster_name
    ServiceName = each.key
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# -----------------------------------------------------------------------------
# ALB Alarms
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "${local.alarm_name_prefix}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB 5XX errors exceeded threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_name
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx_errors" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "${local.alarm_name_prefix}-alb-target-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "ALB target 5XX errors exceeded threshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_name
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "${local.alarm_name_prefix}-alb-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 2
  alarm_description   = "ALB p95 latency exceeded 2 seconds"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_name
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "${local.alarm_name_prefix}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "ALB has unhealthy targets"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = local.alb_name
  }

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Log-based Error Metric Filter and Alarm
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "error_logs" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  name           = "${var.environment_name}-error-logs"
  pattern        = "?ERROR ?Error ?error ?FATAL ?Fatal ?fatal ?Exception ?exception"
  log_group_name = aws_cloudwatch_log_group.ecs_tasks.name

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "${var.environment_name}/Logs"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "log_errors" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  alarm_name          = "${local.alarm_name_prefix}-log-error-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorCount"
  namespace           = "${var.environment_name}/Logs"
  period              = 300
  statistic           = "Sum"
  threshold           = 50
  alarm_description   = "High number of errors in application logs"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != null ? [var.alarm_sns_topic_arn] : []

  tags = var.tags

  depends_on = [aws_cloudwatch_log_metric_filter.error_logs]
}

# -----------------------------------------------------------------------------
# CloudWatch Dashboard
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "ecs" {
  count = var.cloudwatch_alarms_enabled ? 1 : 0

  dashboard_name = local.dashboard_name

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# ECS Retail Store - Observability Dashboard"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "CPU Utilization by Service"
          region = data.aws_region.observability.name
          metrics = [
            for svc in local.services : [
              "ECS/ContainerInsights", "CpuUtilized",
              "ClusterName", local.cluster_name,
              "ServiceName", svc
            ]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 1
        width  = 12
        height = 6
        properties = {
          title  = "Memory Utilization by Service"
          region = data.aws_region.observability.name
          metrics = [
            for svc in local.services : [
              "ECS/ContainerInsights", "MemoryUtilized",
              "ClusterName", local.cluster_name,
              "ServiceName", svc
            ]
          ]
          period = 300
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Running Task Count"
          region = data.aws_region.observability.name
          metrics = [
            for svc in local.services : [
              "ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", local.cluster_name,
              "ServiceName", svc
            ]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "ALB Request Count & Latency"
          region = data.aws_region.observability.name
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", local.alb_name],
            [".", "TargetResponseTime", ".", ".", { stat = "p95" }]
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "ALB HTTP Errors"
          region = data.aws_region.observability.name
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", local.alb_name],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            [".", "HTTPCode_Target_4XX_Count", ".", "."]
          ]
          period = 300
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "Network I/O by Service"
          region = data.aws_region.observability.name
          metrics = [
            for svc in local.services : [
              "ECS/ContainerInsights", "NetworkRxBytes",
              "ClusterName", local.cluster_name,
              "ServiceName", svc
            ]
          ]
          period = 300
          stat   = "Average"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs_tasks.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = var.cloudwatch_alarms_enabled ? "https://${data.aws_region.observability.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.observability.name}#dashboards:name=${local.dashboard_name}" : null
}

output "alb_logs_bucket" {
  description = "S3 bucket for ALB access logs"
  value       = var.alb_access_logs_enabled ? aws_s3_bucket.alb_logs[0].id : null
}

output "vpc_flow_logs_group" {
  description = "CloudWatch Log Group for VPC Flow Logs"
  value       = var.vpc_flow_logs_enabled ? aws_cloudwatch_log_group.vpc_flow_logs[0].name : null
}
