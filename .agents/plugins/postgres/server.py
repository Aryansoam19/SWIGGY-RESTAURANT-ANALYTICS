import os
import sys
import json
from pathlib import Path
from typing import Optional
import psycopg2
from psycopg2.extras import RealDictCursor
from mcp.server.mcpserver import MCPServer

# Load .env file manually if present
def load_env_file():
    possible_paths = [
        Path(__file__).parent / ".env",
        Path.cwd() / ".env",
        Path(__file__).resolve().parents[3] / ".env"
    ]
    for env_path in possible_paths:
        if env_path.is_file():
            try:
                with open(env_path, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith("#") and "=" in line:
                            key, val = line.split("=", 1)
                            key = key.strip()
                            val = val.strip().strip("'\"")
                            os.environ[key] = val
                break
            except Exception:
                pass

load_env_file()

# Initialize MCP Server
app = MCPServer("postgres")

def get_connection():
    load_env_file()
    db_url = os.environ.get("DATABASE_URL")
    if db_url:
        return psycopg2.connect(db_url)
    
    return psycopg2.connect(
        host=os.environ.get("PGHOST", "localhost"),
        port=int(os.environ.get("PGPORT", "5432")),
        dbname=os.environ.get("PGDATABASE", "postgres"),
        user=os.environ.get("PGUSER", "postgres"),
        password=os.environ.get("PGPASSWORD", "")
    )

@app.tool()
def list_tables() -> str:
    """Lists all user tables in the connected PostgreSQL database."""
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT table_schema, table_name 
                    FROM information_schema.tables 
                    WHERE table_schema NOT IN ('information_schema', 'pg_catalog')
                    ORDER BY table_schema, table_name;
                """)
                rows = cur.fetchall()
                if not rows:
                    return "No tables found in user schemas."
                return json.dumps([{"schema": r[0], "table": r[1]} for r in rows], indent=2)
    except Exception as e:
        return f"Error listing tables: {e}"

@app.tool()
def describe_table(table_name: str) -> str:
    """Returns column details, types, and nullability for a given table name."""
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT column_name, data_type, is_nullable, column_default
                    FROM information_schema.columns
                    WHERE table_name = %s
                    ORDER BY ordinal_position;
                """, (table_name,))
                rows = cur.fetchall()
                if not rows:
                    return f"Table '{table_name}' not found."
                cols = [
                    {
                        "column": r[0],
                        "type": r[1],
                        "nullable": r[2],
                        "default": r[3]
                    }
                    for r in rows
                ]
                return json.dumps(cols, indent=2)
    except Exception as e:
        return f"Error describing table '{table_name}': {e}"

@app.tool()
def sample_table(table_name: str, limit: int = 5) -> str:
    """Returns sample rows from a table up to the specified limit (default 5)."""
    try:
        limit = max(1, min(limit, 50))
        # Basic identifier validation to prevent SQL injection on table name
        if not table_name.replace("_", "").isalnum():
            return "Invalid table name format."
            
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(f"SELECT * FROM \"{table_name}\" LIMIT %s;", (limit,))
                rows = cur.fetchall()
                return json.dumps([dict(r) for r in rows], indent=2, default=str)
    except Exception as e:
        return f"Error sampling table '{table_name}': {e}"

@app.tool()
def execute_query(sql_query: str) -> str:
    """Executes a SQL query on the PostgreSQL database. Returns results for SELECT or status for DDL/DML."""
    try:
        with get_connection() as conn:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(sql_query)
                if cur.description:
                    rows = cur.fetchmany(100)
                    total_fetched = len(rows)
                    data = [dict(r) for r in rows]
                    result = {
                        "row_count_returned": total_fetched,
                        "data": data
                    }
                    if total_fetched == 100:
                        result["note"] = "Output truncated to first 100 rows."
                    return json.dumps(result, indent=2, default=str)
                else:
                    conn.commit()
                    return f"Query executed successfully. Rows affected: {cur.rowcount}"
    except Exception as e:
        return f"SQL execution error: {e}"

if __name__ == "__main__":
    app.run(transport="stdio")
