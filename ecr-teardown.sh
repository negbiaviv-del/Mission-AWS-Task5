#!/bin/bash

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