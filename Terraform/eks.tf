module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "aviv-mission-cluster"
  cluster_version = "1.31" # הגרסה היציבה והמומלצת כרגע

  # --- החיבור לרשת שלך ---
  vpc_id = module.networking.vpc_id
  subnet_ids = [
    module.networking.private_subnet_1_id,
    module.networking.private_subnet_2_id
  ]

  # מאפשר לך להריץ פקודות kubectl מהטרמינל שלך
  cluster_endpoint_public_access = true

  # הגדרת השרתים שיריצו את הקונטיינרים
  eks_managed_node_groups = {
    main_group = {
      min_size       = 1
      max_size       = 4
      desired_size   = 4
      instance_types = ["t3.small"]
      ami_type       = "AL2_x86_64"

      # --- התוספת החדשה: מתן הרשאות לשרתים ליצור דיסקים של EBS ---
      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }

  # --- התוספת החדשה: התקנת הדרייבר בתוך הקלאסטר ---
  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # מאפשר לקוברנטיס לתת הרשאות IAM לפודים
  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true

  tags = {
    Environment = "dev"
    Project     = "aviv-mission"
  }
}

# פלט שידפיס לנו את פקודת ההתחברות לקלאסטר בסיום ההקמה
output "configure_kubectl" {
  description = "Run this command to configure kubectl"
  value       = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
}

# --- טריק DevOps: המתנה להתעוררות הקלאסטר לפני התקנת ה-Helm ---
resource "time_sleep" "wait_for_eks" {
  depends_on      = [module.eks]
  create_duration = "30s"
}

# --- התקנת NGINX Ingress Controller אוטומטית בעזרת Helm ---
resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  # עכשיו ה-Helm מחכה ל-time_sleep, שבעצמו מחכה ל-EKS
  depends_on = [time_sleep.wait_for_eks]

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
}

# --- התקנת External Secrets Operator אוטומטית בעזרת Helm ---
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  # גם פה נחכה שהקלאסטר יהיה מוכן
  depends_on = [time_sleep.wait_for_eks]

  # כיוון שטרפורם לעיתים מדלג על CRDs, נוסיף הגדרה חזקה יותר
  set {
    name  = "installCRDs"
    value = "true"
  }

  # התוספת החדשה: הבטחה שיתבצע סנכרון מלא ואישור של המשאבים
  wait    = true
  timeout = 300
}