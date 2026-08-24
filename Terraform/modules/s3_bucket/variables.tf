variable "bucket_name" {
  description = "The name of the S3 bucket. Must be globally unique across all of AWS!"
  type        = string
}

variable "environment" {
  description = "The environment name for tagging"
  type        = string
  default     = "Prod" # שיניתי ל-Prod כדי שיתאים לשם התיקייה הראשית שלך
}