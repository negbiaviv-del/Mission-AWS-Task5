import boto3
import os

# --- הגדרות נמשכות דינמית ממשתני הסביבה של קוברנטיס ---
BUCKET_NAME = os.getenv("S3_BUCKET")
TOPIC_ARN = os.getenv("SNS_TOPIC_ARN")
REGION = os.getenv("AWS_REGION", "us-east-1")

# שימוש ב-Session כדי להבטיח עבודה נכונה עם ה-IAM Role (IRSA)
session = boto3.Session(region_name=REGION)
s3 = session.client('s3')
sns = session.client('sns')

def upload_and_notify(file_path):
    if not os.path.exists(file_path):
        print(f"❌ Error: The file {file_path} does not exist.")
        return

    # וידוא שמשתני הסביבה אכן קיימים לפני ביצוע פעולות
    if not BUCKET_NAME or not TOPIC_ARN:
        print("❌ Error: Missing S3_BUCKET or SNS_TOPIC_ARN in environment variables.")
        return

    file_name = os.path.basename(file_path)
    
    try:
        # 1. העלאה ל-S3
        print(f"⏳ Uploading {file_name} to S3 bucket: {BUCKET_NAME}...")
        s3.upload_file(file_path, BUCKET_NAME, file_name)
        print(f"✅ Successfully uploaded to {BUCKET_NAME}")

        # 2. שליחת הודעה מעוצבת ונקייה ל-SNS
        friendly_message = f"""
🚀 Mission Alert: New Log Uploaded!
----------------------------------
Hello Aviv,

A new log file has been processed successfully:
📄 File: {file_name}
📦 Bucket: {BUCKET_NAME}
✅ Status: Success

The system is running smoothly via Kubernetes.
----------------------------------
        """
        
        print(f"⏳ Sending clean notification to SNS topic: {TOPIC_ARN}...")
        sns.publish(
            TopicArn=TOPIC_ARN,
            Message=friendly_message,
            Subject=f"Log Upload Success: {file_name}"
        )
        print("🎉 Success! Clean notification sent to your email.")

    except Exception as e:
        print(f"❌ Unexpected Error: {e}")

if __name__ == "__main__":
    # יצירת קובץ זמני גנרי לבדיקה (מותאם לקונטיינר במקום שרת EC2)
    test_file = "/tmp/kubernetes_test.log"
    with open(test_file, "w") as f:
        f.write("Kubernetes automated test log content.")
    
    upload_and_notify(test_file)