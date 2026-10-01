# ==============================================================================
# 1. יצירת IAM Role נפרד ומאובטח עבור ה-Backend
# ==============================================================================
resource "aws_iam_role" "backend_role" {
  name = "backend-irsa-role"

  # בלוק האמון (Assume Role Policy): מגדיר מי רשאי "להתחזות" או לקבל את ההרשאות של ה-Role הזה
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        # חיבור לפדרציית הזהויות של ה-EKS (ספק ה-OIDC)
        Principal = {
          Federated = var.oidc_provider_arn
        }
        # תנאי אבטחה קריטי (Condition): מוודא שרק Service Account ספציפי בשם backend-sa בתוך ה-Namespace devops-app יכול להשתמש בטוקן הזה
        Condition = {
          StringEquals = {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:devops-app:backend-sa",
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ==============================================================================
# 2. פוליסת הרשאות מדויקת עבור ה-Backend (Least Privilege)
# מטרת הבלוק: להגביל את ה-Backend אך ורק לפעולות שהוא חייב לבצע תפעולית.
# ==============================================================================
resource "aws_iam_role_policy" "backend_permissions" {
  name = "backend-least-privilege-policy"
  role = aws_iam_role.backend_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # הרשאה 1: שליפת סיסמת מסד הנתונים מתוך ה-Secrets Manager של AWS
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = var.secret_arn
      },
      # הרשאה 2: כתיבת קבצים ל-S3 (העלאת מדיה/קבצים לדלי) - שים לב שהוא לא מורשה למחוק קבצים!
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${var.s3_bucket_arn}/*"
      },
      # הרשאה 3: שליחת התראות או הודעות ל-SNS Topic
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.sns_topic_arn
      },
      # הרשאה 4: שליחת משימות חדשות לתור ה-SQS (כדי שה-Worker ימשוך ויעבד אותן ברקע)
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = var.sqs_queue_arn
      }
    ]
  })
}

# ==============================================================================
# 3. יצירת IAM Role נפרד ומאובטח עבור ה-Worker
# ==============================================================================
resource "aws_iam_role" "worker_role" {
  name = "worker-irsa-role"

  # בלוק האמון (Assume Role Policy): מגדיר את כללי ההזדהות מול ה-EKS עבור ה-Worker
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        # תנאי אבטחה (Condition): מגביל את ה-Role הזה בלעדית ל-Service Account של ה-Worker בלבד
        Condition = {
          StringEquals = {
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:devops-app:worker-sa",
            "${replace(var.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ==============================================================================
# 4. פוליסת הרשאות מדויקת עבור ה-Worker (Least Privilege)
# מטרת הבלוק: מתן הרשאות קריאה וטיפול בתורים וקבצים, תוך חסימה מוחלטת מגישה ל-RDS/Secrets.
# ==============================================================================
resource "aws_iam_role_policy" "worker_permissions" {
  name = "worker-least-privilege-policy"
  role = aws_iam_role.worker_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # הרשאה 1: קריאת קבצים מתוך ה-S3 (כדי לעבד קבצים שהועלו)
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${var.s3_bucket_arn}/*"
      },
      # הרשאה 2: פרסום הודעות ל-SNS
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.sns_topic_arn
      },
      # הרשאה 3: ניהול משימות מול תור ה-SQS (קסימה, בדיקת מאפיינים ומחיקת הודעה לאחר עיבוד מוצלח)
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:GetQueueAttributes",
          "sqs:DeleteMessage"
        ]
        Resource = var.sqs_queue_arn
      }
    ]
  })
}
