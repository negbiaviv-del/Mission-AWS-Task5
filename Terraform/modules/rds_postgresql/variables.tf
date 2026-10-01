# ==============================================================================
# משתנה: נפח האחסון המוקצה למסד הנתונים (בג'יגה-בייט)
# ==============================================================================
variable "db_storage" {
  description = "The allocated storage in gigabytes"
  type        = number
  default     = 20
}

# ==============================================================================
# משתנה: גרסת מנוע ה-PostgreSQL
# ==============================================================================
variable "db_engine_version" {
  description = "The version of the PostgreSQL engine"
  type        = string
  default     = "16.3"
}

# ==============================================================================
# משתנה: סוג החומרה של השרת (Instance Class)
# ==============================================================================
variable "db_instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
  default     = "db.t3.micro"
}

# ==============================================================================
# משתנה: שמו של מסד הנתונים שיוקם אוטומטית עם יצירת השרת
# ==============================================================================
variable "db_name" {
  description = "The name of the database to create when the DB instance is created"
  type        = string
  default     = "missiondb"
}

# ==============================================================================
# משתנה: ששת המשתמש הראשי (Admin / Master Username)
# ==============================================================================
variable "db_username" {
  description = "Username for the master DB user"
  type        = string
}

# ==============================================================================
# משתנה: סיסמת המנהל (מוגדרת כרגישה למניעת זליגה ללוגים)
# ==============================================================================
variable "db_password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
}

# ==============================================================================
# משתנה: שם קבוצת הסאבנטים של מסד הנתונים
# ==============================================================================
variable "db_subnet_group_name" {
  description = "Name for the DB subnet group"
  type        = string
  default     = "main-db-subnet-group"
}

# ==============================================================================
# משתנה: רשימת מזהי הסאבנטים (Subnet IDs) שיועברו ממודול ה-Networking
# ==============================================================================
variable "subnet_ids" {
  description = "A list of subnet IDs for the DB subnet group"
  type        = list(string)
}

# ==============================================================================
# משתנה: מזהה חומת האש (Security Group ID) המיועד ל-RDS
# ==============================================================================
variable "db_sg_id" {
  description = "The ID of the security group to associate with the RDS instance"
  type        = string
}