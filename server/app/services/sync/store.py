"""Storage for synced wardrobes.

## The server does not know what a garment is

Records are stored as opaque JSON blobs keyed by id. Nothing here parses an
item, validates a care profile, or has an opinion about fibre percentages —
`wardrobe_core` is the single authority on what any of that means, and a second
implementation of the domain in Python would be a second thing to keep correct.

The practical payoff: adding a field to the domain requires no server change at
all. The cost: the server cannot reject nonsense, so a corrupted client can
push corrupted data. That trade is right for a relay whose clients are all the
same codebase, and wrong the moment third parties write to it.

## Server time, not client time

Every row carries a `received_at` stamped by the server, and `since` filters on
that rather than on the client's own timestamps. Two devices in different
timezones with drifting clocks would otherwise silently skip changes: a device
whose clock runs five minutes fast marks its cursor into the future and never
sees anything written in that window.

`since` is deliberately inclusive. Re-delivering a record the client already
has costs nothing — merging is idempotent by construction, which is the whole
premise of the sync engine — while *missing* one written in the same
millisecond as the cursor loses data permanently. Given the choice between
sending too much and losing something, this sends too much.
"""

from __future__ import annotations

import json
import sqlite3
import threading
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Literal, Protocol

RecordKind = Literal["item", "event"]


@dataclass(frozen=True, slots=True)
class SyncRecord:
    """One stored row: an opaque payload and the metadata needed to route it."""

    id: str
    kind: RecordKind
    payload: dict[str, Any]
    received_at: datetime


@dataclass(frozen=True, slots=True)
class StoredBatch:
    """What a pull returns."""

    records: tuple[SyncRecord, ...] = ()
    server_time: datetime = field(default_factory=lambda: datetime.now(UTC))

    @property
    def items(self) -> list[dict[str, Any]]:
        return [r.payload for r in self.records if r.kind == "item"]

    @property
    def events(self) -> list[dict[str, Any]]:
        return [r.payload for r in self.records if r.kind == "event"]


class SyncStore(Protocol):
    """Per-account storage for synced records."""

    def pull(self, account: str, since: datetime | None) -> StoredBatch:
        """Everything for `account` changed at or after `since`.

        `None` means everything, which is what a fresh install asks for.
        """
        ...

    def push(
        self,
        account: str,
        items: list[dict[str, Any]],
        events: list[dict[str, Any]],
    ) -> datetime:
        """Stores records and returns the server time they were accepted at."""
        ...

    def close(self) -> None: ...


def _batches(
    items: list[dict[str, Any]],
    events: list[dict[str, Any]],
) -> tuple[tuple[RecordKind, list[dict[str, Any]]], ...]:
    """The two kinds, typed, so the literals are not merely `str`."""
    return (("item", items), ("event", events))


def _record_id(payload: dict[str, Any]) -> str | None:
    """The record's own id, or None when the payload has no usable one.

    The single field the server does insist on. Without an id there is no way
    to replace a record rather than accumulate duplicates of it, which would
    turn every sync into unbounded growth.
    """
    value = payload.get("id")
    return value if isinstance(value, str) and value else None


class InMemorySyncStore:
    """Holds everything in a dict. For tests, and for a disposable server.

    Not only a test double: as with the repositories in `wardrobe_core`, this is
    the readable definition of what the operations mean, and the SQLite version
    is checked against it by a shared contract suite.
    """

    def __init__(self) -> None:
        self._rows: dict[str, dict[tuple[RecordKind, str], SyncRecord]] = {}
        self._lock = threading.Lock()

    def pull(self, account: str, since: datetime | None) -> StoredBatch:
        now = datetime.now(UTC)
        with self._lock:
            rows = list(self._rows.get(account, {}).values())

        selected = [r for r in rows if since is None or r.received_at >= since]
        # Oldest first, then by id, so a pull is reproducible. An unordered
        # result would make two identical syncs look different in a diff and
        # make any pagination added later incorrect.
        selected.sort(key=lambda r: (r.received_at, r.kind, r.id))
        return StoredBatch(records=tuple(selected), server_time=now)

    def push(
        self,
        account: str,
        items: list[dict[str, Any]],
        events: list[dict[str, Any]],
    ) -> datetime:
        now = datetime.now(UTC)
        with self._lock:
            bucket = self._rows.setdefault(account, {})
            for kind, payloads in _batches(items, events):
                for payload in payloads:
                    record_id = _record_id(payload)
                    if record_id is None:
                        continue
                    key = (kind, record_id)
                    if kind == "event" and key in bucket:
                        # Events are immutable facts. Re-sending one is a retry,
                        # not a correction, so the first arrival is kept and its
                        # `received_at` is not disturbed — otherwise a client
                        # retrying a dropped push would repeatedly move the
                        # record forward and re-deliver it to every other device.
                        continue
                    bucket[key] = SyncRecord(
                        id=record_id,
                        kind=kind,
                        payload=payload,
                        received_at=now,
                    )
        return now

    def close(self) -> None:
        self._rows.clear()


