"""
Swiggy Dataset to PostgreSQL Importer
Loads cleaned Swiggy dataset (swiggy_cleaned.csv) into PostgreSQL database.
"""

import os
import sys
import time
import psycopg2
from pathlib import Path

# Ensure UTF-8 output formatting for terminal
sys.stdout.reconfigure(encoding='utf-8')

def load_env():
    """Loads environment variables from .env file."""
    env_file = Path(".env")
    if env_file.exists():
        with open(env_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ[k.strip()] = v.strip().strip("'\"")

def import_swiggy_data():
    load_env()

    host = os.environ.get("PGHOST", "localhost")
    port = os.environ.get("PGPORT", "5432")
    dbname = os.environ.get("PGDATABASE", "postgres")
    user = os.environ.get("PGUSER", "postgres")
    password = os.environ.get("PGPASSWORD", "")

    csv_path = Path("swiggy_cleaned.csv").resolve()
    if not csv_path.exists():
        print(f"[ERROR] CSV file not found: {csv_path}")
        return

    print("=" * 65)
    print("SWIGGY DATA TO POSTGRESQL IMPORTER")
    print("=" * 65)
    print(f"Connecting to: {dbname} at {host}:{port} as user '{user}'...")

    try:
        conn = psycopg2.connect(
            host=host,
            port=port,
            dbname=dbname,
            user=user,
            password=password
        )
        conn.autocommit = False
        cur = conn.cursor()

        # 1. Create Table
        print("\n[1/4] Creating table 'swiggy_restaurants' (if not exists)...")
        create_table_sql = """
        DROP TABLE IF EXISTS swiggy_restaurants CASCADE;

        CREATE TABLE swiggy_restaurants (
            id SERIAL PRIMARY KEY,
            restaurant_name TEXT NOT NULL,
            location VARCHAR(150) NOT NULL,
            area VARCHAR(150) NOT NULL,
            cuisine TEXT NOT NULL,
            primary_cuisine VARCHAR(100) NOT NULL,
            cuisine_count INT NOT NULL,
            rating NUMERIC(3, 1),
            rating_status VARCHAR(50) NOT NULL,
            rating_count DOUBLE PRECISION,
            cost_for_two INT NOT NULL,
            is_pure_veg BOOLEAN NOT NULL,
            offer_count INT NOT NULL,
            offer_name TEXT NOT NULL
        );
        """
        cur.execute(create_table_sql)
        conn.commit()
        print("      Table created successfully.")

        # 2. Bulk Copy Data
        print(f"\n[2/4] Bulk copying records from {csv_path.name}...")
        start_time = time.time()
        
        copy_sql = """
        COPY swiggy_restaurants (
            restaurant_name,
            location,
            area,
            cuisine,
            primary_cuisine,
            cuisine_count,
            rating,
            rating_status,
            rating_count,
            cost_for_two,
            is_pure_veg,
            offer_count,
            offer_name
        ) FROM STDIN WITH (FORMAT csv, HEADER true, ENCODING 'utf-8');
        """
        with open(csv_path, "r", encoding="utf-8") as f:
            cur.copy_expert(copy_sql, f)
        
        conn.commit()
        elapsed = time.time() - start_time
        print(f"      Data imported successfully in {elapsed:.2f} seconds.")

        # 3. Create Indexes for High Performance Analytics
        print("\n[3/4] Creating indexes on high-frequency query columns...")
        cur.execute("""
            CREATE INDEX idx_swiggy_location ON swiggy_restaurants (location);
            CREATE INDEX idx_swiggy_primary_cuisine ON swiggy_restaurants (primary_cuisine);
            CREATE INDEX idx_swiggy_rating ON swiggy_restaurants (rating);
            CREATE INDEX idx_swiggy_cost ON swiggy_restaurants (cost_for_two);
            CREATE INDEX idx_swiggy_veg ON swiggy_restaurants (is_pure_veg);
        """)
        conn.commit()
        print("      Indexes created: location, primary_cuisine, rating, cost_for_two, is_pure_veg.")

        # 4. Verify & Validate
        print("\n[4/4] Verifying imported data...")
        cur.execute("SELECT COUNT(*) FROM swiggy_restaurants;")
        total_rows = cur.fetchone()[0]
        print(f"      Total records in 'swiggy_restaurants': {total_rows:,}")

        # Sample Quick Insights
        print("\n" + "=" * 65)
        print("DATABASE VALIDATION & QUICK SQL INSIGHTS")
        print("=" * 65)

        # Top 5 Locations
        print("\nTop 5 Locations by Restaurant Count:")
        cur.execute("""
            SELECT location, COUNT(*) as count 
            FROM swiggy_restaurants 
            GROUP BY location 
            ORDER BY count DESC 
            LIMIT 5;
        """)
        for loc, count in cur.fetchall():
            print(f" - {loc:25}: {count:6,} restaurants")

        # Top 5 Cuisines
        print("\nTop 5 Primary Cuisines:")
        cur.execute("""
            SELECT primary_cuisine, COUNT(*) as count 
            FROM swiggy_restaurants 
            GROUP BY primary_cuisine 
            ORDER BY count DESC 
            LIMIT 5;
        """)
        for cui, count in cur.fetchall():
            print(f" - {cui:25}: {count:6,} restaurants")

        # Average Cost & Rating
        cur.execute("""
            SELECT 
                ROUND(AVG(cost_for_two), 1) as avg_cost,
                ROUND(AVG(rating), 2) as avg_rating,
                SUM(CASE WHEN is_pure_veg THEN 1 ELSE 0 END) as veg_count,
                COUNT(*) as total
            FROM swiggy_restaurants;
        """)
        avg_cost, avg_rating, veg_count, total = cur.fetchone()
        print(f"\nKey Metrics:")
        print(f" - Average Cost for Two : ₹{avg_cost}")
        print(f" - Average Rating       : {avg_rating} ⭐")
        print(f" - Pure Veg Restaurants : {veg_count:,} ({veg_count/total*100:.1f}%)")

        print("\n" + "=" * 65)
        print("Data ingestion complete! PostgreSQL is ready for analysis.")
        print("=" * 65)

        cur.close()
        conn.close()

    except Exception as e:
        print(f"\n[ERROR] Ingestion failed: {e}")

if __name__ == "__main__":
    import_swiggy_data()
