#!/bin/bash
set -e

GITHUB_REPO_URL="https://github.com/negbiaviv-del/Mission-AWS-Task5.git"

echo "======================================================"
echo "🔐 Fetching GitHub credentials securely from AWS Secrets Manager..."
echo "======================================================"

SECRET_JSON=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id jenkins-github-auth --query SecretString --output text)

GITHUB_USER=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['username'])")
GITHUB_TOKEN=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['pat'])")

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: Could not fetch GitHub PAT from AWS. Please verify the secret exists in AWS Secrets Manager."
    exit 1
fi
echo "✅ GitHub credentials successfully loaded from AWS!"
echo "======================================================"

echo "==> Creating Jenkins directory..."
mkdir -p jenkins

echo "==> Generating Namespace and RBAC manifests..."
cat << 'EOF' > jenkins/jenkins-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: jenkins
EOF

cat << 'EOF' > jenkins/jenkins-rbac.yaml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-admin
  namespace: jenkins
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-admin
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/exec", "pods/log", "secrets", "configmaps", "services", "persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "statefulsets"]
    verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: jenkins-admin
subjects:
  - kind: ServiceAccount
    name: jenkins-admin
    namespace: jenkins
EOF

echo "==> Generating Jenkins ServiceMonitor for Prometheus..."
cat << 'EOF' > jenkins/jenkins-monitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: jenkins-monitor
  namespace: observability
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: jenkins
      app.kubernetes.io/name: jenkins
  namespaceSelector:
    matchNames:
      - jenkins
  endpoints:
    - port: http
      path: /prometheus/
      interval: 30s
EOF

echo "==> Generating Jenkins Helm values (JCasC)..."
cat << 'EOF' > jenkins/jenkins-values.yaml
controller:
  serviceType: LoadBalancer
  serviceAccount:
    create: false
    name: jenkins-admin

  persistence:
    storageClass: "gp2"
    size: "8Gi"

  containerEnv:
    - name: AWS_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: aws-credentials-secret
          key: aws_access_key_id
    - name: AWS_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: aws-credentials-secret
          key: aws_secret_access_key
    - name: GITHUB_USERNAME
      valueFrom:
        secretKeyRef:
          name: github-credentials-secret
          key: github_username
    - name: GITHUB_TOKEN
      valueFrom:
        secretKeyRef:
          name: github-credentials-secret
          key: github_token

  installPlugins:
    - kubernetes
    - workflow-aggregator
    - git
    - configuration-as-code
    - job-dsl
    - credentials-binding
    - aws-credentials
    - pipeline-stage-view
    - prometheus

  JCasC:
    defaultConfig: true
    configScripts:
      credentials: |
        credentials:
          system:
            domainCredentials:
              - credentials:
                  - aws:
                      scope: GLOBAL
                      id: "aws-credentials"
                      description: "AWS Credentials for ECR"
                      accessKey: "${AWS_ACCESS_KEY_ID}"
                      secretKey: "${AWS_SECRET_ACCESS_KEY}"
                  - usernamePassword:
                      scope: GLOBAL
                      id: "github-credentials"
                      description: "GitHub Credentials for pulling code"
                      username: "${GITHUB_USERNAME}"
                      password: "${GITHUB_TOKEN}"
      setup-jenkins: |
        jobs:
          - script: >
              pipelineJob('Application - CI') {
                  description('CI Pipeline - Builds Docker images and pushes to ECR')
                  definition {
                      cpsScm {
                          scm {
                              git {
                                  remote {
                                      url('https://github.com/negbiaviv-del/Mission-AWS-Task5.git')
                                      credentials('github-credentials')
                                  }
                                  branch('*/main')
                              }
                          }
                          scriptPath('CI-Jenkinsfile')
                      }
                  }
              }
          - script: >
              pipelineJob('Application - CD') {
                  description('CD Pipeline - Deploys a specific image tag to EKS')
                  parameters {
                      stringParam('IMAGE_TAG', '', 'The unique image tag to deploy')
                  }
                  definition {
                      cpsScm {
                          scm {
                              git {
                                  remote {
                                      url('https://github.com/negbiaviv-del/Mission-AWS-Task5.git')
                                      credentials('github-credentials')
                                  }
                                  branch('*/main')
                              }
                          }
                          scriptPath('CD-Jenkinsfile')
                      }
                  }
              }
