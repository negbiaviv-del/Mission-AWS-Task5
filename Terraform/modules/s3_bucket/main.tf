# 1. יצירת הדלי עצמו
resource "aws_s3_bucket" "app_data" {
  bucket        = var.bucket_name
  force_destroy = true # סופר חשוב לפרויקטים: מאפשר למחוק את הדלי גם אם יש בו קבצים!

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
  }
}

# 2. חסימת גישה ציבורית (Best Practice קריטי באבטחה)
resource "aws_s3_bucket_public_access_block" "app_data_access" {
  bucket = aws_s3_bucket.app_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. הפעלת הצפנה אוטומטית לקבצים (Server-Side Encryption)
resource "aws_s3_bucket_server_side_encryption_configuration" "app_data_crypto" {
  bucket = aws_s3_bucket.app_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}