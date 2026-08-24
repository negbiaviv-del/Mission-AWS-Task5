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