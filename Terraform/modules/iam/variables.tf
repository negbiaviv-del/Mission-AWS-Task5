variable "role_name" {
  description = "The name of the IAM role for EC2"
  type        = string
  default     = "ec2-mission-role"
}

variable "secret_arn" {
  description = "ARN of the Secrets Manager secret"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the SNS topic"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  type        = string
}

variable "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider from EKS"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "The URL of the OIDC Issuer from EKS"
  type        = string
}