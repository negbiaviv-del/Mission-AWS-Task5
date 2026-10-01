# ==============================================================================
# פלטים (Outputs) - חשיפת מידע מתוך הקלאסטר והתשתיות החוצה
# ==============================================================================

# פלט: נקודת החיבור המלאה למסד הנתונים (Database Endpoint)
output "database_endpoint" {
  description = "The endpoint of the RDS database"
  # מושך ממודול ה-RDS את הכתובת המלאה כולל הפורט (לדוגמה: missiondb.c3...us-east-1.rds.amazonaws.com:5432)
  # ה-Backend משתמש בזה כדי לדעת לאן לשלוח שאילתות SQL.
  value       = module.rds_postgresql.db_instance_endpoint
}

# פלט: כתובת השרת בלבד (Database Address)
output "db_address" {
  description = "The address of the RDS instance"
  # מושך את הכתובת הנקייה של השרת באמזון *ללא הפורט* (רק ה-URL).
  # נחוץ אם האפליקציה מבקשת לקבל את ההוסט (Host) והפורט בשני משתנים נפרדים.
  value       = module.rds_postgresql.db_instance_address
}

# פלט: שם המשתמש למסד הנתונים (Database Username)
output "db_user" {
  description = "The database username"
  # מושך את שם המשתמש שהזנו (למשל dbadmin).
  # מודפס החוצה כדי שסקריפט ההתקנה או ה-External Secrets ידעו איזה משתמש להזריק לפודים.
  value       = var.db_user
}

# פלט: סיסמת מסד הנתונים (Database Password)
output "db_password" {
  description = "The database password"
  # מושך את סיסמת ה-Admin
  # שהגדרנו.
  value       = var.master_db_password
  # חובה לאבטחת מידע! מסמן לטרפורם שהערך הזה סודי, ולכן הוא לא ידפיס את הסיסמה
  # בטקסט גלוי בטרמינל (יציג `<sensitive>` במקום), כדי למנוע זליגת סיסמאות ללוגים.
  sensitive   = true
}

# חושף את ה-ARN
# של תפקיד ה-IAM
# של ה-Backend
# לצורך שימוש אוטומטי בסקריפטים
output "backend_iam_role_arn" {
  description = "IAM Role ARN for the Backend ServiceAccount"
  value       = module.iam_eks_role_backend.iam_role_arn
}

# חושף את ה-ARN
# של תפקיד ה-IAM
# של ה-Worker
# לצורך שימוש בסקריפט ההקמה
output "worker_iam_role_arn" {
  description = "IAM Role ARN for the Worker ServiceAccount"
  value       = module.iam_eks_role_worker.iam_role_arn
}