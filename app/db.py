import psycopg2
import psycopg2.extras
import os
from dotenv import load_dotenv

load_dotenv()

def get_connection():
    return psycopg2.connect(
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        dbname=os.getenv("DB_NAME"),
        user=os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD")
    )

def query(sql, params=None, fetchone=False, fetchall=False, commit=False):
    """Single-statement helper. Auto-commits if commit=True."""
    conn = get_connection()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    try:
        cur.execute(sql, params)
        if commit:
            conn.commit()
            return cur.rowcount
        if fetchone:
            return cur.fetchone()
        if fetchall:
            return cur.fetchall()
    finally:
        cur.close()
        conn.close()

def run_transaction(operations):
    """
    Atomic transaction: executes a list of (sql, params) tuples as one unit.
    If ANY operation fails the entire transaction is rolled back.
    Returns list of rowcounts on success, raises exception on failure.

    Each operation can be:
        (sql, params)
        (sql, params, min_rowcount)

    min_rowcount is useful for SELECT ... FOR UPDATE lock checks. If the
    statement affects/returns fewer rows, the whole transaction is rolled back.

    Usage:
        run_transaction([
            ("INSERT INTO ...", (val1, val2)),
            ("UPDATE ...",      (val3, val4), 1),
        ])
    """
    conn = get_connection()
    conn.autocommit = False          # explicit transaction control
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    try:
        results = []
        for operation in operations:
            if len(operation) == 2:
                sql, params = operation
                min_rowcount = None
            elif len(operation) == 3:
                sql, params, min_rowcount = operation
            else:
                raise ValueError("Transaction operations must be (sql, params) or (sql, params, min_rowcount)")
            cur.execute(sql, params)
            if min_rowcount is not None and cur.rowcount < min_rowcount:
                raise ValueError("Transaction precondition failed; a required row was not available")
            results.append(cur.rowcount)
        conn.commit()                # all succeeded → commit
        return results
    except Exception as e:
        conn.rollback()              # any failure → rollback everything
        raise e
    finally:
        cur.close()
        conn.close()
