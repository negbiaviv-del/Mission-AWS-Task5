variable "topic_name" {
  description = "The name of the SNS topic for application alerts"
  type        = string
  default     = "aviv-project-alerts-v2"

}

variable "alert_email" {
  description = "The email address that will receive the SNS alerts"
  type        = string
  sensitive   = true # שומר על פרטיות האימייל ב-Logs
}