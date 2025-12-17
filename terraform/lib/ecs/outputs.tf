output "ui_service_url" {
  description = "URL of the UI component"
  value       = "http://${module.alb.lb_dns_name}"
}

output "catalog_security_group_id" {
  value       = module.catalog_service.task_security_group_id
  description = "Security group ID of the catalog service"
}

output "checkout_security_group_id" {
  value       = module.checkout_service.task_security_group_id
  description = "Security group ID of the checkout service"
}

output "orders_security_group_id" {
  value       = module.orders_service.task_security_group_id
  description = "Security group ID of the orders service"
}

# -----------------------------------------------------------------------------
# Observability Outputs
# -----------------------------------------------------------------------------

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.cluster.name
}

output "ecs_tasks_log_group" {
  description = "CloudWatch Log Group name for ECS tasks"
  value       = aws_cloudwatch_log_group.ecs_tasks.name
}

output "ecs_exec_log_group" {
  description = "CloudWatch Log Group name for ECS Exec sessions"
  value       = aws_cloudwatch_log_group.ecs_exec.name
}
