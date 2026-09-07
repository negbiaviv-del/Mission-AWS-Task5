#!/bin/bash
# ==============================================================================
# DevOps Final Project - One-Touch Teardown Script
# Submitted by: Aviv Moshe Negbi
# ==============================================================================

echo "⚠️ WARNING: Starting Full Project Teardown (One-Touch)..."
echo "This will safely destroy all AWS resources and Kubernetes deployments."
echo "========================================"

echo "🧹 Phase 1: Deleting Kubernetes Resources (Clearing ALBs, ELBs & EBS)"
# אנו מתעלמים משגיאות כאן כדי להבטיח שהסקריפט יגיע לשלב ה-Terraform בכל מצב
kubectl delete namespace devops-app --ignore-not-found=true
helm uninstall jenkins -n jenkins || true
kubectl delete namespace jenkins --ignore-not-found=true
helm uninstall kube-prometheus-stack -n observability || true
kubectl delete namespace observability --ignore-not-found=true
echo "✅ Kubernetes resources cleared."
echo ""

echo "🗑️ Phase 2: Cleaning ECR Repositories"
if [ -f "ecr-teardown.sh" ]; then
    chmod +x ecr-teardown.sh
    ./ecr-teardown.sh
    echo "✅ ECR repositories cleaned."
else
    echo "⚠️ ecr-teardown.sh not found, skipping..."
fi
echo ""

echo "🔥 Phase 3: Destroying AWS Infrastructure (Terraform)"
cd Terraform
terraform destroy -auto-approve
cd ..
echo "✅ Infrastructure destroyed successfully."
echo ""

echo "================================================================="
echo "💀 TEARDOWN COMPLETE! ALL RESOURCES HAVE BEEN DESTROYED. 💀"
echo "================================================================="