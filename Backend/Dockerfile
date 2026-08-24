FROM python:3.11-slim

# 1. יצירת משתמש וקבוצה Non-Root (פותר את הערת האבטחה של אביעד!)
RUN groupadd -r appuser && useradd -r -g appuser -m -d /home/appuser appuser

WORKDIR /app

# 2. העתקה והתקנה של דרישות הפרויקט
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && pip install gunicorn

# 3. העתקת שאר קבצי הפרויקט
COPY . .

# 4. העתקת סקריפט ההפעלה ומתן הרשאות ביצוע
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 5. העברת הבעלות על תיקיית האפליקציה למשתמש החדש שלנו
RUN chown -R appuser:appuser /app /entrypoint.sh

# 6. מעבר למשתמש ה-Non-Root
USER appuser
ENV HOME=/home/appuser

EXPOSE 5000

ENTRYPOINT ["/entrypoint.sh"]

# 7. הפעלה נכונה של Gunicorn עם הגדרת תיקייה זמנית חוקית
CMD ["gunicorn", "--worker-tmp-dir", "/dev/shm", "--bind", "0.0.0.0:5000", "app:app"]