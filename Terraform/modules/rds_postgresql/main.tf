# 1. יצירת קבוצת סאבנטים למסד הנתונים
resource "aws_db_subnet_group" "rds_group" {
  name       = var.db_subnet_group_name
  subnet_ids = var.subnet_ids

  tags = {
    Name = "Main-RDS-Subnet-Group"
  }
}

# 2. הקמת מסד הנתונים (PostgreSQL)
resource "aws_db_instance" "postgres" {
  allocated_storage = var.db_storage
  engine            = "postgres"
  engine_version    = var.db_engine_version
  instance_class    = var.db_instance_class
  db_name           = var.db_name
  username          = var.db_username
  password          = var.db_password

  db_subnet_group_name = aws_db_subnet_group.rds_group.name

  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false
  skip_final_snapshot    = true
}