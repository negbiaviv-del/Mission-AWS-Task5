#!/bin/bash
set -e

GITHUB_REPO_URL="https://github.com/negbiaviv-del/Mission-AWS-Task5.git"

# ==============================================================================
# 1. שליפת הרשאות גיט מ-
# AWS Secrets Manager
# מה הבלוק עושה: מתחבר לכספת הסודות של
# AWS
# ומושך בצורה מאובטחת את הטוקן של
# GitHub.
# למה צריך את זה: כדי להימנע מפרקטיקה פסולה של
# "Hardcoded Secrets"
# (סיסמאות גלויות בקוד).
# זוהי שכבת אבטחה שמוודאת שהטוקן של גיט לא נחשף לאף אדם או לוג שקורא את הסקריפט.
# ==============================================================================
# 1.1 הדפסת הודעת התחלה למשתמש (UI)
echo "======================================================"
echo "🔐 Fetching GitHub credentials securely from AWS Secrets Manager..."
echo "======================================================"

# 1.2 שליפת הסוד השלם
# (כמחרוזת JSON)
# ישירות מהכספת של אמזון
# (AWS CLI)
SECRET_JSON=$(aws secretsmanager get-secret-value --region us-east-1 --secret-id jenkins-github-auth --query SecretString --output text)

# 1.3 פענוח ה-
# JSON
# בעזרת פייתון וחילוץ ספציפי של שם המשתמש והסיסמה - הטוקן לתוך משתנים
GITHUB_USER=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['username'])")
GITHUB_TOKEN=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['pat'])")

# 1.4 מנגנון בקרת איכות
# (Validation)
# מוודא שהטוקן נשלף בהצלחה ועוצר את הסקריפט אם הוא ריק
if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ Error: Could not fetch GitHub PAT from AWS. Please verify the secret exists in AWS Secrets Manager."
    exit 1
fi
echo "✅ GitHub credentials successfully loaded from AWS!"
echo "======================================================"

# ==============================================================================
# 2. החלת תצורה, הרשאות וניטור
# (Applying Manifests)
# מה הבלוק עושה: מפעיל את קבצי ה-
# YAML
# הקיימים שלך בתיקיית
# jenkins
# (הרשאות, סביבה וניטור).
# למה צריך את זה: ג'נקינס דורש סביבה מבודדת
# (Namespace)
# והרשאות מערכת מדויקות (RBAC)
# כדי לנהל פודים ומשאבים בקלאסטר. בנוסף, אנחנו פורסים את ה-
# ServiceMonitor
# כדי שפרומיתיאוס יזהה את ג'נקינס אוטומטית
# (Service Discovery).
# ==============================================================================
echo "==> Applying Namespace, RBAC, and ServiceMonitor from existing files..."
kubectl apply -f jenkins/jenkins-namespace.yaml
kubectl apply -f jenkins/jenkins-rbac.yaml
kubectl apply -f jenkins/jenkins-monitor.yaml

# מגדיר את כונן ה-
# gp2
# של אמזון כברירת המחדל לאחסון בקלאסטר, כדי לאפשר לג'נקינס להקצות לעצמו שטח אחסון פיזי באופן אוטומטי.
echo "==> Automating StorageClass Configuration..."
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || echo "StorageClass gp2 patch failed or already set."

# מוחק לחלוטין כל שאריות של התקנת ג'נקינס קודמת הגדרות, שירותים ואחסון, כדי להבטיח שההתקנה הנוכחית תתחיל מדף חלק וללא התנגשויות.
echo "==> Cleaning up previous installation..."
helm uninstall jenkins -n jenkins --ignore-not-found --wait
kubectl delete statefulset jenkins -n jenkins --ignore-not-found
kubectl delete pvc jenkins -n jenkins --ignore-not-found
kubectl delete svc jenkins -n jenkins --ignore-not-found

