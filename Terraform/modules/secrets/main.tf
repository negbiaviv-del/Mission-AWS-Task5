# ==============================================================================
# יצירת הקופסה (Secret Container) ב-AWS Secrets Manager
# בלוק זה מייצר את המעטפת של הסוד בענן. השורה recovery_window_in_days = 0
# מאפשרת מחיקה מיידית של הסוד בלי תקופת המתנה מעצבנת של 30 יום.
# ==============================================================================
resource "aws_secretsmanager_secret" "db_password" {
  name        = var.secret_name
  description = var.secret_description

  recovery_window_in_days = 0
}

# ==============================================================================
# הזרקת התוכן (Secret Version) לתוך הקופסה
# בלוק זה לוקח את הסיסמה המאובטחת שהוזנקה מבחוץ (var.db_password)
# ושומר אותה בפועל בתוך המעטפת שיצרנו בבלוק הקודם.
# ==============================================================================
resource "aws_secretsmanager_secret_version" "db_password_version" {
  secret_id = aws_secretsmanager_secret.db_password.id

  secret_string = var.db_password
}