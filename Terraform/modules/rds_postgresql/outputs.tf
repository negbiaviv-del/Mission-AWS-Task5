# ==============================================================================
# פלט: נקודת החיבור המלאה (Endpoint) של מסד הנתונים
# משמש את האפליקציה (ה-Backend) כדי לדעת לאן לשלוח פקודות SQL.
# ==============================================================================
output "db_instance_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.postgres.endpoint
}

# ==============================================================================
# פלט: מזהה השרת הייחודי (DB Instance ID)
# ==============================================================================
output "db_instance_id" {
  description = "The ID of the RDS instance"
  value       = aws_db_instance.postgres.id
}

# ==============================================================================
# פלט: מספר הפורט של מסד הנתונים (לרוב 5432 עבור PostgreSQL)
# ==============================================================================
output "db_port" {
  description = "The port the database is listening on"
  value       = aws_db_instance.postgres.port
}

# ==============================================================================
# פלט: כתובת השרת הציבורית/פנימית (Address)
# ==============================================================================
output "db_instance_address" {
  description = "The address of the RDS instance"
  value       = aws_db_instance.postgres.address
}