# ==============================================================================
# 3. הזרקת סודות לקוברנטיס
# (Kubernetes Secrets)
# מה הבלוק עושה: לוקח את הרשאות ה-
# AWS של הטרמינל שלך ואת הרשאות ה-
# Git שמשכנו, ושומר אותם כ-
# Secrets בקלאסטר.
# למה צריך את זה: כדי שג'נקינס שיושב בתוך הפוד) יוכל לתקשר עם העולם החיצון (למשוך קוד
# מגיט ולהעלות אימג'ים ל-
# ECR,
# הוא חייב גישה מאובטחת לזהויות האלו מתוך הקלאסטר עצמו.
# ==============================================================================
# שואב את הרשאות הגישה של
# AWS
# המוגדרות במחשב המקומי
# (באמצעות ה-AWS CLI)
# ושומר אותן במשתנים בסקריפט.
echo "==> Fetching AWS Credentials from local environment..."
AWS_ACCESS_KEY=$(aws configure get aws_access_key_id)
AWS_SECRET_KEY=$(aws configure get aws_secret_access_key)

# מזריק את הרשאות ה-
# AWS
# לתוך קוברנטיס כאובייקט
# Secret
# מאובטח ב-
# Namespace
# של ג'נקינס, כדי שיוכל לדחוף אימג'ים ל-
#ECR.
echo "==> Creating Kubernetes Secrets for AWS and GitHub..."
kubectl create secret generic aws-credentials-secret \
  --namespace jenkins \
  --from-literal=aws_access_key_id="$AWS_ACCESS_KEY" \
  --from-literal=aws_secret_access_key="$AWS_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# מזריק את הרשאות ה-
# GitHub
# (ששלפנו קודם לכן) כ-
# Secret
# מאובטח בקוברנטיס, כדי שג'נקינס יוכל למשוך את קוד הפרויקט מגיט.
kubectl create secret generic github-credentials-secret \
  --namespace jenkins \
  --from-literal=github_username="$GITHUB_USER" \
  --from-literal=github_token="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# ==============================================================================
# 4. התקנת ג'נקינס בעזרת
# Helm (Configuration as Code)
# מה הבלוק עושה: מתקין את ג'נקינס דרך מנהל החבילות וממתין לקבלת
# DNS
# חיצוני מאמזון.
# למה צריך את זה: אנו משתמשים בגישת
# JCasC
# (דרך קובץ ה-
#values.yaml הקיים שלך).
# זה מאפשר לנו להתקין ג'נקינס שמגיע מראש עם כל הפלאגינים וה-
# Pipelines
# מוכנים לעבודה,
# ללא צורך בהגדרות ידניות דרך ממשק המשתמש (UI).
# ==============================================================================
# מוסיף ומעדכן את מאגר החבילות הרשמי של ג'נקינס
# (Helm Repo)
# למחשב המקומי כדי שנוכל להוריד ממנו את ההתקנה.
echo "==> Installing Jenkins via Helm..."
helm repo add jenkinsci https://charts.jenkins.io || true
helm repo update

# מבצע את ההתקנה של ג'נקינס בפועל בעזרת מנהל החבילות
# Helm,
# תוך דריסת הגדרות ברירת המחדל עם קובץ ה-
# values המותאם שלנו.
helm upgrade --install jenkins jenkinsci/jenkins \
  -n jenkins \
  -f jenkins/jenkins-values.yaml

# מדפיס למשתמש הודעת חיווי על כך שפקודת ההתקנה נשלחה בהצלחה לקלאסטר והתהליך החל.
echo "======================================================"
echo "Jenkins installation initiated successfully!"
echo "======================================================"

# ממתין באופן אקטיבי (עד 5 דקות) עד שקוברנטיס יסיים להקים את הפודים של ג'נקינס והם ידווחו על סטטוס "מוכן לעבודה" (Ready).
echo "⏳ Waiting for Jenkins Pods to be Ready (this can take 3-4 minutes)..."
kubectl rollout status statefulset/jenkins -n jenkins --timeout=300s

