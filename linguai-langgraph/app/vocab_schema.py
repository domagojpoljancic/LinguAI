"""
Canonical SQLite vocabulary schema.

Shared by:
- Runtime (vocab_store) for table creation / compatibility
- Offline ingestion pipeline for create/upgrade and write

Schema version allows future migrations; ingestion and runtime must agree on
table name and column set for retrieval.
"""

from pathlib import Path

# Schema version for future migrations (ingestion can refuse to write if version mismatch).
VOCAB_SCHEMA_VERSION = 1

# Valid CEFR levels and source_type for validation
CEFR_LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
SOURCE_TYPES = ("primary", "fallback", "seed", "cefr", "wiktionary")

# Default DB path (overridable by VOCAB_DB_PATH)
def default_db_path() -> Path:
    return Path(__file__).resolve().parents[1] / "data" / "vocab.db"


def create_table_sql() -> str:
    """Return the CREATE TABLE statement for vocab_entries (idempotent with IF NOT EXISTS)."""
    return """
    CREATE TABLE IF NOT EXISTS vocab_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_language TEXT NOT NULL,
        target_language TEXT NOT NULL,
        default_text   TEXT NOT NULL,
        target_text    TEXT NOT NULL,
        level          TEXT CHECK (level IS NULL OR level IN ('A1','A2','B1','B2','C1','C2')),
        topic          TEXT,
        tags           TEXT,
        score          REAL NOT NULL DEFAULT 1.0,
        source_type    TEXT NOT NULL DEFAULT 'primary' CHECK (source_type IN ('primary','fallback','seed','cefr','wiktionary')),
        source_id      TEXT,
        created_at     TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
        updated_at     TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
    );
    """


def unique_index_sql() -> str:
    """Unique constraint on (source_language, target_language, default_text, target_text)."""
    return """
    CREATE UNIQUE INDEX IF NOT EXISTS uq_vocab_pair
        ON vocab_entries(source_language, target_language, default_text, target_text);
    """


def retrieval_indexes_sql() -> str:
    """Indexes for runtime retrieval (language pair, topic, level)."""
    return """
    CREATE INDEX IF NOT EXISTS idx_vocab_lang_topic
        ON vocab_entries(source_language, target_language, topic);
    CREATE INDEX IF NOT EXISTS idx_vocab_lang_topic_level
        ON vocab_entries(source_language, target_language, topic, level);
    """


def schema_version_table_sql() -> str:
    """Metadata table for schema version."""
    return """
    CREATE TABLE IF NOT EXISTS _vocab_schema (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    """


def full_schema_sql() -> str:
    """Full schema script: table, unique index, retrieval indexes, version table."""
    return (
        create_table_sql()
        + unique_index_sql()
        + retrieval_indexes_sql()
        + schema_version_table_sql()
    )


def ensure_schema_version(conn) -> None:
    """Ensure vocab_entries has required columns and _vocab_schema is set. Safe to call multiple times."""
    cur = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='vocab_entries'"
    )
    if cur.fetchone() is None:
        conn.executescript(full_schema_sql())
        conn.execute(
            "INSERT OR REPLACE INTO _vocab_schema (key, value) VALUES (?, ?)",
            ("version", str(VOCAB_SCHEMA_VERSION)),
        )
        conn.commit()
        return
    # Add new columns if missing (SQLite doesn't support IF NOT EXISTS for columns)
    for col, ctype in (
        ("source_id", "TEXT"),
        ("created_at", "TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))"),
        ("updated_at", "TEXT DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))"),
    ):
        try:
            conn.execute(f"ALTER TABLE vocab_entries ADD COLUMN {col} {ctype}")
            conn.commit()
        except Exception:
            pass  # column already exists
    conn.executescript(schema_version_table_sql() + unique_index_sql() + retrieval_indexes_sql())
    conn.execute(
        "INSERT OR REPLACE INTO _vocab_schema (key, value) VALUES (?, ?)",
        ("version", str(VOCAB_SCHEMA_VERSION)),
    )
    conn.commit()


def describe_schema() -> str:
    """Human-readable schema description for docs/debug."""
    return """vocab_entries(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source_language TEXT NOT NULL,
  target_language TEXT NOT NULL,
  default_text   TEXT NOT NULL,
  target_text    TEXT NOT NULL,
  level          TEXT CHECK (level IS NULL OR level IN ('A1','A2','B1','B2','C1','C2')),
  topic          TEXT,
  tags           TEXT,
  score          REAL NOT NULL DEFAULT 1.0,
  source_type    TEXT NOT NULL CHECK (source_type IN ('primary','fallback','seed','cefr','wiktionary')),
  source_id      TEXT,
  created_at     TEXT,
  updated_at     TEXT
)
UNIQUE (source_language, target_language, default_text, target_text)
INDEX idx_vocab_lang_topic (source_language, target_language, topic)
INDEX idx_vocab_lang_topic_level (source_language, target_language, topic, level)
"""
