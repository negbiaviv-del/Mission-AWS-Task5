# --- פלטים ממודול בסיס הנתונים (RDS) ---
output "database_endpoint" {
  description = "The endpoint of the RDS database"
  value       = module.rds_postgresql.db_instance_endpoint
}

output "db_address" {
  description = "The address of the RDS instance"
  value       = module.rds_postgresql.db_instance_address
}

output "db_user" {
  description = "The database username"
  value       = var.db_user
}

output "db_password" {
  description = "The database password"
  value       = var.master_db_password
  sensitive   = true
}

# פלטים חדשים שיועברו אוטומטית לסקריפט הבאש
output "backend_iam_role_arn" {
  description = "IAM Role ARN for the Backend ServiceAccount"
  value       = module.iam_eks_role_backend.iam_role_arn
}

output "worker_iam_role_arn" {
  description = "IAM Role ARN for the Worker ServiceAccount"
  value       = module.iam_eks_role_worker.iam_role_arn
}