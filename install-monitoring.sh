#!/bin/bash
set -e

CLUSTER_NAME="aviv-mission-cluster"
REGION="us-east-1"

# === 1. הכנת תשתית וחיבור לקלאסטר ===
# מעדכן את הרשאות הגישה המקומיות כדי שנוכל לדבר עם הקלאסטר של EKS באמזון. מתקין את התוסף aws-ebs-csi-driver, שמאפשר לקוברנטיס ליצור ולנהל כוננים קשיחים וירטואליים (EBS) ב-AWS באופן אוטומטי (קריטי לשמירת נתונים - Retention).
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

# === 2. ניקוי והכנת הסביבה לניטור ===
# מסיר התקנות קודמות של מערכת הניטור אם יש כאלה (כדי למנוע התנגשויות), ויוצר סביבה (Namespace) חדשה בשם observability שבה נתקין את כל רכיבי הניטור.
echo "===> Cleaning up any previous/stuck Helm releases..."
helm uninstall kube-prometheus-stack -n observability --ignore-not-found --wait || true

echo "===> Creating namespace: observability"
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

# === 3. התקנת חבילת הניטור (Prometheus + Grafana) ===
# מוסיף את המאגר הרשמי של Prometheus ומתקין את כל החבילה (Prometheus, Grafana, Alertmanager) במכה אחת בעזרת Helm, תוך שימוש בקובץ הגדרות מותאם אישית (prometheus-values.yaml).
echo "===> Adding Prometheus Community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "===> Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  -f monitoring/prometheus-values.yaml

# === 4. יצירת סרוויס מוניטור (ServiceMonitor) ===
# מייצר קובץ שמנחה את פרומיתיאוס לזהות אוטומטית פודים עם התגית `app: backend` ב-Namespace של האפליקציה, ולהתחיל לשאוב מהם מטריקות בנתיב `/metrics` כל 15 שניות (Service Discovery).
echo "===> Generating Backend ServiceMonitor for Prometheus..."
cat << 'EOF' > monitoring/app-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: backend-monitor
  namespace: observability
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: backend
  namespaceSelector:
    matchNames:
      - devops-app
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
EOF

echo "===> Applying Backend ServiceMonitor..."
kubectl apply -f monitoring/app-monitor.yaml

# === 5. הזרקת לוחות בקרה והתראות ===
# מעלה אוטומטית לגרפאנה דאשבורדים מוכנים מראש (Dashboards as Code) עבור האפליקציה וג'נקינס. בנוסף, מעלה כללי התראות (Alerts) שיקפיצו שגיאות אם משהו קורס.
echo "===> Injecting Grafana Dashboards as Code..."
kubectl apply -f monitoring/backend-dashboard.yaml
kubectl apply -f monitoring/jenkins-dashboard.yaml

echo "===> Applying Application Alerts (PrometheusRules)..."
kubectl apply -f monitoring/app-alerts.yaml

# === 6. אבטחת רשת ומשיכת כתובת לגרפאנה ===
# מפעיל חוקי רשת (NetworkPolicies) כדי לבודד ולהגן על סביבת הניטור. לאחר מכן, ממתין ש-AWS תעניק לגרפאנה כתובת גישה חיצונית (Load Balancer URL) כדי שנוכל להיכנס אליה דרך הדפדפן.
echo "===> Applying Strict NetworkPolicies for Observability..."
kubectl apply -f monitoring/observability-network-policy.yaml

echo "===> Waiting for AWS to provision a Load Balancer for Grafana (this may take 2-3 minutes)..."
while [ -z "$(kubectl get svc kube-prometheus-stack-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)" ]; do
  sleep 10
  echo "Still waiting for AWS ELB..."
done

GRAFANA_URL=$(kubectl get svc kube-prometheus-stack-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# === 7. חילוץ סיסמה והדפסת פרטי גישה ===
# שולף מתוך הסודות (Secrets) של קוברנטיס את הסיסמה המאובטחת שנוצרה לגרפאנה, ומדפיס למסך את הכתובת, שם המשתמש והסיסמה כדי שתוכל להתחבר מיד.
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