#!/bin/bash

# ==============================================================================
# הגדרת סביבת ריצה ומשתנים
# (Fail-Fast & Variables)
# מה הבלוק עושה: מורה לסקריפט לעצור מיד אם פקודה נכשלת
# (set -e),
# ומגדיר את זהות הקלאסטר.
# למה צריך את זה: עצירה מיידית מונעת שרשרת תקלות אם שלב קריטי נכשל. שימוש במשתנים
# מונע
# "Hardcoding"
# (כתיבה קשיחה) ומאפשר להסב את הסקריפט לקלאסטר אחר בקלות.
# ==============================================================================
set -e
CLUSTER_NAME="aviv-mission-cluster"
REGION="us-east-1"

# ==============================================================================
# 1. חיבור לקלאסטר והקצאת מנהל התקני אחסון
# (Kubeconfig & EBS CSI)
# מה הבלוק עושה: מחבר את הטרמינל ל-
# EKS ומתקין את הדרייבר
# aws-ebs-csi-driver.
# למה צריך את זה: פרומיתיאוס וגרפאנה שומרים נתונים היסטוריים ודורשים דיסק פיזי
# (Stateful).
# הדרייבר הזה הוא הגשר שמאפשר לקוברנטיס לפנות לאמזון ולייצר כונני אחסון
# (EBS volumes)
# באופן אוטומטי.
# ==============================================================================
echo "======================================================"
echo "⚙️ Preparing EKS Cluster for Observability Stack..."
echo "======================================================"

echo "===> Updating Kubeconfig automatically..."
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

echo "===> Ensuring AWS EBS CSI Driver is installed for PVC provisioning..."
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --region $REGION \
  --resolve-conflicts OVERWRITE || echo "EBS CSI Driver already exists or is updating."

sleep 15

# ==============================================================================
# 2. ניקוי עבר ויצירת סביבה מבודדת
# (Idempotency & Logical Isolation)
# מה הבלוק עושה: מוחק התקנה קודמת אם קיימת, ויוצר
#Namespace
# ייעודי בשם
# observability.
# למה צריך את זה: המחיקה מבטיחה שהסקריפט תמיד יתחיל מדף חלק ויתקן מצבים תקועים.
# ה-Namespace
# מפריד לוגית את מערך הניטור מאפליקציית הפרודקשן כדי למנוע התנגשויות ניהול.
# ==============================================================================
echo "===> Cleaning up any previous/stuck Helm releases..."
helm uninstall kube-prometheus-stack -n observability --ignore-not-found --wait || true

echo "===> Creating namespace: observability"
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# ==============================================================================
# 3. פריסת פלטפורמת הניטור דרך מנהל החבילות
# (Helm Chart Deployment)
# מה הבלוק עושה: מוריד ומתקין את חבילת
# kube-prometheus-stack
# שכוללת את כל רכיבי הניטור.
# למה צריך את זה: במקום לכתוב מאות קבצי
# YAML ידנית,
# Helm
# מתקין לנו פתרון קומפלט מבוסס
# Prometheus Operator,
# תוך דריסת הגדרות ברירת המחדל עם קובץ ה-
# values המותאם שלנו.
# ==============================================================================
echo "===> Adding Prometheus Community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "===> Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  -f monitoring/prometheus-values.yaml

# ==============================================================================
# 4. מנגנון גילוי שירותים אוטומטי
# (Service Discovery / ServiceMonitor)
# מה הבלוק עושה: מייצר אובייקט שמורה לפרומיתיאוס לנטר ספציפית את ה-
# Backend.
# למה צריך את זה: במקום להזין כתובות
#IP
# שמשתנות כל הזמן, קובץ זה אומר ל-
# Operator:
#"חפש כל פוד שנושא את התווית
# 'app: backend',
#  ושאב ממנו נתונים
# (Pull)
#  כל 15 שניות".
# ==============================================================================
echo "===> Applying Backend ServiceMonitor from existing file..."
kubectl apply -f monitoring/app-monitor.yaml

# ==============================================================================
# 5. ניהול תצורה כקוד
# (Configuration as Code / GitOps)
# מה הבלוק עושה: טוען אובייקטים של חוקי התראה
# (PrometheusRules)
# ולוחות בקרה מוכנים
# (Dashboards).
# למה צריך את זה: במקום להגדיר התראות ולוחות דרך הממשק הגרפי מצב שעלול להימחק ולהיעלם
# אנחנו מזריקים אותם לקלאסטר כקוד.
# Operator -ה
# מזהה אותם וטוען אותם לגרפאנה באופן אוטומטי.
# ==============================================================================
echo "===> Injecting Grafana Dashboards as Code..."
kubectl apply -f monitoring/backend-dashboard.yaml
kubectl apply -f monitoring/jenkins-dashboard.yaml

echo "===> Applying Application Alerts (PrometheusRules)..."
kubectl apply -f monitoring/app-alerts.yaml

# ==============================================================================
# 6. אבטחת רשת והמתנה אסינכרונית לנתב החיצוני
# (NetworkPolicies & ELB Wait-State)
# מה הבלוק עושה: אוכף חוקי חומת אש
# (Zero Trust)
# וממתין שאמזון תקצה כתובת אינטרנט.
# למה צריך את זה: הקצאת
# Load Balancer
# פיזי ב-
# AWS
# לוקחת זמן. הלולאה מבטיחה
# שהסקריפט לא ירוץ קדימה וידפיס למשתמש כתובת ריקה, אלא ימתין עד שהשירות יהיה זמין באוויר.
# ==============================================================================
echo "===> Applying Strict NetworkPolicies for Observability..."
kubectl apply -f monitoring/observability-network-policy.yaml

echo "===> Waiting for AWS to provision a Load Balancer for Grafana (this may take 2-3 minutes)..."
while [ -z "$(kubectl get svc kube-prometheus-stack-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)" ]; do
  sleep 10
  echo "Still waiting for AWS ELB..."
done

GRAFANA_URL=$(kubectl get svc kube-prometheus-stack-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# ==============================================================================
# 7. חילוץ סודות והנגשת נתונים למשתמש
# (Secrets Management)
# מה הבלוק עושה: שולף את הסיסמה המקודדת של גרפאנה מתוך מאגר הסודות של קוברנטיס.
# למה צריך את זה: ההתקנה יצרה סיסמה אקראית ומאובטחת המקודדת ב-
# Base64.
# בלוק זה
# מפענח אותה
# (decode)
# ומדפיס אותה יחד עם כתובת הגישה כדי לאפשר כניסה חלקה ומיידית למערכת.
# ==============================================================================
GRAFANA_PASSWORD=$(kubectl get secret -n observability kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

echo "======================================================"
echo "✅ Observability Stack successfully installed and connected!"
echo "======================================================"
echo "🌍 Grafana is now automatically exposed to the internet via AWS LoadBalancer:"
echo "URL: http://$GRAFANA_URL"
echo ""
echo "Username: admin"
echo "Password: [$GRAFANA_PASSWORD]"
echo "======================================================"