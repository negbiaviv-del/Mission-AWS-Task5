# ==============================================================================
# הגדרות התחברות לקוברנטיס ו-Helm
# ==============================================================================
provider "kubernetes" {
  # כתובת ה-API של הקלאסטר שאליה הטרפורם פונה
  host = module.eks.cluster_endpoint
  # תעודת האבטחה שמאפשרת לטרפורם לסמוך על הקלאסטר ולתקשר איתו בצורה מוצפנת
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    # שימוש במנגנון ההזדהות החדש של קוברנטיס מול ענן AWS
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # מריץ פקודת AWS CLI ששואבת טוקן זמני, כך שאנחנו לא שומרים סיסמאות קשיחות בקוד
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# ==============================================================================
# הגדרת ספק הטרפורם ל-Helm (Helm Provider)
# מטרה: מאפשר לטרפורם להתקין ולנהל חבילות (כמו Ingress Controller, Prometheus)
# ישירות בתוך קלאסטר ה-EKS
# בעזרת מנהל החבילות Helm.
# ==============================================================================
provider "helm" {

  # הבלוק הזה פותח "ערוץ תקשורת" שדרכו Helm
  # יוכל לגשת לקוברנטיס
  kubernetes {

    # הכתובת הפיזית של הקלאסטר (ה-API Server)
    # שאליה Helm שולח את פקודות ההתקנה
    host = module.eks.cluster_endpoint

    # תעודת האבטחה (CA) של הקלאסטר, שמאפשרת ל-Helm
    # לוודא שהוא מתקשר עם הקלאסטר הנכון ולא עם מתחזה = מוצפן
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    # מנגנון הזדהות דינמי: במקום לתת ל-Helm
    # סיסמה קבועה שעלולה לדלוף, אנחנו משתמשים ב-exec
    exec {
      # גרסת ממשק ההזדהות של קוברנטיס שאיתה אמזון (AWS) עובדת
      api_version = "client.authentication.k8s.io/v1beta1"

      # אנחנו אומרים ל-Helm:
      # "תריץ את פקודת aws בטרמינל כדי להשיג לעצמך אישור כניסה"
      command = "aws"

      # הפרמטרים שמועברים לפקודה: פנייה לשירות EKS,
      # ובקשה ספציפית לטוקן (get-token) שמיועד לקלאסטר שלנו
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# ==============================================================================
# מודול רשת (Networking)
# ==============================================================================
module "networking" {
  # הנתיב שבו הטרפורם ימצא את קבצי המודול הזה (התיקייה המקומית שלנו)
  source = "./modules/networking"

  # מעביר למודול את טווח הכתובות הראשי (CIDR)
  # כדי שידע איך לחלק את הסאבנטים
  vpc_cidr = var.vpc_cidr

  # מעביר את ה-IP
  # שלך כדי ליצור חוקי גישה ספציפיים אם צריך
  my_ip = var.my_ip
}

# ==============================================================================
# מודול הרשאות כלליות (IAM) - עבור המשאבים הבסיסיים
# ==============================================================================
module "iam" {
  source = "./modules/iam"

  # כדי לחבר בין זהויות קוברנטיס לזהויות AWS,
  # אנחנו מעבירים את פרטי ה-OIDC
  # של הקלאסטר
  oidc_provider_arn       = module.eks.oidc_provider_arn
  cluster_oidc_issuer_url = module.eks.cluster_oidc_issuer_url

  # מעבירים למודול את הכתובות המדויקות (ARNs)
  # של המשאבים כדי שהפוליסות יהיו מדויקות (Least Privilege)
  # ולא פתוחות לכל הענן
  secret_arn    = module.secrets.secret_arn
  s3_bucket_arn = module.s3.bucket_arn
  sns_topic_arn = module.sns.topic_arn
  sqs_queue_arn = aws_sqs_queue.worker_queue.arn
}

# ==============================================================================
# מודול ניהול סודות (Secrets Manager)
# ==============================================================================
module "secrets" {
  source = "./modules/secrets"
  # שם הסוד כפי שיופיע בממשק של אמזון (למשל: aviv-db-password)
  secret_name = var.secret_name
  # תיאור קצר שיעזור לנו לזהות מה הסוד הזה מכיל
  secret_description = var.secret_description
  # הסיסמה עצמה (שנמשכת מקובץ ה-tfvars המוסתר שלנו) שתישמר מוצפנת בענן
  db_password = var.master_db_password
}

# ==============================================================================
# מודול מסד נתונים (RDS PostgreSQL)
# ==============================================================================
module "rds_postgresql" {
  source = "./modules/rds_postgresql"

  # מעביר ל-RDS
  # את חומת האש שיצרנו עבורו במודול ה-Networking
  db_sg_id = module.networking.db_sg_id

  # מעביר לו רשימה של הסאבנטים הפרטיים כדי ש-AWS
  # תדע איפה פיזית למקם את השרת
  subnet_ids = [
    module.networking.private_subnet_1_id,
    module.networking.private_subnet_2_id
  ]

  # שם המשתמש הראשי למסד הנתונים
  db_username = "dbadmin"
  # הסיסמה שתוזן בעת יצירת השרת
  db_password = var.master_db_password
}

# ==============================================================================
# מודול דלי אחסון (S3 Bucket)
# ==============================================================================
module "s3" {
  source = "./modules/s3_bucket"
  # השם הייחודי העולמי של דלי האחסון שלנו
  bucket_name = var.bucket_name
}

# ==============================================================================
# מודול התראות (SNS Topic)
# ==============================================================================
module "sns" {
  source = "./modules/sns_topic"
  # השם של נושא ההתראות במערכת
  topic_name = "aviv-project-alerts-v2"
  # האימייל שלך, שאליו אמזון תשלח את ההתראות מהמערכת
  alert_email = var.my_alert_email
}

# ==============================================================================
# תור הודעות (SQS Queue) - מנוהל ישירות ללא מודול כרגע
# ==============================================================================
resource "aws_sqs_queue" "worker_queue" {
  # יצירת תור הודעות פשוט אליו ה-Backend ישלח משימות וה-Worker ישאב אותן
  name = "mission-queue-v2"
}

# ==============================================================================
# מאגרי תמונות דוקר (AWS ECR)
# ==============================================================================
resource "aws_ecr_repository" "backend_repo" {
  # שם המאגר שאליו נדחוף את ה-Image של ה-Backend
  name = "mission-backend"
  # מאפשר למחוק את המאגר (ב-terraform destroy) גם אם יש בתוכו תמונות, כדי שלא ניתקע
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

# ==============================================================================
# יצירת מפתח הצפנה לאפליקציית הפייתון
# ==============================================================================
resource "random_password" "flask_secret" {
  # מייצר מחרוזת אקראית באורך 20 תווים
  length = 20
  # מאפשר שילוב של תווים מיוחדים (כמו @, #) כדי להקשות על פריצה
  special = true
}

# ==============================================================================
# יצירת Namespace (סביבה מבודדת) בתוך קוברנטיס
# ==============================================================================
resource "kubernetes_namespace" "devops_app" {
  metadata {
    # כל הפודים, השירותים והסודות שלנו ירוצו תחת הסביבה הזו, כדי לא ללכלך את ה-default
    name = "devops-app"
  }
  # הבטחה שטרפורם קודם יקים את הקלאסטר (EKS) ורק אז ינסה לייצר בתוכו את ה-Namespace
  depends_on = [module.eks]
}

# ==============================================================================
# יצירת סוד בקוברנטיס (רק עבור Flask)
# ==============================================================================
resource "kubernetes_secret" "flask_secret" {
  metadata {
    # שם הסוד שיופיע בקוברנטיס ושנזריק לפודים
    name = "flask-secret"
    # משייך את הסוד ל-Namespace
    # שיצרנו, כדי שלא יהיה נגיש לכולם
    namespace = kubernetes_namespace.devops_app.metadata[0].name
  }

  data = {
    # לוקח את הסיסמה שיצרנו למעלה, ומכניס אותה למפתח שנקרא SECRET_KEY
    SECRET_KEY = random_password.flask_secret.result
  }

  # סוג הסוד הסטנדרטי בקוברנטיס למידע אטום (מוצפן קידוד 64)
  type       = "Opaque"
  depends_on = [kubernetes_namespace.devops_app]
}

# ==============================================================================
# ConfigMap - מפת הגדרות עבור הפודים
# ==============================================================================
resource "kubernetes_config_map" "app_config" {
  metadata {
    # שם המפה, שאותה הפודים יטענו כדי להפוך את המידע פה למשתני סביבה (Env Vars)
    name      = "app-config"
    namespace = kubernetes_namespace.devops_app.metadata[0].name
  }

  data = {
    # מושך את כתובת ה-RDS
    # היישר ממודול ה-RDS.
    # ככה אם הכתובת תשתנה, הקוד שלנו יתעדכן אוטומטית
    DB_HOST    = module.rds_postgresql.db_instance_address
    DB_NAME    = "missiondb"
    DB_USER    = "dbadmin"
    AWS_REGION = "us-east-1"

    # מושך דינמית את הכתובות של משאבי הענן כדי שה-Backend
    # ידע לאן לשלוח נתונים
    SQS_QUEUE_URL = aws_sqs_queue.worker_queue.url
    SNS_TOPIC_ARN = module.sns.topic_arn
    S3_BUCKET     = module.s3.bucket_name
  }

  depends_on = [kubernetes_namespace.devops_app]
}

# ==============================================================================
# אבטחת רשת - חיבור ה-EKS למסד הנתונים
# ==============================================================================
resource "aws_security_group_rule" "eks_to_rds" {
  # קובע שזהו חוק מסוג "כניסה" (מידע שנכנס ל-RDS)
  type = "ingress"
  # פורט ההתחלה (5432 הוא פורט הדיפולט של PostgreSQL)
  from_port = 5432
  # פורט הסיום (אנחנו פותחים רק פורט אחד)
  to_port = 5432
  # פרוטוקול התקשורת
  protocol = "tcp"

  # לאיזו חומת אש אנחנו מוסיפים את החוק הזה? לחומת האש של ה-RDS
  security_group_id = module.networking.db_sg_id

  # מי מורשה להיכנס? רק שרתים (Worker Nodes)
  # שלובשים את חומת האש של קלאסטר ה-EKS
  source_security_group_id = module.eks.node_security_group_id
}

# ==============================================================================
# IRSA - חיבור בין פוד ה-Backend להרשאות AWS
# ==============================================================================
resource "aws_iam_policy" "backend_policy" {
  # יצירת פוליסת IAM המכילה אך ורק את הפעולות שה-Backend
  # חייב לבצע
  name        = "aviv-backend-policy"
  description = "Permissions for Backend Pod"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",                  # העלאת קבצים בלבד (לא מחיקה)
          "sqs:SendMessage",               # שליחת הודעות לתור ה-Worker
          "sns:Publish",                   # הדלקה של התראות
          "secretsmanager:GetSecretValue", # קריאת סיסמת ה-DB כדי להתחבר ל-RDS
          "secretsmanager:DescribeSecret"
        ]
        # במערכת פרודקשן אמיתית נצמצם את ה-Resource
        # רק למשאבים הספציפיים (כרגע פתוח לצורך נוחות בפיתוח
        Resource = "*"
      }
    ]
  })
}

