#!/bin/bash
set -e

REGION="us-east-1"
CLUSTER_NAME="aviv-mission-cluster"
TERRAFORM_DIR="Terraform"

echo "☁️ [1/3] Navigating to Terraform directory and initializing..."
cd $TERRAFORM_DIR
terraform init

echo "🏗️ [2/3] Applying Terraform infrastructure (this will take 10-15 minutes)..."
terraform apply -auto-approve

echo "🔗 [3/3] Fetching kubeconfig credentials for the new EKS cluster..."
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

echo "✅ Infrastructure setup and Ingress Controller installation are complete via Terraform!"
echo "➡️ Next step: Run ./deploy-app.sh from the root directory to deploy your application."