_SCHEMA = """
CREATE TABLE IF NOT EXISTS records (
    account     TEXT NOT NULL,
    kind        TEXT NOT NULL,
    id          TEXT NOT NULL,
    payload     TEXT NOT NULL,
    received_at TEXT NOT NULL,
    PRIMARY KEY (account, kind, id)
);
CREATE INDEX IF NOT EXISTS idx_records_pull
    ON records (account, received_at);
"""


class SqliteSyncStore:
    """The durable store.

    Uses the standard library rather than an async driver, and the endpoints
    that call it are declared `def` rather than `async def` so FastAPI runs them
    in a threadpool. Adding an async database driver would buy throughput this
    service does not need and cost a dependency it would then have to keep.
    """

    def __init__(self, path: str | Path) -> None:
        self._path = Path(path)
        if self._path.parent != Path():
            self._path.parent.mkdir(parents=True, exist_ok=True)
        # `check_same_thread=False` because FastAPI's threadpool hands requests
        # to whichever worker is free; every access is serialised by the lock
        # below, which is what actually makes that safe.
        self._db = sqlite3.connect(str(self._path), check_same_thread=False)
        self._db.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        with self._lock:
            self._db.executescript(_SCHEMA)
            # WAL so a long pull does not block a concurrent push.
            self._db.execute("PRAGMA journal_mode=WAL")
            self._db.commit()

    def pull(self, account: str, since: datetime | None) -> StoredBatch:
        now = datetime.now(UTC)
        sql = "SELECT kind, id, payload, received_at FROM records WHERE account = ?"
        params: list[Any] = [account]
        if since is not None:
            sql += " AND received_at >= ?"
            params.append(_to_text(since))
        sql += " ORDER BY received_at, kind, id"

        with self._lock:
            rows = self._db.execute(sql, params).fetchall()

        return StoredBatch(
            records=tuple(
                SyncRecord(
                    id=row["id"],
                    kind=row["kind"],
                    payload=json.loads(row["payload"]),
                    received_at=_from_text(row["received_at"]),
                )
                for row in rows
            ),
            server_time=now,
        )

    def push(
        self,
        account: str,
        items: list[dict[str, Any]],
        events: list[dict[str, Any]],
    ) -> datetime:
        now = datetime.now(UTC)
        stamp = _to_text(now)

        with self._lock:
            for kind, payloads in _batches(items, events):
                for payload in payloads:
                    record_id = _record_id(payload)
                    if record_id is None:
                        continue
                    if kind == "event":
                        # See the note in `InMemorySyncStore.push`: an event is
                        # an immutable fact and the first arrival wins.
                        self._db.execute(
                            "INSERT OR IGNORE INTO records "
                            "(account, kind, id, payload, received_at) "
                            "VALUES (?, ?, ?, ?, ?)",
                            (account, kind, record_id, json.dumps(payload), stamp),
                        )
                    else:
                        self._db.execute(
                            "INSERT INTO records "
                            "(account, kind, id, payload, received_at) "
                            "VALUES (?, ?, ?, ?, ?) "
                            "ON CONFLICT (account, kind, id) DO UPDATE SET "
                            "payload = excluded.payload, "
                            "received_at = excluded.received_at",
                            (account, kind, record_id, json.dumps(payload), stamp),
                        )
            self._db.commit()

        return now

    def close(self) -> None:
        with self._lock:
            self._db.close()


def _to_text(moment: datetime) -> str:
    """ISO-8601 in UTC.

    Stored as text rather than as a unix number so the rows are readable in a
    console, and always normalised to UTC so string ordering is time ordering —
    which is what the index depends on.
    """
    return moment.astimezone(UTC).isoformat()


def _from_text(text: str) -> datetime:
    parsed = datetime.fromisoformat(text)
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)