# מריץ לולאת המתנה שבודקת כל 5 שניות אם אמזון כבר סיימה להקצות כתובת אינטרנט ציבורית
# (Load Balancer)
#  לשרת הג'נקינס.
echo "⏳ Waiting for AWS to assign a public DNS for Jenkins..."
JENKINS_URL=""
while [ -z "$JENKINS_URL" ]; do
    sleep 5
    JENKINS_URL=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
done

# חודר לתוך הפוד של ג'נקינס בקלאסטר כדי לקרוא את קובץ סיסמת מנהל המערכת ההתחלתית, ושומר אותה במשתנה מקומי.
echo "🔑 Extracting Jenkins Admin Password..."
JENKINS_PASSWORD=$(kubectl exec --namespace jenkins -it svc/jenkins -c jenkins -- /bin/cat /run/secrets/additional/chart-admin-password | tr -d '\r')
# ==============================================================================
# 5. הגדרת
# Webhook
# אוטומטי מול
# GitHub
# מה הבלוק עושה: משתמש ב-
# API
#של גיט כדי להגדיר
# Webhook
# שמצביע לכתובת החדשה של ג'נקינס.
# למה צריך את זה: זהו המנוע של ה-
# CI/CD.
# ה-Webhook
# אומר לגיט: "בכל פעם שמפתח
# דוחף קוד חדש למאגר
# (Push),
#  תשלח מיד בקשת רשת ל-
# URL
# הזה כדי שג'נקינס יתחיל בילד אוטומטית".
# ==============================================================================
# שולח בקשת API
# מאובטחת לשרתים של
# GitHub
# כדי ליצור
# Webhook
# אוטומטי, שיורה לגיט להודיע לג'נקינס על כל דחיפת קוד חדשה
# (Push)
# ולהזניק תהליך אוטומציה.
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

# מדפיס למסך סיכום סופי וידידותי למשתמש הכולל את כתובת הגישה החיצונית, שם המשתמש והסיסמה שחולצה, כדי לאפשר כניסה מיידית למערכת.
echo ""
echo "======================================================"
echo "🚀 JENKINS IS SUCCESSFULLY INSTALLED AND EXPOSED!"
echo "======================================================"
echo "👤 Username : admin"
echo "🔑 Password : $JENKINS_PASSWORD"
echo "🌐 URL      : http://$JENKINS_URL:8080"
echo "======================================================"

# ==============================================================================
# 6. הפעלת צינור
# (Pipeline)
#  ראשון מרחוק
# (API Trigger)
# מה הבלוק עושה: פונה לממשק ה-
# AP
# של ג'נקינס, חולץ אסימון אבטחה
# (Crumb),
# ומזניק ריצת
# CI.
# למה צריך את זה: זהו וידוא תקינות
# (End-to-End Test).
# המטרה היא לוודא שלא רק שג'נקינס
# באוויר, אלא שהוא באמת מסוגל למשוך קוד ולבנות את הפרויקט, ללא צורך בהתערבות ידנית ראשונית.
# ==============================================================================
echo ""
echo "===> Triggering the first CI build automatically..."
sleep 10

# יצירת קובץ זמני לשמירת ה-
# Session Cookie
COOKIE_JAR=$(mktemp)

# משיכת ה-
# Crumb
# ושמירת ה-
# Cookie
# באמצעות הסיסמה שחולצה באופן דינמי
CRUMB=$(curl -s -c "$COOKIE_JAR" -u "admin:${JENKINS_PASSWORD}" "http://${JENKINS_URL}:8080/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

# הרצת הג'וב תוך כדי שליחת ה-
# Crumb
# וה-
# Cookie יחד
if [[ "$CRUMB" == Jenkins-Crumb:* ]]; then
    curl -s -X POST -b "$COOKIE_JAR" -u "admin:${JENKINS_PASSWORD}" -H "$CRUMB" "http://${JENKINS_URL}:8080/job/Application%20-%20CI/build"
    echo -e "\n✅ First build triggered successfully! Check the Jenkins UI."
else
    echo -e "\n⚠️ Could not fetch valid Jenkins crumb. Please trigger the first build manually."
fi

# ניקוי הקובץ הזמני
rm -f "$COOKIE_JAR"