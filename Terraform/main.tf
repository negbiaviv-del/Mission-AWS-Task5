# --- הגדרות התחברות לקוברנטיס ו-Helm ---
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# --- מודול רשת (Networking) ---
module "networking" {
  source   = "./modules/networking"
  vpc_cidr = var.vpc_cidr
  my_ip    = var.my_ip
}

# --- מודול הרשאות (IAM) ---
module "iam" {
  source = "./modules/iam"

  oidc_provider_arn       = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  role_name     = var.iam_role
  secret_arn    = module.secrets.secret_arn
  s3_bucket_arn = module.s3.bucket_arn
  sns_topic_arn = module.sns.topic_arn
  sqs_queue_arn = aws_sqs_queue.worker_queue.arn
}

# --- מודול ניהול סודות (Secrets Manager) ---
module "secrets" {
  source             = "./modules/secrets"
  secret_name        = var.secret_name
  secret_description = var.secret_description
  db_password        = var.master_db_password
}

# --- מודול מסד נתונים (RDS PostgreSQL) ---
module "rds_postgresql" {
  source = "./modules/rds_postgresql"

  db_sg_id = module.networking.db_sg_id
  subnet_ids = [
    module.networking.private_subnet_1_id,
    module.networking.private_subnet_2_id
  ]

  db_username = "dbadmin"
  db_password = var.master_db_password
}

# --- מודולים נוספים (S3 & SNS) ---
module "s3" {
  source      = "./modules/s3_bucket"
  bucket_name = var.bucket_name
}

module "sns" {
  source      = "./modules/sns_topic"
  topic_name  = "aviv-project-alerts-v2"
  alert_email = var.my_alert_email
}

# --- תור הודעות (SQS) ---
resource "aws_sqs_queue" "worker_queue" {
  name = "mission-queue-v2"
}

# --- מאגרים לתמונות (ECR) ---
resource "aws_ecr_repository" "backend_repo" {
  name         = "mission-backend"
  force_delete = true
}

resource "aws_ecr_repository" "worker_repo" {
  name         = "mission-worker"
  force_delete = true
}
resource "aws_ecr_repository" "frontend_repo" {
  name         = "mission-frontend"
  force_delete = true
}

resource "random_password" "flask_secret" {
  length  = 20
  special = true
}

resource "kubernetes_namespace" "devops_app" {
  metadata {
    name = "devops-app"
  }
  depends_on = [module.eks]
}

# יצירת סוד רק עבור Flask בקוברנטיס (ה-DB Password מנוהל כעת ע"י External Secrets)
resource "kubernetes_secret" "flask_secret" {
  metadata {
    name      = "flask-secret"
    namespace = kubernetes_namespace.devops_app.metadata[0].name
  }

  data = {
    SECRET_KEY = random_password.flask_secret.result
  }

  type       = "Opaque"
  depends_on = [kubernetes_namespace.devops_app]
}

# הזרקת כתובות ונתונים דינמיים לקוברנטיס
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.devops_app.metadata[0].name
  }

  data = {
    DB_HOST    = module.rds_postgresql.db_instance_address
    DB_NAME    = "missiondb"
    DB_USER    = "dbadmin"
    AWS_REGION = "us-east-1"

    # שליפה אוטומטית של הכתובות וה-ARNs ש-AWS יצר
    SQS_QUEUE_URL = aws_sqs_queue.worker_queue.url
    SNS_TOPIC_ARN = module.sns.topic_arn
    S3_BUCKET     = module.s3.bucket_name
  }

  depends_on = [kubernetes_namespace.devops_app]
}

# --- אבטחת ה-RDS: מתן גישה אך ורק לשרתי ה-EKS ---
resource "aws_security_group_rule" "eks_to_rds" {
  type      = "ingress"
  from_port = 5432
  to_port   = 5432
  protocol  = "tcp"

  # מזהה קבוצת האבטחה של מסד הנתונים
  security_group_id = module.networking.db_sg_id

  # מזהה קבוצת האבטחה של שרתי קוברנטיס (רק הם מורשים לגשת!)
  source_security_group_id = module.eks.node_security_group_id
}

# ==========================================
# IRSA - IAM Roles for Service Accounts
# יצירת תפקידים נפרדים ל-Backend ול-Worker
# ==========================================

# פוליסת הרשאות ל-Backend (כתיבה בלבד + גישה ל-Secrets Manager)
resource "aws_iam_policy" "backend_policy" {
  name        = "aviv-backend-policy"
  description = "Permissions for Backend Pod"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "sqs:SendMessage",
          "sns:Publish",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

module "iam_eks_role_backend" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.0"
  role_name = "aviv-mission-backend-role"

  role_policy_arns = {
    policy = aws_iam_policy.backend_policy.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["devops-app:backend-sa"]
    }
  }
}

# פוליסת הרשאות ל-Worker (קריאה, מחיקה, פרסום + גישה ל-Secrets Manager)
resource "aws_iam_policy" "worker_policy" {
  name        = "aviv-worker-policy"
  description = "Permissions for Worker Pod"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sns:Publish",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

module "iam_eks_role_worker" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.0"
  role_name = "aviv-mission-worker-role"

  role_policy_arns = {
    policy = aws_iam_policy.worker_policy.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["devops-app:worker-sa"]
    }
  }
}

resource "kubernetes_cluster_role_binding" "jenkins_deployer" {
  metadata {
    name = "jenkins-deployer-binding"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin" # לחלופין אפשר ליצור Role מותאם אישית שמורשה לגעת רק ב-devops-app
  }

  subject {
    kind      = "ServiceAccount"
    name      = "jenkins"
    namespace = "jenkins"
  }
}