import boto3
import os
import time
from botocore.exceptions import NoCredentialsError

# הגדרות המערכת
WATCH_DIRECTORY = "/home/ec2-user/logs"
BUCKET_NAME = "new-mission-bucket"
REGION = "us-east-1" # שנה לאזור שלך במידה והוא שונה

def upload_to_s3(file_path, bucket, s3_name):
    s3 = boto3.client('s3')
    try:
        s3.upload_file(file_path, bucket, s3_name)
        print(f"Successfully uploaded {s3_name} to {bucket}")
        return True
    except FileNotFoundError:
        print("The file was not found")
        return False
    except NoCredentialsError:
        print("Credentials not available")
        return False
    except Exception as e:
        print(f"An error occurred: {e}")
        return False

def monitor_and_upload():
    # יצירת התיקייה אם היא לא קיימת
    if not os.path.exists(WATCH_DIRECTORY):
        os.makedirs(WATCH_DIRECTORY)
        print(f"Created directory: {WATCH_DIRECTORY}")

    print(f"Monitoring started on {WATCH_DIRECTORY}...")
    
    # רשימת קבצים שכבר הועלו (כדי לא להעלות שוב ושוב את אותו קובץ)
    uploaded_files = set()

    while True:
        try:
            # סריקת התיקייה
            files = os.listdir(WATCH_DIRECTORY)
            
            for file_name in files:
                if file_name not in uploaded_files:
                    file_path = os.path.join(WATCH_DIRECTORY, file_name)
                    
                    # בדיקה שמדובר בקובץ ולא בתיקייה
                    if os.path.isfile(file_path):
                        success = upload_to_s3(file_path, BUCKET_NAME, file_name)
                        if success:
                            uploaded_files.add(file_name)
            
            # המתנה של 2 שניות בין סריקות
            time.sleep(2)
            
        except Exception as e:
            print(f"Monitor error: {e}")
            time.sleep(5)

if __name__ == "__main__":
    monitor_and_upload()
