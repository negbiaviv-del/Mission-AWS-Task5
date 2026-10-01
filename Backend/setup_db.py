# ==============================================================================
# 1. משיכת הגדרות סביבה והכנות
# מה הבלוק עושה: טוען את פרטי ההתחברות למסד הנתונים מתוך הסודות של קוברנטיס.
# למה צריך את זה: כדי לדעת לאן להתחבר מבלי לכתוב סיסמאות בקוד
# (Hardcoding).
# ==============================================================================
import os
import sys
import psycopg2

# משיכת פרטי החיבור ממשתני סביבה
DB_HOST = os.getenv("DB_HOST")
DB_NAME = os.getenv("DB_NAME", "postgres")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD")

def setup_database():
    if not DB_PASSWORD:
        print("[-] ERROR: DB_PASSWORD environment variable is missing!")
        sys.exit(1)

    conn = None
    cur = None
    try:
# ==============================================================================
# 2. התחברות ויצירת סכמת הטבלה (Schema Definition)
# מה הבלוק עושה: פותח חיבור מאובטח ל-
# RDS,
# מוודא שהטבלה קיימת, ומעדכן עמודות אם צריך.
# למה צריך את זה: טרפורם מקים
# DB
# ריק. בלוק זה הוא ה"קבלן" שבונה את מבנה הנתונים הנדרש כדי ש-
# app.py
# יוכל לעבוד מולו מבלי לקרוס.
# ==============================================================================
        # התחברות מאובטחת
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            sslmode='require'
        )
        cur = conn.cursor()

        # 1. יצירת הטבלה (בפעם הראשונה)
        cur.execute("""
            CREATE TABLE IF NOT EXISTS mission_data (
                id SERIAL PRIMARY KEY,
                name VARCHAR(255),
                status TEXT
            );
        """)

        # 2. אוטומציה: תיקון מבנה (Migration)
        cur.execute("ALTER TABLE mission_data ALTER COLUMN status TYPE TEXT;")
        conn.commit()
        print("Database schema verified and set to TEXT.")

# ==============================================================================
# 3. הזרקת נתוני התחלה (Data Seeding)
# מה הבלוק עושה: בודק אם הטבלה ריקה, ואם כן, מכניס 3 רשומות ראשוניות של שירותי תשתית.
# למה צריך את זה: כדי לוודא שמסד הנתונים מתפקד כראוי ומקבל נתונים בהקמה.
#רשומות אלו מסוננות ב-
# app.py
# ולא מוצגות ללקוח.
# ==============================================================================
        # 3. הכנסת נתונים ראשוניים
        cur.execute("SELECT COUNT(*) FROM mission_data;")
        if cur.fetchone()[0] == 0:
            cur.execute("""
                INSERT INTO mission_data (name, status)
                VALUES
                ('Frontend Server', 'Operational'),
                ('Backend Server', 'Connected'),
                ('RDS Database', 'Synced');
            """)
            conn.commit()
            print("Initial data inserted.")
        else:
            print("Table already has data, skipping insertion.")

        print("Database initialized successfully!")

# ==============================================================================
# 4. טיפול בשגיאות סיום חיבור (Error Handling & Teardown)
# מה הבלוק עושה: תופס שגיאות חיבור ומסיים את פעולת הסקריפט, ולבסוף סוגר את החיבור למסד הנתונים.
# למה צריך את זה: אם משהו נכשל, פקודת
# sys.exit(1)
# דואגת שהקונטיינר יקרוס בצורה רועשת כדי שקוברנטיס יזהה את התקלה וינסה להפעיל אותו מחדש, ולא ימשיך להריץ את השרת על בסיס נתונים פגום.
# ==============================================================================
    except psycopg2.Error as e:
        print(f"[-] Database error: {e}")
        sys.exit(1)  # קריסה רועשת כדי שקוברנטיס יזהה את התקלה
    except Exception as e:
        print(f"[-] Unexpected error: {e}")
        sys.exit(1)  # קריסה רועשת
    finally:
        if cur: cur.close()
        if conn: conn.close()

if __name__ == "__main__":
    setup_database()