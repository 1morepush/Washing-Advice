"""The v1 API surface."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.v1 import (
    chat,
    condition,
    health,
    images,
    machines,
    scan,
    sell,
    stains,
    style,
    sync,
)
from app.core.request_limit import enforce_request_limit

api_router = APIRouter(prefix="/v1")

# Health and sync are open and unmetered; they spend no AI allowance. Everything
# else is listed here behind one dependency rather than limited inside each
# endpoint: a new endpoint in an existing router is covered without a line, and
# a new router must be added here to be, which is the choice to make.
_limited = [Depends(enforce_request_limit)]

api_router.include_router(health.router)
api_router.include_router(scan.router, dependencies=_limited)
# Cutout is not limited: it is local pixel work and spends no allowance.
api_router.include_router(images.router)
api_router.include_router(machines.router, dependencies=_limited)
api_router.include_router(stains.router, dependencies=_limited)
api_router.include_router(condition.router, dependencies=_limited)
api_router.include_router(style.router, dependencies=_limited)
api_router.include_router(chat.router, dependencies=_limited)
api_router.include_router(sell.router, dependencies=_limited)
api_router.include_router(sync.router)
