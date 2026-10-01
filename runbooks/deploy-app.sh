#!/bin/bash
# ==============================================================================
# הגדרות בסיס
# ==============================================================================
# מה השורה עושה: מורה לסקריפט לעצור מיד אם פקודה כלשהי נכשלת.
# למה צריך את זה: מונע מצב שבו שגיאה אחת קטנה נגררת ומייצרת נזק או חוסר עקביות בשלבים הבאים.
set -e

REGION="us-east-1"
ACCOUNT="544471418394"
ECR_URL="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
NAMESPACE="devops-app"

# שולף את תעודת הזהות של הקוד הנוכחי (כדי לדעת איזו גרסה לפרוס מהענן)
GIT_SHA=$(git rev-parse --short HEAD)
echo "🎯 Target deployment version (Git SHA): $GIT_SHA"

# ==============================================================================
# 1. חיבור לקלאסטר הקוברנטיס
# ==============================================================================
echo "☸️ [1/6] Updating local kubeconfig and fetching IAM Roles..."
# מה הבלוק עושה: נכנס לתיקיית טרפורם, שולף משם את שם הקלאסטר ואת כתובות ההרשאות
# (ARNs)
# של ה-Backend
#  וה-Worker
# שייצרנו מקודם.
# למה צריך את זה: הסקריפט חייב את הנתונים האלו כדי לחבר את המחשב שלך לקלאסטר וכדי להזריק הרשאות לפודים.
cd Terraform
CLUSTER_NAME=$(terraform output -raw configure_kubectl | awk -F'--name ' '{print $2}')
BACKEND_ROLE_ARN=$(terraform output -raw backend_iam_role_arn)
WORKER_ROLE_ARN=$(terraform output -raw worker_iam_role_arn)
cd ..

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# ==============================================================================
# 2. איתור כתובת האתר (Load Balancer)
# ==============================================================================
echo "🌐 [2/6] Fetching dynamic AWS Load Balancer DNS..."
# מה הבלוק עושה: מחפש את הכתובת החיצונית ש-
# AWS
# הקצתה לנתב
#(NGINX)
# וממתין עד שתהיה מוכנה.
# למה צריך את זה: מוודא שהתשתית הפיזית קיימת לפני שפורסים אליה את שכבת התצוגה.
LB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

while [ -z "$LB_HOSTNAME" ]; do
    echo "⏳ Waiting for AWS to assign Load Balancer DNS..."
    sleep 5
    LB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
done
echo "✅ Load Balancer DNS is ready: $LB_HOSTNAME"

# ==============================================================================
# 3. יצירת סביבה (Namespace) והגדרות אבטחה
# ==============================================================================
echo "🔒 [3/6] Managing Kubernetes Namespaces, Local Secrets & TLS..."
# מה הבלוק עושה: מקים את הסביבה הווירטואלית, מייצר תעודת הצפנה
# (TLS)
# לאתר, ומגדיר תוויות.
# למה צריך את זה: בידוד משאבים
# (Namespace)
# ואבטחת המידע שעובר ברשת
# (HTTPS).
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "⚙️ Generating Self-Signed TLS Certificate..."
kubectl delete secret mission-tls -n $NAMESPACE --ignore-not-found 2>/dev/null || true
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -subj "/CN=mission-app" 2>/dev/null
kubectl create secret tls mission-tls --key /tmp/tls.key --cert /tmp/tls.crt -n $NAMESPACE
rm -f /tmp/tls.key /tmp/tls.crt

echo "🏷️ [Auto-Fix] Ensuring ingress-nginx namespace has the correct labels for NetworkPolicies..."
kubectl label namespace ingress-nginx kubernetes.io/metadata.name=ingress-nginx --overwrite

# ==============================================================================
# 4. פריסת קבצי האפליקציה לקוברנטיס
# ==============================================================================
echo "📝 [4/6] Applying Kubernetes manifests..."
cd K8S

# === הגדרת סיסמת גישה (Basic Auth) ===
# מה הבלוק עושה: מגריל סיסמה של 16 תווים ויוצר ממנה קובץ הרשאות כדי לחסום את האתר.
GENERATED_PASSWORD=$(openssl rand -hex 8)
htpasswd -bc /tmp/auth admin "$GENERATED_PASSWORD"
kubectl create secret generic basic-auth --from-file=auth=/tmp/auth -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
rm -f /tmp/auth

# === הפעלת קבצי התצורה (Manifests) ===
if [ -f "external-secrets.yaml" ]; then kubectl apply -f external-secrets.yaml; sleep 5; fi
if [ -f "network-policies.yaml" ]; then kubectl apply -f network-policies.yaml; fi
kubectl apply -f backend/
kubectl apply -f worker/
kubectl apply -f frontend/
cd ..

# ==============================================================================
# 5. עדכון הפודים לגרסה החדשה
# ==============================================================================
echo "🔄 [5/6] Updating Deployments to use specific image tags ($GIT_SHA)..."
# מה הבלוק עושה: מורה לקוברנטיס למשוך את האימג'ים מהענן עם התגית הספציפית שמתאימה לקוד הנוכחי.
# למה צריך את זה: כדי להבטיח שהאפליקציה משתמשת בגרסה המעודכנת ביותר שנבנתה.
kubectl set image deployment/frontend frontend=$ECR_URL/mission-frontend:$GIT_SHA -n $NAMESPACE
kubectl set image deployment/backend backend=$ECR_URL/mission-backend:$GIT_SHA -n $NAMESPACE
kubectl set image deployment/backend init-home=$ECR_URL/mission-backend:$GIT_SHA -n $NAMESPACE
kubectl set image deployment/worker worker=$ECR_URL/mission-worker:$GIT_SHA -n $NAMESPACE

# ==============================================================================
# 6. תיקוני אבטחה ותקשורת שקופים
# ==============================================================================
echo "🔧 [6/6] Applying permanent security and routing patches..."
# מה הבלוק עושה: מתקן הרשאות קבצים
# (Non-Root)
# ומזריק את ה-
# IAM Roles
# לתוך ה-Service Accounts.
kubectl patch deployment backend -n $NAMESPACE -p '{"spec":{"template":{"spec":{"securityContext":{"fsGroup":1000, "runAsUser":1000}}}}}'
kubectl patch service frontend-service -n $NAMESPACE --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8080}]'

if [ -n "$BACKEND_ROLE_ARN" ] && [ -n "$WORKER_ROLE_ARN" ]; then
    kubectl annotate serviceaccount backend-sa -n $NAMESPACE eks.amazonaws.com/role-arn=$BACKEND_ROLE_ARN --overwrite
    kubectl annotate serviceaccount worker-sa -n $NAMESPACE eks.amazonaws.com/role-arn=$WORKER_ROLE_ARN --overwrite
fi

# ==============================================================================
# תצוגה סופית
# ==============================================================================
echo ""
echo "=================================================================================="
echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
echo "=================================================================================="
echo "🌐 URL                   : https://$LB_HOSTNAME"
echo "👤 Frontend Username     : admin"
echo "🔑 Frontend Password     : $GENERATED_PASSWORD"
echo "=================================================================================="