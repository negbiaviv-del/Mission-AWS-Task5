#!/bin/bash
# ==============================================================================
# 1. הגדרות בסיס ותשתיות (Setup & Terraform)
# ==============================================================================
# הגדרה לעצירת הסקריפט המיידית אם אחת הפקודות נכשלת
set -e
# הגדרה לעצירת הסקריפט אם פקודה נכשלת בתוך שרשרת פקודות
# (Pipeline של לינוקס)
set -o pipefail

echo "🚀 Starting Full Project Deployment (One-Touch)..."

echo "🛠️ Phase 1: Provisioning AWS Infrastructure (Terraform)"
cd Terraform
# הורדת פלאגינים לטרהפורם
terraform init
# הקמת התשתית ללא דרישת אישור ידני מהמשתמש
terraform apply -auto-approve
cd ..
echo "✅ Infrastructure provisioned successfully."

# ==============================================================================
# 2. פריסת מערכות (Monitoring, App & CI/CD)
# ==============================================================================
echo "📊 Phase 2: Installing Observability Stack (Prometheus & Grafana)"
chmod +x runbooks/install-monitoring.sh
# tee מדפיס למסך וגם שומר את הפלט לתוך קובץ לוג להמשך שימוש
./runbooks/install-monitoring.sh | tee monitoring.log

echo "📈 Phase 2.1: Opening Prometheus Port-Forward"
chmod +x runbooks/open-prometheus.sh
# nohup משאיר את הפקודה לרוץ ברקע גם אם תסגור את חלון הטרמינל. '&' שולח אותה לרקע.
nohup ./runbooks/open-prometheus.sh > /dev/null 2>&1 &

echo "🌐 Phase 3: Deploying 3-Tier Application (Baseline)"
chmod +x runbooks/deploy-app.sh
./runbooks/deploy-app.sh | tee deploy-app.log

echo "⚙️ Phase 4: Bootstrapping Jenkins CI/CD & Triggering Automation"
chmod +x runbooks/install-jenkins.sh
./runbooks/install-jenkins.sh | tee install-jenkins.log

# ==============================================================================
# 3. סיכום וניקוי (Summary & Cleanup)
# ==============================================================================
# ביטול חגורת הבטיחות - אם לא נמצאה סיסמה בלוג, הסקריפט ימשיך כרגיל ולא יקרוס
set +e
set +o pipefail

# חילוץ נתונים:
# grep מחפש את השורה הרלוונטית,
# tail לוקח שורה אחרונה,
# awk לוקח את המילה האחרונה באותה שורה
APP_URL=$(grep "URL" deploy-app.log | tail -n 1 | awk '{print $NF}')
APP_PASS=$(grep "Frontend Password" deploy-app.log | tail -n 1 | awk '{print $NF}')

JENKINS_URL=$(grep "URL" install-jenkins.log | tail -n 1 | awk '{print $NF}')
JENKINS_PASS=$(grep "Password" install-jenkins.log | grep -v "Frontend" | tail -n 1 | awk '{print $NF}')

# חילוץ סיסמת מנהל גרפנה ישירות מתוך הסוד
# (Secret)
# בקוברנטיס ופענוח הקידוד שלה
# (base64)
GRAFANA_PASS=$(kubectl get secret -n observability kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 --decode)
# אם לא מצאנו סיסמה, ניתן ערך ברירת מחדל
if [ -z "$GRAFANA_PASS" ]; then GRAFANA_PASS="prom-operator"; fi

# חילוץ כתובת ה-Load Balancer
# שקוברנטיס נתן לגרפנה
GRAFANA_LB=$(kubectl get svc -n observability kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

echo ""
echo "📊 GRAFANA"
echo "URL:      http://$GRAFANA_LB"
echo "User:     admin"
echo "Password: $GRAFANA_PASS"
echo ""

echo "⚙️ JENKINS"
echo "URL:      $JENKINS_URL"
echo "User:     admin"
echo "Password: $JENKINS_PASS"
echo ""

echo "🌐 APPLICATION (Frontend)"
echo "URL:      $APP_URL"
echo "User:     admin"
echo "Password: $APP_PASS"
echo ""

echo "📈 PROMETHEUS"
echo "URL:      http://localhost:9090"
echo "Note:     Port-forward is already running in the background."
echo "================================================================="

# מחיקת קבצי הלוג הזמניים כדי לא להשאיר סיסמאות חשופות בשרת
rm -f deploy-app.log install-jenkins.log monitoring.log