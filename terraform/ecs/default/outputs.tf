# -----------------------------------------------------------------------------
# ECS Deployment Outputs
# -----------------------------------------------------------------------------

output "ui_service_url" {
  description = "URL of the UI component"
  value       = module.retail_app_ecs.ui_service_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.retail_app_ecs.ecs_cluster_name
}

# -----------------------------------------------------------------------------
# Observability Outputs
# -----------------------------------------------------------------------------

output "ecs_tasks_log_group" {
  description = "CloudWatch Log Group name for ECS tasks"
  value       = module.retail_app_ecs.ecs_tasks_log_group
}

output "ecs_exec_log_group" {
  description = "CloudWatch Log Group name for ECS Exec sessions"
  value       = module.retail_app_ecs.ecs_exec_log_group
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = module.retail_app_ecs.cloudwatch_dashboard_url
}

output "alb_logs_bucket" {
  description = "S3 bucket for ALB access logs (if enabled)"
  value       = module.retail_app_ecs.alb_logs_bucket
}

output "vpc_flow_logs_group" {
  description = "CloudWatch Log Group for VPC Flow Logs (if enabled)"
  value       = module.retail_app_ecs.vpc_flow_logs_group
}
