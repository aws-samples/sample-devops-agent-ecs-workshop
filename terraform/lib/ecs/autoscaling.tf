# Auto-scaling configuration for ECS services
# This enables target tracking scaling based on CPU utilization

# UI Service Auto-Scaling
resource "aws_appautoscaling_target" "ui_service" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${module.ui_service.ecs_service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = var.tags

  depends_on = [module.ui_service]
}

resource "aws_appautoscaling_policy" "ui_service_cpu" {
  name               = "${var.environment_name}-ui-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ui_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ui_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ui_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
