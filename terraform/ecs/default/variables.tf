variable "environment_name" {
  type        = string
  default     = "retail-store-ecs"
  description = "Name of the environment"
}

variable "container_image_overrides" {
  type = object({
    default_repository = optional(string)
    default_tag        = optional(string)

    ui       = optional(string)
    catalog  = optional(string)
    cart     = optional(string)
    checkout = optional(string)
    orders   = optional(string)
  })
  default     = {}
  description = "Object that encapsulates any overrides to default values"
}

variable "opentelemetry_enabled" {
  type        = bool
  default     = false
  description = "Boolean value that enables OpenTelemetry."
}

variable "container_insights_setting" {
  type        = string
  default     = "enhanced"
  description = "Container Insights setting for ECS cluster (enhanced or disabled)"

  validation {
    condition     = contains(["enhanced", "disabled"], var.container_insights_setting)
    error_message = "container_insights_setting must be either 'enhanced' or 'disabled'"
  }
}

variable "lifecycle_events_enabled" {
  type        = bool
  default     = false
  description = "Enable ECS lifecycle events to CloudWatch Logs. Note: Requires container_insights_setting to be 'enhanced'."
}

# -----------------------------------------------------------------------------
# Observability Variables
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch Logs retention period in days"
}

variable "logs_kms_key_arn" {
  type        = string
  default     = null
  description = "KMS key ARN for encrypting CloudWatch Logs (optional)"
}

variable "alb_access_logs_enabled" {
  type        = bool
  default     = false
  description = "Enable ALB access logs to S3"
}

variable "alb_logs_retention_days" {
  type        = number
  default     = 30
  description = "S3 lifecycle expiration for ALB access logs"
}

variable "vpc_flow_logs_enabled" {
  type        = bool
  default     = false
  description = "Enable VPC Flow Logs to CloudWatch Logs"
}

variable "cloudwatch_alarms_enabled" {
  type        = bool
  default     = true
  description = "Enable CloudWatch alarms for ECS services and ALB"
}

variable "alarm_sns_topic_arn" {
  type        = string
  default     = null
  description = "SNS topic ARN for CloudWatch alarm notifications"
}