#!/bin/bash
# ==============================================================================
# 1. ניקוי קוברנטיס (Kubernetes Teardown)
# ==============================================================================
echo "⚠️ WARNING: Starting Full Project Teardown (One-Touch)..."

echo "🧹 Phase 1: Deleting Kubernetes Resources (Clearing ALBs, ELBs & EBS)"
# מחיקת סביבת האפליקציה.
#  --ignore-not-found אומר שאם זה כבר נמחק אל תציג שגיאה
kubectl delete namespace devops-app --ignore-not-found=true
# מחיקת ההתקנה של ג'נקינס (helm uninstall).
# || true מוודא שהסקריפט ימשיך גם אם ג'נקינס לא מותקן
helm uninstall jenkins -n jenkins 2>/dev/null || true
kubectl delete namespace jenkins --ignore-not-found=true
# מחיקת מערכת הניטור
helm uninstall kube-prometheus-stack -n observability 2>/dev/null || true
kubectl delete namespace observability --ignore-not-found=true

# ==============================================================================
# 2. ריקון רג'יסטרי (ECR Cleanup)
# ==============================================================================
echo "🗑️ Phase 2: Cleaning ECR Repositories (Inline Execution)"
REGION="us-east-1"
REPOS=("mission-frontend" "mission-backend" "mission-worker")

# לולאה שעוברת על כל אחד מ-3 הריפוזטוריס שלנו
for REPO in "${REPOS[@]}"; do
    echo "   Emptying repository: $REPO..."
    # שימוש ב-AWS CLI
    # כדי לשלוף את רשימת כל תעודות הזהות (IDs)
    # של האימג'ים לקובץ
    # JSON זמני
    aws ecr list-images --repository-name $REPO --region $REGION --query 'imageIds[*]' --output json 2>/dev/null > /tmp/images_$REPO.json || true

    # בדיקה: אם הקובץ לא ריק ויש בתוכו אימג'ים
    if [ -s /tmp/images_$REPO.json ] && [ "$(cat /tmp/images_$REPO.json)" != "null" ] && [ "$(cat /tmp/images_$REPO.json)" != "[]" ]; then
        # פקודת מחיקה מרוכזת (batch)
        # ב-AWS
        # שמוחקת את כל האימג'ים יחד לפי הרשימה
        aws ecr batch-delete-image --repository-name $REPO --region $REGION --image-ids file:///tmp/images_$REPO.json > /dev/null 2>&1 || true
    fi
    # מחיקת הקובץ הזמני
    rm -f /tmp/images_$REPO.json
done

# ==============================================================================
# 3. מחיקת תשתיות מלאה (AWS Infrastructure Destroy)
# ==============================================================================
echo "⏳ Waiting 120 seconds for AWS to completely terminate all Load Balancers..."
# המתנה חובה כדי לתת ל-
# AWS
# לסיים לפרק את הנתבים ברקע. בלעדיה
# Terraform יקרוס ויטען שהרשת בשימוש.
sleep 120

echo "🔥 Phase 3: Destroying AWS Infrastructure (Terraform)"
cd Terraform
# מחיקת התשתית הפיזית/ענן של השרתים והרשת
terraform destroy -auto-approve
cd ..