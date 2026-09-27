import os
import psycopg2
from pathlib import Path

def test_connection():
    # Load .env
    env_file = Path(".env")
    if env_file.exists():
        with open(env_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ[k.strip()] = v.strip().strip("'\"")

    host = os.environ.get("PGHOST", "localhost")
    port = os.environ.get("PGPORT", "5432")
    dbname = os.environ.get("PGDATABASE", "postgres")
    user = os.environ.get("PGUSER", "postgres")
    password = os.environ.get("PGPASSWORD", "")

    print(f"Testing connection to PostgreSQL...")
    print(f"Host: {host}:{port}, Database: {dbname}, User: {user}")

    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            dbname=dbname,
            user=user,
            password=password
        )
        with conn.cursor() as cur:
            cur.execute("SELECT version();")
            ver = cur.fetchone()[0]
            print("\n[SUCCESS] Connected to PostgreSQL successfully!")
            print(f"PostgreSQL Version: {ver}")

            # Check existing tables
            cur.execute("""
                SELECT table_name 
                FROM information_schema.tables 
                WHERE table_schema = 'public';
            """)
            tables = [t[0] for t in cur.fetchall()]
            print(f"Public Tables in '{dbname}': {tables if tables else 'No tables created yet.'}")
        conn.close()
    except Exception as e:
        print(f"\n[ERROR] Connection failed: {e}")
        print("Please check your password and database name in .env")

if __name__ == "__main__":
    test_connection()
