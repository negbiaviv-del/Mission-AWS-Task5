variable "secret_name" {
  description = "The name of the secret in AWS Secrets Manager"
  type        = string
  default     = "mission/prod/db-password"
}

variable "secret_description" {
  description = "Description of the secret"
  type        = string
  default     = "Master password for the RDS database"
}

variable "db_password" {
  description = "The actual password string to store in the secret"
  type        = string
  sensitive   = true # חובה! מונע הדפסה של הסיסמה לטרמינל
}