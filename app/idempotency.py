"""
Idempotency store for POST /generate-boxes.

Key: (customer_id, request_id). We store the request payload hash and the response
so that exact replays return the cached response; same key with different payload
is treated as a conflict (caller returns 409).

Only successful responses (status=generated_placeholder) are stored so that
retries after transient failures can get a fresh run. Storage is SQLite in
data/idempotency.db. No TTL; entries persist until overwritten or DB is cleared.

Concurrency: SQLite serializes writes. Multiple workers may both miss get() for
the same new key and run the workflow; both will eventually call set() and the
last write wins. No cross-process lock; safe for single-instance or low-contention MVP.
"""

from __future__ import annotations

import hashlib
import json
import logging
import sqlite3
from pathlib import Path
from typing import Optional, Tuple

logger = logging.getLogger(__name__)

_BASE_DIR = Path(__file__).resolve().parents[1]
_DATA_DIR = _BASE_DIR / "data"
_DB_PATH = _DATA_DIR / "idempotency.db"


def _db_path() -> Path:
    """Path to idempotency SQLite DB. Overridable via IDEMPOTENCY_DB_PATH."""
    import os
    p = os.environ.get("IDEMPOTENCY_DB_PATH")
    if p:
        return Path(p)
    return _DB_PATH


def _ensure_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS idempotency_store (
            customer_id TEXT NOT NULL,
            request_id TEXT NOT NULL,
            request_hash TEXT NOT NULL,
            response_json TEXT NOT NULL,
            created_at TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
            PRIMARY KEY (customer_id, request_id)
        );
        """
    )
    conn.commit()


def get(customer_id: str, request_id: str) -> Optional[Tuple[str, str]]:
    """
    Look up a previous response by (customer_id, request_id).

    Returns:
        (request_hash, response_json) if found, else None.
    """
    path = _db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    try:
        _ensure_schema(conn)
        row = conn.execute(
            "SELECT request_hash, response_json FROM idempotency_store WHERE customer_id = ? AND request_id = ?",
            (customer_id, request_id),
        ).fetchone()
        if row is None:
            return None
        return (row[0], row[1])
    finally:
        conn.close()


def set(customer_id: str, request_id: str, request_hash: str, response_json: str) -> None:
    """
    Store a response for (customer_id, request_id). Overwrites if key already exists.
    Call only for successful outcomes (e.g. status=generated_placeholder).
    """
    path = _db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path)
    try:
        _ensure_schema(conn)
        conn.execute(
            """
            INSERT INTO idempotency_store (customer_id, request_id, request_hash, response_json)
            VALUES (?, ?, ?, ?)
            ON CONFLICT (customer_id, request_id) DO UPDATE SET
                request_hash = excluded.request_hash,
                response_json = excluded.response_json,
                created_at = strftime('%Y-%m-%dT%H:%M:%SZ','now')
            """,
            (customer_id, request_id, request_hash, response_json),
        )
        conn.commit()
        logger.debug("idempotency_set customer_id=%s request_id=%s", customer_id, request_id)
    finally:
        conn.close()
