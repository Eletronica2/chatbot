"""Per-tenant document registry used to make knowledge sync idempotent.

One row per (tenant_id, document_id) holding the last applied version, hash and status. Deleted
documents keep a tombstone row so an older upsert arriving late cannot resurrect them.
"""

import os
import sqlite3
import threading
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class RegistryEntry:
    tenant_id: str
    document_id: str
    version: int
    content_hash: str
    status: str
    updated_at: str
    synced_at: float
    chunks: int


class DocumentRegistry:
    def __init__(self, path: str):
        if path != ":memory:":
            os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        self._lock = threading.Lock()
        self._db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute(
            """
            CREATE TABLE IF NOT EXISTS documents (
                tenant_id TEXT NOT NULL,
                document_id TEXT NOT NULL,
                version INTEGER NOT NULL,
                content_hash TEXT NOT NULL,
                status TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                synced_at REAL NOT NULL,
                chunks INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (tenant_id, document_id)
            )
            """
        )

    def get(self, tenant_id: str, document_id: str) -> RegistryEntry | None:
        with self._lock:
            row = self._db.execute(
                "SELECT tenant_id, document_id, version, content_hash, status, updated_at, synced_at, chunks "
                "FROM documents WHERE tenant_id = ? AND document_id = ?",
                (tenant_id, document_id),
            ).fetchone()
        return RegistryEntry(*row) if row else None

    def put(self, tenant_id: str, document_id: str, version: int, content_hash: str, status: str, updated_at: str, chunks: int) -> None:
        with self._lock:
            self._db.execute(
                "INSERT INTO documents (tenant_id, document_id, version, content_hash, status, updated_at, synced_at, chunks) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(tenant_id, document_id) DO UPDATE SET version = excluded.version, "
                "content_hash = excluded.content_hash, status = excluded.status, updated_at = excluded.updated_at, "
                "synced_at = excluded.synced_at, chunks = excluded.chunks",
                (tenant_id, document_id, version, content_hash, status, updated_at, time.time(), chunks),
            )

    def manifest(self, tenant_id: str) -> list[RegistryEntry]:
        with self._lock:
            rows = self._db.execute(
                "SELECT tenant_id, document_id, version, content_hash, status, updated_at, synced_at, chunks "
                "FROM documents WHERE tenant_id = ? ORDER BY document_id",
                (tenant_id,),
            ).fetchall()
        return [RegistryEntry(*r) for r in rows]

    def ping(self) -> bool:
        with self._lock:
            return self._db.execute("SELECT 1").fetchone() == (1,)
