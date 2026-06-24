import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", 5432),
        dbname=os.getenv("DB_NAME", "pl_xg"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
    )

if __name__ == "__main__":
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("SELECT version();")
        print("Connected:", cur.fetchone()[0])
        conn.close()
    except Exception as e:
        print("Connection failed:", e)