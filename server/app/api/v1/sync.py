"""Sync endpoints.

Two operations, matching `SyncRemote` in the Dart core exactly: pull what has
changed, push what has changed locally. The server is a relay — it stores and
returns opaque records and does no reconciliation of its own.

That is the important architectural point. All the conflict rules — items merge
by provenance, events by union, counters by replay — live in `wardrobe_core`
and run **on the device**. Putting them here as well would mean two
implementations of the same subtle logic in two languages, and the one that
matters is the one that has to work offline anyway.

Handlers are `def` rather than `async def` on purpose: the store is synchronous
SQLite, and FastAPI runs sync handlers in a threadpool. Declaring them `async`
would block the event loop on every disk write.
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status

from app.api.v1.dependencies import get_sync_store
from app.config import Settings, get_settings
from app.schemas.sync import SyncPullResponse, SyncPushRequest, SyncPushResponse
from app.services.sync.accounts import InvalidTokenError, account_for
from app.services.sync.store import SyncStore

router = APIRouter(tags=["sync"])


def _account(
    authorization: str | None,
    settings: Settings,
) -> str:
    """Resolves the bearer token to an account key, or refuses.

    Errors deliberately say what is wrong with the *request* and never echo the
    token, not even a prefix of it: this is a bearer credential, and error
    responses end up in logs, bug reports and screenshots.
    """
    if not settings.sync_enabled:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Sync is not enabled on this server.",
        )

    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="A sync token is required, as 'Authorization: Bearer <token>'.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        return account_for(authorization[len("bearer ") :])
    except InvalidTokenError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(error),
            headers={"WWW-Authenticate": "Bearer"},
        ) from error


@router.get("/sync", response_model=None)
def pull(
    since: datetime | None = Query(
        default=None,
        description=(
            "Return everything changed at or after this instant. Omit on a "
            "fresh install to receive everything."
        ),
    ),
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    store: SyncStore = Depends(get_sync_store),
) -> dict[str, object]:
    account = _account(authorization, settings)
    batch = store.pull(account, _as_utc(since))

    return SyncPullResponse(
        items=batch.items,
        events=batch.events,
        server_time=batch.server_time,
    ).to_wire()


@router.post("/sync", response_model=None)
def push(
    payload: SyncPushRequest,
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
    store: SyncStore = Depends(get_sync_store),
) -> dict[str, object]:
    account = _account(authorization, settings)

    if payload.total > settings.max_sync_records_per_request:
        # A cap rather than silent truncation. Truncating would make the client
        # believe everything landed and advance its cursor past records the
        # server never stored — data loss that neither side could detect.
        raise HTTPException(
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
            detail=(
                f"At most {settings.max_sync_records_per_request} records per "
                f"request; received {payload.total}. Sync in smaller batches."
            ),
        )

    accepted_at = store.push(account, payload.items, payload.events)

    return SyncPushResponse(
        accepted_at=accepted_at,
        items=len(payload.items),
        events=len(payload.events),
    ).to_wire()


def _as_utc(moment: datetime | None) -> datetime | None:
    """Treats a naive timestamp as UTC.

    Clients are supposed to send an offset. One that does not is far more
    likely to mean UTC — the whole domain stores UTC — than to mean the
    server's local timezone, and comparing a naive value against a stored
    aware one raises rather than merely being wrong.
    """
    if moment is None:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=UTC)
