"""Unit tests for idempotency store. Uses a temporary DB; no server required."""

import os
import tempfile

import pytest

# Use temp DB so we don't touch data/idempotency.db
@pytest.fixture(autouse=True)
def temp_idempotency_db(monkeypatch):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "idempotency.db")
        monkeypatch.setenv("IDEMPOTENCY_DB_PATH", path)
        yield path


def test_idempotency_get_miss():
    from app.idempotency import get
    assert get("c1", "r1") is None


def test_idempotency_set_and_get():
    from app.idempotency import get, set as idem_set
    idem_set("c1", "r1", "hash1", '{"requestId":"r1","status":"ok"}')
    out = get("c1", "r1")
    assert out is not None
    stored_hash, response_json = out
    assert stored_hash == "hash1"
    assert "r1" in response_json
    assert "ok" in response_json


def test_idempotency_different_keys_no_collision():
    from app.idempotency import get, set as idem_set
    idem_set("c1", "r1", "h1", "{}")
    assert get("c2", "r1") is None
    assert get("c1", "r2") is None
    out = get("c1", "r1")
    assert out is not None
    assert out[0] == "h1"


def test_idempotency_overwrite():
    from app.idempotency import get, set as idem_set
    idem_set("c1", "r1", "hash1", "resp1")
    idem_set("c1", "r1", "hash2", "resp2")
    out = get("c1", "r1")
    assert out is not None
    assert out[0] == "hash2"
    assert out[1] == "resp2"
