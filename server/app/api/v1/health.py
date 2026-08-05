"""Health and configuration reporting."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.v1.dependencies import get_pipeline
from app.config import Settings, get_settings
from app.schemas.base import WireModel
from app.services.ai.pipeline import VisionPipeline
from app.services.ai.registry import registry

router = APIRouter(tags=["health"])


class HealthResponse(WireModel):
    status: str
    version: str
    vision_provider: str
    gemini_configured: bool
    """Whether a credential is present — never the credential itself."""

    available_providers: list[str]
    pipeline_stages: list[str]


@router.get("/health", response_model=HealthResponse, summary="Liveness and wiring")
async def health(
    settings: Settings = Depends(get_settings),
    pipeline: VisionPipeline = Depends(get_pipeline),
) -> HealthResponse:
    """Reports what the service is actually running.

    The stage list is the useful part: it makes the pipeline's composition
    visible without reading the configuration, so "why did that scan cost
    money?" is answerable from outside the process.
    """
    return HealthResponse(
        status="ok",
        version="0.1.0",
        vision_provider=settings.vision_provider,
        gemini_configured=settings.gemini_configured,
        available_providers=registry.names,
        pipeline_stages=pipeline.stage_names,
    )
