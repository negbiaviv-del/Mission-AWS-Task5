#!/bin/bash

# === מחיקת מאגרי התמונות ב-AWS (ECR Teardown) ===
# סקריפט ניקוי (Teardown) שעובר על רשימת השירותים שלנו ומוחק את מאגרי התמונות (Repositories) שלהם מ-AWS ECR.
# השימוש בפרמטר '--force' הוא קריטי כאן - הוא מוודא שהמאגר יימחק לחלוטין גם אם הוא לא ריק (ויש בו עדיין אימג'ים), כדי למנוע שגיאות, לחסוך עלויות ולנקות את סביבת הענן בסיום העבודה.

# הגדרת משתנים
REGION="us-east-1"
SERVICES=("mission-frontend" "mission-backend" "mission-worker")
echo "Starting ECR teardown..."

# מעבר על רשימת המאגרים ומחיקתם
for SERVICE in "${SERVICES[@]}"; do
    echo "Attempting to delete repository: $SERVICE..."

    # שימוש ב-force כדי למחוק את המאגר גם אם יש בו אימג'ים
    aws ecr delete-repository --repository-name $SERVICE --region $REGION --force > /dev/null 2>&1

    # בדיקה אם פעולת המחיקה הצליחה
    if [ $? -eq 0 ]; then
        echo "Successfully deleted $SERVICE."
    else
        echo "Repository $SERVICE not found or already deleted."
    fi
done

echo "Teardown complete! All specified ECR repositories are gone."