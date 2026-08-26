#!/bin/bash
set -e

CLUSTER_NAME="aviv-mission-cluster"
REGION="us-east-1"

echo "======================================================"
echo "⚙️ Preparing EKS Cluster for Observability Stack..."
echo "======================================================"

# --- תוספת 1: חיבור אוטומטי לקלאסטר ---
echo "===> Updating Kubeconfig automatically..."
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

echo "===> Ensuring AWS EBS CSI Driver is installed for PVC provisioning..."
aws eks create-addon \
  --cluster-name $CLUSTER_NAME \
  --addon-name aws-ebs-csi-driver \
  --region $REGION \
  --resolve-conflicts OVERWRITE || echo "EBS CSI Driver already exists or is updating."

# נותנים לדרייבר כמה שניות לעלות לפני שמבקשים ממנו דיסקים
sleep 15

echo "===> Cleaning up any previous/stuck Helm releases..."
helm uninstall kube-prometheus-stack -n observability --ignore-not-found --wait || true

echo "===> Creating namespace: observability"
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

echo "===> Adding Prometheus Community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "===> Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  -f monitoring/prometheus-values.yaml

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

# --- תוספת 2: הזרקת הדאשבורדים אוטומטית למערכת ---
echo "===> Injecting Grafana Dashboards as Code..."
kubectl apply -f monitoring/backend-dashboard.yaml
kubectl apply -f monitoring/jenkins-dashboard.yaml

# --- תוספת 3: אבטחת רשת ---
echo "===> Applying Strict NetworkPolicies for Observability..."
kubectl apply -f monitoring/observability-network-policy.yaml

echo "===> Waiting for AWS to provision a Load Balancer for Grafana (this may take 2-3 minutes)..."
while [ -z "$(kubectl get svc kube-prometheus-stack-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)" ]; do
  sleep 10
  echo "Still waiting for AWS ELB..."
done

GRAFANA_URL=$(kubectl get svc kube-prometheus-stack-grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# משיכת הסיסמה הדינמית ישירות למשתנה בתוך הסקריפט
GRAFANA_PASSWORD=$(kubectl get secret -n observability kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode)

echo "======================================================"
echo "✅ Observability Stack successfully installed and connected!"
echo "======================================================"
echo "🌍 Grafana is now automatically exposed to the internet via AWS LoadBalancer:"
echo "URL: http://$GRAFANA_URL"
echo ""
echo "Username: admin"
# מדפיסים את הסיסמה בתוך סוגריים מרובעים כדי שיהיה קל להעתיק אותה בלי רווחים בטעות
echo "Password: [$GRAFANA_PASSWORD]"
echo "======================================================"