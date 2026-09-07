#!/bin/bash
# ==============================================================================
# DevOps Final Project - One-Touch Deployment Script
# Submitted by: Aviv Moshe Negbi
# ==============================================================================

# עצירת הסקריפט במקרה של שגיאה באחד השלבים
set -e

echo "🚀 Starting Full Project Deployment (One-Touch)..."
echo "========================================"

echo "🛠️ Phase 1: Provisioning AWS Infrastructure (Terraform)"
cd Terraform
terraform init
terraform apply -auto-approve
cd ..
echo "✅ Infrastructure provisioned successfully."
echo ""

echo "📊 Phase 2: Installing Observability Stack (Prometheus & Grafana)"
chmod +x install-monitoring.sh
./install-monitoring.sh
echo "✅ Monitoring stack deployed successfully."
echo ""

echo "📈 Phase 2.1: Opening Prometheus Port-Forward"
chmod +x open-prometheus.sh
nohup ./open-prometheus.sh > /dev/null 2>&1 &
echo "✅ Prometheus is running in the background."
echo ""

echo "🌐 Phase 3: Deploying 3-Tier Application (Baseline)"
chmod +x deploy-app.sh
./deploy-app.sh
echo "✅ Application baseline deployed successfully."
echo ""

echo "⚙️ Phase 4: Bootstrapping Jenkins CI/CD & Triggering Automation"
chmod +x install-jenkins.sh
./install-jenkins.sh
echo "✅ Jenkins deployed and first build triggered successfully."
echo ""

# ==============================================================================
# SUMMARY BLOCK: Fetching live data directly from the cluster
# ==============================================================================
echo "================================================================="
echo "🎉 DEPLOYMENT COMPLETE! HERE IS YOUR SYSTEM SUMMARY: 🎉"
echo "================================================================="

# שליפת נתוני גרפאנה
GRAFANA_PASS=$(kubectl get secret -n observability kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode || echo "See script output")
GRAFANA_URL=$(kubectl get svc -n observability kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "See script output")

# שליפת נתוני ג'נקינס
JENKINS_PASS=$(kubectl get secret -n jenkins jenkins -o jsonpath="{.data.jenkins-admin-password}" 2>/dev/null | base64 --decode || echo "See script output")
JENKINS_URL=$(kubectl get ingress -n jenkins -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "See script output")

# שליפת כתובת האפליקציה
APP_URL=$(kubectl get ingress -n devops-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "See script output")

echo ""
echo "📊 GRAFANA"
echo "URL:      http://$GRAFANA_URL"
echo "User:     admin"
echo "Password: $GRAFANA_PASS"
echo ""

echo "⚙️ JENKINS"
echo "URL:      https://$JENKINS_URL"
echo "User:     admin"
echo "Password: $JENKINS_PASS"
echo ""

echo "🌐 APPLICATION (Frontend)"
echo "URL:      https://$APP_URL"
echo "User:     admin"
echo "Password: (Check the output of deploy-app.sh above)"
echo ""

echo "📈 PROMETHEUS"
echo "URL:      http://localhost:9090"
echo "Note:     Port-forward is already running in the background."
echo "================================================================="