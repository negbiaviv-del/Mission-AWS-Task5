#!/bin/bash

echo "=========================================="
echo "Starting installation for Aviv App Backend"
echo "=========================================="

# מעבר לתיקיית האפליקציה בשרת
cd /opt/aviv-app/

# יצירת קובץ אפליקציה בסיסי מבוסס פייתון (Placeholder)
cat << 'EOF' > app.py
import time

def main():
    print("Aviv Backend Service is starting...")
    # כאן בעתיד תשב הלוגיקה של ה-Flask או ה-Workers
    while True:
        time.sleep(60)

if __name__ == "__main__":
    main()
EOF

# מתן הרשאות ריצה לקובץ הפייתון
chmod +x app.py

echo "Installation completed successfully!"