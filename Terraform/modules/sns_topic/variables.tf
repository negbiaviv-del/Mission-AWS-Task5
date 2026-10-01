# ==============================================================================
# משתנה: שם ערוץ ההתראות (Topic Name)
# ==============================================================================
variable "topic_name" {
  description = "The name of the SNS topic for application alerts"
  type        = string
  default     = "aviv-project-alerts-v2"
}

# ==============================================================================
# משתנה: כתובת האימייל לקבלת ההתראות (מוגדר כמידע רגיש)
# ==============================================================================
variable "alert_email" {
  description = "The email address that will receive the SNS alerts"
  type        = string
  sensitive   = true
}