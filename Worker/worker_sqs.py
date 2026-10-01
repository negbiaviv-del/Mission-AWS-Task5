# ==============================================================================
# 1. ייבוא ספריות והגדרות סביבה (Imports & Configuration)
# מה הבלוק עושה: טוען כלים לעבודה מול
# AWS
# (דרך boto3)
# ומושך את כתובות השירותים מקוברנטיס.
# למה צריך את זה: כדי שהוורקר יידע לאיזה תור להאזין ולאן לשלוח מיילים מבלי לכתוב זאת בטקסט גלוי.
# ==============================================================================
import os
import json
import boto3
import time

QUEUE_URL = os.getenv("SQS_QUEUE_URL")
SNS_TOPIC = os.getenv("SNS_TOPIC_ARN")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# הגדרת הלקוחות של AWS
# (חיבור לתור ההודעות, לאחסון, ולשירות ההתראות)
sqs = boto3.client('sqs', region_name=AWS_REGION)
s3 = boto3.client('s3', region_name=AWS_REGION)
sns = boto3.client('sns', region_name=AWS_REGION)

def start_worker():
    print(f"[*] Worker is active and polling: {QUEUE_URL}")
# ==============================================================================
# 2. לולאת האזנה רציפה (Long Polling Loop)
# מה הבלוק עושה: רץ לנצח ומאזין לתור ההודעות של
# SQS.
# למה צריך את זה: הוורקר צריך להיות זמין 24/7.
# Long Polling של 10 שניות חוסך משאבים ומוריד את עלויות הבקשות מול אמזון.
# ==============================================================================
    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=10
            )

            if 'Messages' in response:
                for msg in response['Messages']:
                    handle = msg['ReceiptHandle']

# ==============================================================================
# 3. פענוח הבקשה ועיבוד נתונים מ-
# S3 (Task Processing)
# מה הבלוק עושה: מתרגם את הודעת ה-
# JSON,
# ניגש ל-
# Bucket
# ב-S3,
# וקורא את קובץ התצורה שהלקוח שמר.
# למה צריך את זה: הוורקר מוכיח את יכולתו לגשת למשאבים מבודדים
# (S3)
# בעזרת הרשאות ה-
# IAM (IRSA)
# שניתנו לו על ידי קוברנטיס.
# ==============================================================================
                    try:
                        body = json.loads(msg['Body'])
                        s3_bucket = body.get('s3_bucket')
                        s3_key = body.get('s3_key')
                        action = body.get('action')

                        print(f"[+] Received task: Action={action}, File={s3_key}")

                        s3_response = s3.get_object(Bucket=s3_bucket, Key=s3_key)
                        file_content = json.loads(s3_response['Body'].read().decode('utf-8'))
                        machine_name = file_content.get('Base_Machine_Name', 'Unknown')

# ==============================================================================
# 4. התראה על הצלחה ומחיקת המשימה (Notification & Cleanup)
# מה הבלוק עושה: שולח מייל סיום דרך
# SNS
# ומוחק את ההודעה מתור ה-
# SQS.
# למה צריך את זה: אם ההודעה לא תימחק מהתור, הוורקר יחשוב שהיא נכשלה ויעבד אותה שוב ושוב. שליחת המייל משלימה את מעגל הדיווח ללקוח.
# ==============================================================================
                        sns.publish(
                            TopicArn=SNS_TOPIC,
                            Message=f"✅ WORKER SUCCESS: Completed processing infrastructure configuration for '{machine_name}'.\nFile {s3_key} read successfully from S3.",
                            Subject=f"Worker Processing Complete: {machine_name}"
                        )

                        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=handle)
                        print(f"[V] Done! {s3_key} processed and deleted from SQS queue.\n")

                    except json.JSONDecodeError:
                        print(f"[-] Error: Message body is not valid JSON. Body: {msg['Body']}")

        except Exception as e:
            print(f"[-] Error polling or processing: {e}")
            time.sleep(5)

# ==============================================================================
# 5. בדיקות מקדימות והפעלת התהליך (Pre-flight Checks & Execution)
# מה הבלוק עושה: לפני תחילת הלולאה, הקוד בודק שכל משתני הסביבה החיוניים אכן קיימים.
# למה צריך את זה: פרקטיקת הגנה. אם ה-
# Deployment
# בקוברנטיס לא הזריק את כתובת התור, התהליך יקרוס מיד בצורה ברורה במקום לייצר שגיאות מסתוריות.
# ==============================================================================
if __name__ == "__main__":
    if not QUEUE_URL or not SNS_TOPIC:
        print("ERROR: Missing Environment Variables (SQS_QUEUE_URL or SNS_TOPIC_ARN)")
        print("Please export them before running the worker.")
        exit(1)

    start_worker()