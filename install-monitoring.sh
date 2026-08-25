#!/bin/bash
set -e

CLUSTER_NAME="aviv-mission-cluster"
REGION="us-east-1"

echo "======================================================"
echo "⚙️ Preparing EKS Cluster for Observability Stack..."
echo "======================================================"

echo "===> Ensuring AWS EBS CSI Driver is installed for PVC provisioning..."
# הפקודה מתקינה את הדרייבר, ואם הוא כבר קיים היא פשוט תמשיך הלאה בלי להיכשל
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

echo "======================================================"
echo "✅ Observability Stack successfully installed and connected!"
echo "======================================================"
echo "To access Grafana, run:"
echo "kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n observability"
echo "Username: admin | Password: prom-operator"