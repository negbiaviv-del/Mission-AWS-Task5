# ==============================================================================
# 1. הקמת מרחב האחסון (S3 Bucket)
# הבלוק הזה יוצר את הדלי עצמו. ההגדרה force_destroy
# מאפשרת לנו
# למחוק את הדלי דרך טרפורם גם אם נשארו בתוכו קבצים - קריטי לסביבות פיתוח
# ==============================================================================
resource "aws_s3_bucket" "app_data" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
  }
}

# ==============================================================================
# 2. חסימת גישה ציבורית (Public Access Block)
# הבלוק הזה הוא שכבת אבטחה קריטית. הוא מעביר 4 פקודות חסימה שמונעות
# לחלוטין כל אפשרות לחשוף את הקבצים בדלי לאינטרנט הפתוח.
# ==============================================================================
resource "aws_s3_bucket_public_access_block" "app_data_access" {
  bucket = aws_s3_bucket.app_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ==============================================================================
# 3. הגדרת הצפנה אוטומטית (Server-Side Encryption)
# הבלוק הזה מורה ל-AWS
# להצפין כל קובץ שעולה לדלי באמצעות אלגוריתם AES256,
# כדי להגן על המידע במצב מנוחה (Data at Rest).
# ==============================================================================
resource "aws_s3_bucket_server_side_encryption_configuration" "app_data_crypto" {
  bucket = aws_s3_bucket.app_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}