"""Health and configuration reporting."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.v1.dependencies import get_pipeline
from app.config import Settings, get_settings
from app.core.errors import ApiError
from app.schemas.base import WireModel
from app.services.ai.registry import registry

router = APIRouter(tags=["health"])


class HealthResponse(WireModel):
    status: str
    """`ok`, or `degraded` when the service is up but cannot scan."""

    version: str
    vision_provider: str
    gemini_configured: bool
    """Whether a credential is present — never the credential itself."""

    gemini_model: str | None = None
    """Which model the Gemini provider will call, when it is the one selected.

    A model name is configuration, not a secret, and it is the field a 404 from
    the API turns on: "no such model for this API version" is unanswerable
    without knowing which name was sent.
    """

    available_providers: list[str]
    pipeline_stages: list[str]

    problem: str | None = None
    """Why the service is degraded, when it is."""


@router.get(
    "/health",
    response_model=HealthResponse,
    response_model_exclude_none=True,
    summary="Liveness and wiring",
)
async def health(settings: Settings = Depends(get_settings)) -> HealthResponse:
    """Reports what the service is actually running.

    The pipeline is built *here* rather than injected, so that a provider which
    cannot be constructed — `VISION_PROVIDER=gemini` with no key, say — is
    reported as `degraded` with the reason instead of turning this endpoint into
    a 503.

    That distinction matters operationally. A 503 from `/health` reads as "the
    service is down" to every monitor and load balancer, and would take a
    process out of rotation and page someone. The service is not down; it is
    misconfigured, and this is the endpoint an operator hits to find that out.
    Failing here fails at precisely the moment it needs to explain itself.
    """
    common = {
        "version": "0.1.0",
        "vision_provider": settings.vision_provider,
        "gemini_configured": settings.gemini_configured,
        # Omitted when no key is set, so it appears only where it means
        # something: the model that will actually be called.
        "gemini_model": settings.gemini_model if settings.gemini_configured else None,
        "available_providers": registry.names,
    }

    try:
        pipeline = get_pipeline()
    except ApiError as error:
        return HealthResponse(
            status="degraded",
            pipeline_stages=[],
            problem=f"{error.detail}{f' ({error.hint})' if error.hint else ''}",
            **common,  # type: ignore[arg-type]
        )

    # The stage list is the useful part: it makes the pipeline's composition
    # visible without reading the configuration, so "why did that scan cost
    # money?" is answerable from outside the process.
    return HealthResponse(
        status="ok",
        pipeline_stages=pipeline.stage_names,
        **common,  # type: ignore[arg-type]
    )
