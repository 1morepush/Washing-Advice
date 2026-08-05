"""Wiring.

Assembles the pipeline from configuration: a knowledge-cache stage if enabled,
then the selected provider. Everything is built once per process and reused,
because the knowledge cache is only useful if it outlives a single request.
"""

from __future__ import annotations

from functools import lru_cache

from app.config import Settings, get_settings
from app.core.errors import ProviderUnavailableError
from app.services.ai import providers as _providers  # noqa: F401 — registers providers
from app.services.ai.base import ProviderError, StageCost, VisionStage
from app.services.ai.knowledge_cache import (
    InMemoryKnowledgeCache,
    KnowledgeCache,
    KnowledgeCacheStage,
)
from app.services.ai.pipeline import VisionPipeline
from app.services.ai.registry import registry
from app.services.ai.stages import ProviderStage


@lru_cache
def get_knowledge_cache() -> KnowledgeCache:
    """The process-wide cache.

    Cached deliberately: a per-request cache would never hit, which would make
    the whole memory stage decorative.
    """
    settings = get_settings()
    return InMemoryKnowledgeCache(max_entries=settings.knowledge_cache_max_entries)


@lru_cache
def get_pipeline() -> VisionPipeline:
    """Builds the pipeline described by the current settings."""
    settings: Settings = get_settings()
    cache = get_knowledge_cache() if settings.knowledge_cache_enabled else None

    stages: list[VisionStage] = []
    if cache is not None:
        stages.append(KnowledgeCacheStage(cache))

    try:
        provider = registry.create(settings.vision_provider)
    except KeyError as error:
        raise ProviderUnavailableError(
            str(error),
            hint=f"registered providers: {', '.join(registry.names)}",
        ) from error
    except ProviderError as error:
        raise ProviderUnavailableError(
            str(error),
            hint="set GEMINI_API_KEY, or set VISION_PROVIDER=fake",
        ) from error

    stages.append(ProviderStage(provider, cost=StageCost.NETWORK, cache=cache))

    return VisionPipeline(
        stages,
        sufficient_confidence=settings.sufficient_confidence,
    )


def reset_wiring() -> None:
    """Clears the cached singletons.

    For tests, which build the app repeatedly with different settings in one
    process and would otherwise get the first pipeline every time.
    """
    get_pipeline.cache_clear()
    get_knowledge_cache.cache_clear()
    get_settings.cache_clear()
