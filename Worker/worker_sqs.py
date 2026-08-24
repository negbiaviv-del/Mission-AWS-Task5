import os
import json
import boto3
import time

# שימוש במשתני סביבה במקום ערכים קשיחים (Hardcoded)
QUEUE_URL = os.getenv("SQS_QUEUE_URL")
SNS_TOPIC = os.getenv("SNS_TOPIC_ARN")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# הגדרת הלקוחות של AWS
sqs = boto3.client('sqs', region_name=AWS_REGION)
s3 = boto3.client('s3', region_name=AWS_REGION)
sns = boto3.client('sns', region_name=AWS_REGION)

def start_worker():
    print(f"[*] Worker is active and polling: {QUEUE_URL}")
    while True:
        try:
            # משיכת הודעה מהתור (Long Polling)
            response = sqs.receive_message(
                QueueUrl=QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=10
            )

            if 'Messages' in response:
                for msg in response['Messages']:
                    handle = msg['ReceiptHandle']
                    
                    # 1. פענוח ההודעה (שהיא עכשיו JSON ולא נתיב קובץ)
                    try:
                        body = json.loads(msg['Body'])
                        s3_bucket = body.get('s3_bucket')
                        s3_key = body.get('s3_key')
                        action = body.get('action')
                        
                        print(f"[+] Received task: Action={action}, File={s3_key}")
                        
                        # 2. קריאת הקובץ מ-S3 (מוכיח שהוורקר קיבל את המידע ויודע לגשת אליו)
                        s3_response = s3.get_object(Bucket=s3_bucket, Key=s3_key)
                        file_content = json.loads(s3_response['Body'].read().decode('utf-8'))
                        machine_name = file_content.get('Base_Machine_Name', 'Unknown')
                        
                        # 3. שליחת התראה ל-SNS שהוורקר סיים את תפקידו
                        sns.publish(
                            TopicArn=SNS_TOPIC,
                            Message=f"✅ WORKER SUCCESS: Completed processing infrastructure configuration for '{machine_name}'.\nFile {s3_key} read successfully from S3.",
                            Subject=f"Worker Processing Complete: {machine_name}"
                        )

                        # 4. מחיקת ההודעה מהתור בסיום מוצלח
                        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=handle)
                        print(f"[V] Done! {s3_key} processed and deleted from SQS queue.\n")
                        
                    except json.JSONDecodeError:
                        print(f"[-] Error: Message body is not valid JSON. Body: {msg['Body']}")
                    
        except Exception as e:
            print(f"[-] Error polling or processing: {e}")
            time.sleep(5) # המתנה קצרה במקרה של שגיאת רשת כדי לא להציף בבקשות

if __name__ == "__main__":
    # בדיקת תקינות - מוודא שמשתני הסביבה קיימים לפני הריצה
    if not QUEUE_URL or not SNS_TOPIC:
        print("ERROR: Missing Environment Variables (SQS_QUEUE_URL or SNS_TOPIC_ARN)")
        print("Please export them before running the worker.")
        exit(1)
        
    start_worker()