variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type = string
}

variable "iam_role" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_user" {
  type = string
}

variable "sns_topic_name" {
  type = string
}

variable "secret_name" {
  type = string
}

variable "secret_description" {
  type        = string
  description = "The description for the RDS secret"
}

variable "my_ip" {
  description = "Your public IP address"
  type        = string
}

variable "master_db_password" {
  description = "The master password for the RDS PostgreSQL database"
  type        = string
  sensitive   = true # שומר על הסיסמה חסויה בתוך ה-Logs
}

variable "my_alert_email" {
  description = "Email address for SNS subscriptions"
  type        = string
}
