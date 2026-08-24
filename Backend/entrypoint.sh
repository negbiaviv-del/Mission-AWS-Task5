#!/bin/bash
# 1. הרצת סקריפט האתחול של מסד הנתונים
echo "Initializing Database..."
python3 setup_db.py

# 2. קריאת הפקודה המלאה מה-Dockerfile (עם כל פרמטרי האבטחה)
echo "Starting Application..."
exec "$@"