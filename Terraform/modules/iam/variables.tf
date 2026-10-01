# ==============================================================================
# משתנים גלובליים המוגדרים למודול ה-IAM
# ==============================================================================

# משתנה: כתובת הסוד (Secret ARN) מ-Secrets Manager עבור ה-Backend
variable "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  type        = string
}

# משתנה: כתובת ה-S3 (Bucket ARN) לניהול קבצים משותף
variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  type        = string
}

# משתנה: כתובת ה-SNS Topic (Topic ARN) להפצת אירועים
variable "sns_topic_arn" {
  description = "ARN of the SNS topic"
  type        = string
}

# משתנה: כתובת תור ה-SQS (Queue ARN) להעברת משימות אסינכרוניות
variable "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  type        = string
}

# משתנה: כתובת ספק ה-OIDC של קלאסטר ה-EKS (נדרש לצורך אימות מול AWS STS)
variable "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider from EKS"
  type        = string
}

# משתנה: כתובת ה-URL של ספק ה-OIDC מקלאסטר ה-EKS (משמש לבניית תנאי ה-Condition)
variable "cluster_oidc_issuer_url" {
  description = "The URL of the OIDC Issuer from EKS"
  type        = string
}