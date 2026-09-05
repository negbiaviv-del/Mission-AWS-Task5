#!/bin/bash
set -e

REGION="us-east-1"
ACCOUNT="544471418394"
ECR_URL="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
NAMESPACE="devops-app"

# === 1. התחברות ל-ECR ===
# מתחבר לשירות האחסון של אמזון (ECR) כדי שנוכל לדחוף אליו את האימג'ים (תמונות דוקר) שנבנה.
echo "🔐 [1/7] Logging into AWS ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_URL

# === 2. הגדרת סביבת הבנייה של Docker ===
# מכין את Docker Buildx, כלי שמאפשר לנו לבנות אימג'ים מתקדמים מהר יותר וביעילות.
echo "🛠️ [2/7] Initializing Docker Buildx..."
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes > /dev/null 2>&1 || true
docker buildx create --use --name multiarch-builder 2>/dev/null || docker buildx use multiarch-builder

# === 3. בניית אימג'ים ודחיפה לענן ===
# לוקח את המזהה הייחודי של הגיט (Git SHA) ומשתמש בו כתגית.
# בונה את האימג'ים של שלושת השירותים שלנו (Frontend, Backend, Worker) ודוחף אותם ל-AWS ECR.
echo "🏗️ [3/7] Building and pushing Docker images to ECR..."
GIT_SHA=$(git rev-parse --short HEAD)
echo "Using Git SHA: $GIT_SHA for image tagging"

SERVICES=("mission-frontend" "mission-backend" "mission-worker")
DIRS=("./Frontend" "./Backend" "./Worker")

for i in "${!SERVICES[@]}"; do
    SERVICE="${SERVICES[$i]}"
    DIR="${DIRS[$i]}"

    echo "Building $SERVICE..."
    docker buildx build --platform linux/amd64 --no-cache -t $ECR_URL/$SERVICE:$GIT_SHA --push $DIR
done

# === 4. חיבור לקלאסטר הקוברנטיס ===
# שולף מ-Terraform את השם של הקלאסטר ב-AWS ואת הרשאות ה-IAM (התפקידים), ואז מחבר את הטרמינל שלנו לקלאסטר הזה כדי שנוכל להריץ פקודות kubectl.
echo "☸️ [4/7] Updating local kubeconfig and fetching IAM Roles..."
cd Terraform
CLUSTER_NAME=$(terraform output -raw configure_kubectl | awk -F'--name ' '{print $2}')
BACKEND_ROLE_ARN=$(terraform output -raw backend_iam_role_arn)
WORKER_ROLE_ARN=$(terraform output -raw worker_iam_role_arn)
cd ..

aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# === 5. איתור כתובת האתר (Load Balancer) ===
# בודק מול קוברנטיס מה כתובת ה-DNS (כתובת הגישה) של האתר שלנו שהוקצה על ידי AWS. מחכה בלולאה עד ש-AWS מנפיק את הכתובת.
echo "🌐 [5/7] Fetching dynamic AWS Load Balancer DNS..."
LB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

while [ -z "$LB_HOSTNAME" ]; do
    echo "⏳ Waiting for AWS to assign Load Balancer DNS..."
    sleep 5
    LB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
done
echo "✅ Load Balancer DNS is ready: $LB_HOSTNAME"

# === 6. יצירת סביבה (Namespace) והגדרות אבטחה ===
# יוצר את סביבת devops-app בקוברנטיס. מייצר תעודת הצפנה (TLS) זמנית כדי שהאתר יעבוד ב-HTTPS, ומתייג את ה-Namespace של Nginx כדי שחוקי הרשת יעבדו נכון.
echo "🔒 [6/7] Managing Kubernetes Namespaces, Local Secrets & TLS..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "⚙️ Generating Self-Signed TLS Certificate..."
kubectl delete secret mission-tls -n $NAMESPACE --ignore-not-found 2>/dev/null || true
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /tmp/tls.key -out /tmp/tls.crt -subj "/CN=mission-app" 2>/dev/null
kubectl create secret tls mission-tls --key /tmp/tls.key --cert /tmp/tls.crt -n $NAMESPACE
rm -f /tmp/tls.key /tmp/tls.crt

echo "🏷️ [Auto-Fix] Ensuring ingress-nginx namespace has the correct labels for NetworkPolicies..."
kubectl label namespace ingress-nginx kubernetes.io/metadata.name=ingress-nginx --overwrite

# === 7. פריסת קבצי האפליקציה לקוברנטיס ===
# מייצר סיסמה אקראית לכניסה לאתר ויוצר עבורה סיקרט. מגדיר את ה-Ingress כך שינתב תנועה ל-Frontend. פורס את שאר קבצי ה-YAML (Backend, Worker וכו').
echo "📝 [7/7] Applying Kubernetes manifests..."
cd K8S

GENERATED_PASSWORD=$(openssl rand -hex 8)
htpasswd -bc /tmp/auth admin "$GENERATED_PASSWORD"
kubectl create secret generic basic-auth --from-file=auth=/tmp/auth -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
rm -f /tmp/auth