EOF

echo "==> Applying Namespace, RBAC, and ServiceMonitor..."
kubectl apply -f jenkins/jenkins-namespace.yaml
kubectl apply -f jenkins/jenkins-rbac.yaml
kubectl apply -f jenkins/jenkins-monitor.yaml

echo "==> Automating StorageClass Configuration..."
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || echo "StorageClass gp2 patch failed or already set."

echo "==> Cleaning up previous installation..."
helm uninstall jenkins -n jenkins --ignore-not-found --wait
kubectl delete statefulset jenkins -n jenkins --ignore-not-found
kubectl delete pvc jenkins -n jenkins --ignore-not-found
kubectl delete svc jenkins -n jenkins --ignore-not-found

echo "==> Fetching AWS Credentials from local environment..."
AWS_ACCESS_KEY=$(aws configure get aws_access_key_id)
AWS_SECRET_KEY=$(aws configure get aws_secret_access_key)

echo "==> Creating Kubernetes Secrets for AWS and GitHub..."
kubectl create secret generic aws-credentials-secret \
  --namespace jenkins \
  --from-literal=aws_access_key_id="$AWS_ACCESS_KEY" \
  --from-literal=aws_secret_access_key="$AWS_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic github-credentials-secret \
  --namespace jenkins \
  --from-literal=github_username="$GITHUB_USER" \
  --from-literal=github_token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Jenkins via Helm..."
helm repo add jenkinsci https://charts.jenkins.io || true
helm repo update

helm upgrade --install jenkins jenkinsci/jenkins \
  -n jenkins \
  -f jenkins/jenkins-values.yaml

echo "======================================================"
echo "Jenkins installation initiated successfully!"
echo "======================================================"

echo "⏳ Waiting for Jenkins Pods to be Ready (this can take 3-4 minutes)..."
kubectl rollout status statefulset/jenkins -n jenkins --timeout=300s

echo "⏳ Waiting for AWS to assign a public DNS for Jenkins..."
JENKINS_URL=""
while [ -z "$JENKINS_URL" ]; do
    sleep 5
    JENKINS_URL=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
done

echo "🔑 Extracting Jenkins Admin Password..."
JENKINS_PASSWORD=$(kubectl exec --namespace jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password | tr -d '\r')

echo "===> Automating GitHub Webhook creation..."
curl -s -X POST -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/negbiaviv-del/Mission-AWS-Task5/hooks \
  -d '{
    "name": "web",
    "active": true,
    "events": [
      "push"
    ],
    "config": {
      "url": "http://'"$JENKINS_URL"':8080/github-webhook/",
      "content_type": "json",
      "insecure_ssl": "1"
    }
  }'
echo -e "\n===> GitHub Webhook created successfully!"

echo ""
echo "======================================================"
echo "🚀 JENKINS IS SUCCESSFULLY INSTALLED AND EXPOSED!"
echo "======================================================"
echo "👤 Username : admin"
echo "🔑 Password : $JENKINS_PASSWORD"
echo "🌐 URL      : http://$JENKINS_URL:8080"
echo "======================================================"

echo ""
echo "===> Triggering the first CI build automatically..."
sleep 10

# יצירת קובץ זמני לשמירת ה-Session Cookie
COOKIE_JAR=$(mktemp)

# משיכת ה-Crumb ושמירת ה-Cookie באמצעות הסיסמה שחולצה באופן דינמי
CRUMB=$(curl -s -c "$COOKIE_JAR" -u "admin:${JENKINS_PASSWORD}" "http://${JENKINS_URL}:8080/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

# הרצת הג'וב תוך כדי שליחת ה-Crumb וה-Cookie יחד
if [[ "$CRUMB" == Jenkins-Crumb:* ]]; then
    curl -s -X POST -b "$COOKIE_JAR" -u "admin:${JENKINS_PASSWORD}" -H "$CRUMB" "http://${JENKINS_URL}:8080/job/Application%20-%20CI/build"
    echo -e "\n✅ First build triggered successfully! Check the Jenkins UI."
else
    echo -e "\n⚠️ Could not fetch valid Jenkins crumb. Please trigger the first build manually."
fi

# ניקוי הקובץ הזמני
rm -f "$COOKIE_JAR"