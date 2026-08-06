"""The sync wire contract.

Payloads are passed through untouched: an item is whatever `wardrobe_core`
serialised, and the server neither validates nor reshapes it. See the note at
the top of `services/sync/store.py` for why that is deliberate rather than lazy.

What *is* validated is the envelope — sizes, and that records carry ids —
because those are the server's own invariants rather than the domain's.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import Field

from app.schemas.base import WireModel


class SyncPushRequest(WireModel):
    """Local changes offered to the server."""

    items: list[dict[str, Any]] = Field(default_factory=list)
    events: list[dict[str, Any]] = Field(default_factory=list)

    @property
    def total(self) -> int:
        return len(self.items) + len(self.events)


class SyncPushResponse(WireModel):
    """What was accepted, and when the server says it happened.

    `accepted_at` is the value the client stores as its cursor, which is why it
    is server time: a client that recorded its own clock here would skip
    changes whenever the two disagreed.
    """

    accepted_at: datetime
    items: int
    events: int


class SyncPullResponse(WireModel):
    """Everything the server holds for this account since the client's cursor."""

    items: list[dict[str, Any]] = Field(default_factory=list)
    events: list[dict[str, Any]] = Field(default_factory=list)
    server_time: datetime
