# שימוש בתמונה רשמית המוגדרת לעבוד בטוח בקוברנטיס (פורט 8080, ללא הרשאות Root)
FROM nginxinc/nginx-unprivileged:alpine

# דריסת דף הפתיחה של Nginx עם ההגדרות לשרת ה-Backend שלנו
COPY flask.conf /etc/nginx/conf.d/default.conf 