cat <<EOF > frontend/ingress.yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: devops-app
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth
    nginx.ingress.kubernetes.io/auth-realm: "Authentication Required"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - $LB_HOSTNAME
      secretName: mission-tls
  rules:
    - host: $LB_HOSTNAME
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port:
                  number: 8080
EOF

echo "🛡️ [Auto-Fix] Ensuring External Secrets Operator is installed via Helm..."
helm repo add external-secrets https://charts.external-secrets.io > /dev/null 2>&1 || true
helm upgrade --install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace --set installCRDs=true > /dev/null 2>&1 || true

echo "⏳ Waiting for External Secrets Webhook to be fully ready..."
kubectl rollout status deployment/external-secrets-webhook -n external-secrets --timeout=120s
sleep 5

if [ -f "external-secrets.yaml" ]; then
    kubectl apply -f external-secrets.yaml
    sleep 5
fi

if [ -f "network-policies.yaml" ]; then
    kubectl apply -f network-policies.yaml
fi

kubectl apply -f backend/
kubectl apply -f worker/
kubectl apply -f frontend/
cd ..

# === 8. עדכון הפודים לגרסה החדשה ===
# מעדכן את הפודים שימשכו מה-ECR בדיוק את תמונות הדוקר (האימג'ים) שבנינו בתחילת הסקריפט (לפי ה-Git SHA).
echo "🔄 Updating Deployments to use specific image tags ($GIT_SHA)..."
kubectl set image deployment/frontend frontend=$ECR_URL/mission-frontend:$GIT_SHA -n $NAMESPACE
kubectl set image deployment/backend backend=$ECR_URL/mission-backend:$GIT_SHA -n $NAMESPACE
kubectl set image deployment/backend init-home=$ECR_URL/mission-backend:$GIT_SHA -n $NAMESPACE
kubectl set image deployment/worker worker=$ECR_URL/mission-worker:$GIT_SHA -n $NAMESPACE

# === 9. תיקוני אבטחה ותקשורת שקופים ===
# מעדכן הרשאות קבצים ל-Backend (כדי שלא ירוץ כ-Root) ומתקן בעיות ניתוב בין ה-Service ל-Frontend. מכניס לפודים את הרשאות ה-IAM לגישה לשירותי AWS כמו S3/SQS.
echo "🔧 [Auto-Fix] Applying permanent security and routing patches..."

kubectl patch deployment backend -n $NAMESPACE -p '{"spec":{"template":{"spec":{"securityContext":{"fsGroup":1000, "runAsUser":1000}}}}}'
kubectl patch service frontend-service -n $NAMESPACE --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8080}]'
kubectl patch networkpolicy allow-ingress-to-frontend -n $NAMESPACE --type='json' -p='[{"op": "replace", "path": "/spec/ingress/0/ports/0/port", "value": 8080}]' 2>/dev/null || true

if [ -n "$BACKEND_ROLE_ARN" ] && [ -n "$WORKER_ROLE_ARN" ]; then
    echo "Injecting IAM Role ARN for Backend: $BACKEND_ROLE_ARN"
    kubectl annotate serviceaccount backend-sa -n $NAMESPACE eks.amazonaws.com/role-arn=$BACKEND_ROLE_ARN --overwrite

    echo "Injecting IAM Role ARN for Worker: $WORKER_ROLE_ARN"
    kubectl annotate serviceaccount worker-sa -n $NAMESPACE eks.amazonaws.com/role-arn=$WORKER_ROLE_ARN --overwrite
fi

# === 10. הפעלת מחדש ואתחול מסד נתונים ===
# מכבה ומדליק את הפודים בצורה מסודרת כדי שההגדרות ייכנסו לתוקף. לבסוף, מריץ סקריפט מתוך ה-Backend כדי לייצר טבלאות במסד הנתונים (PostgreSQL). מציג את הכתובת והסיסמה בסוף.
echo "🔄 Performing a rollout restart to apply new configurations cleanly..."
kubectl rollout restart deployment -n $NAMESPACE

echo "⏳ Giving Pods 15 seconds to start before running DB initialization..."
sleep 15

echo "🗄️ Automatically Initializing the Database (Running setup_db.py)..."
BACKEND_POD=$(kubectl get pods -n $NAMESPACE -l app=backend -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NAMESPACE $BACKEND_POD -- python setup_db.py || echo "⚠️ DB initialization encountered an issue (it might already be set up)."

echo "⏳ Waiting for Backend Pods to become Ready..."
kubectl rollout status deployment/backend -n $NAMESPACE --timeout=90s

echo ""
echo "=================================================================================="
echo "🎉 AUTOMATION COMPLETED SUCCESSFULLY! APP IS EXPOSED"
echo "=================================================================================="
echo "🌐 URL      : https://$LB_HOSTNAME"
echo "👤 Username : admin"
echo "🔑 Password : $GENERATED_PASSWORD"
echo "=================================================================================="