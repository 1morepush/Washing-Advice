"""The v1 API surface."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import health, images, machines, scan, stains, sync

api_router = APIRouter(prefix="/v1")
api_router.include_router(health.router)
api_router.include_router(scan.router)
api_router.include_router(images.router)
api_router.include_router(machines.router)
api_router.include_router(stains.router)
api_router.include_router(sync.router)
