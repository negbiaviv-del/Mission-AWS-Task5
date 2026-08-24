#!/bin/bash
set -e

echo "===> Creating namespace: observability"
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -

echo "===> Adding Prometheus Community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "===> Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace observability \
  -f monitoring/prometheus-values.yaml

echo "======================================================"
echo "✅ Observability Stack successfully installed!"
echo "======================================================"
echo "To access Grafana, run:"
echo "kubectl port-forward svc/kube-prometheus-stack-grafana 8080:80 -n observability"
echo "Username: admin | Password: prom-operator"