module "iam_eks_role_backend" {
  # מודול רשמי של אמזון שבונה תפקיד (Role)
  # שמותאם ספציפית לפודים בקוברנטיס
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"
  # השם של ה-Role
  # שיופיע במסך ה-IAM
  # באמזון
  role_name = "aviv-mission-backend-role"

  # הצמדת הפוליסה המדויקת שיצרנו בבלוק הקודם אל התפקיד הזה
  role_policy_arns = {
    policy = aws_iam_policy.backend_policy.arn
  }

  oidc_providers = {
    main = {
      # חיבור לספק הזהויות של הקלאסטר
      provider_arn = module.eks.oidc_provider_arn
      # קובע שרק ה-Service Account
      # שנקרא backend-sa
      # יקבל את התפקיד הזה. זה אוטם אבטחתית את הקלאסטר!
      namespace_service_accounts = ["devops-app:backend-sa"]
    }
  }
}

# ==============================================================================
# IRSA - חיבור בין פוד ה-Worker
# להרשאות AWS
# ==============================================================================
resource "aws_iam_policy" "worker_policy" {
  name        = "aviv-worker-policy"
  description = "Permissions for Worker Pod"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", # ה-Worker
          # לא כותב נתונים, רק קורא אותם מהדלי לעיבוד
          "sqs:ReceiveMessage",     # שאיבת משימות מהתור
          "sqs:DeleteMessage",      # מחיקת משימה מהתור אחרי שסיימנו לעבד אותה בהצלחה
          "sqs:GetQueueAttributes", # מאפשר לו לבדוק כמה משימות ממתינות לו
          "sns:Publish",            # הוצאת התראה על סיום עבודה
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
      provider_arn = module.eks.oidc_provider_arn
      # רק פוד שעולה עם זהות worker-sa
      # יוכל לקרוא/למחוק הודעות מ-SQS
      namespace_service_accounts = ["devops-app:worker-sa"]
    }
  }
}

# ==============================================================================
# הקצאת הרשאות בקלאסטר (RBAC)
# עבור שרת ה-Jenkins
# ==============================================================================
resource "kubernetes_cluster_role_binding" "jenkins_deployer" {
  metadata {
    # שם החיבור (Binding)
    # שמאחד בין תפקיד לבין משתמש
    name = "jenkins-deployer-binding"
  }

  role_ref {
    # אנחנו בוחרים בתפקיד מובנה של קוברנטיס שנקרא
    # "cluster-admin" (אדמין מלא)
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    # אנחנו מצמידים את הרשאות האדמין למשתמש מיוחד (Service Account)
    # שנקרא jenkins.
    # זה מאפשר לשרת ה-Jenkins
    # להריץ פקודות kubectl
    # בתוך הקלאסטר כדי לעדכן קוד.
    kind      = "ServiceAccount"
    name      = "jenkins"
    namespace = "jenkins"
  }
}