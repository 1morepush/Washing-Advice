"""The v1 API surface."""

from __future__ import annotations

from fastapi import APIRouter

from app.api.v1 import health, scan

api_router = APIRouter(prefix="/v1")
api_router.include_router(health.router)
api_router.include_router(scan.router)
