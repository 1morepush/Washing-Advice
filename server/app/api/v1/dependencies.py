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
from app.services.ai.base import ProviderError, StageCost, VisionProvider, VisionStage
from app.services.ai.knowledge_cache import (
    InMemoryKnowledgeCache,
    KnowledgeCache,
    KnowledgeCacheStage,
)
from app.services.ai.pipeline import VisionPipeline
from app.services.ai.registry import registry
from app.services.ai.stages import ProviderStage
from app.services.images.cutout import BackgroundRemover, BorderSampledRemover
from app.services.machines.base import MachineIdentifier
from app.services.machines.fake import FakeMachineIdentifier
from app.services.machines.gemini_identifier import GeminiMachineIdentifier
from app.services.stains.base import StainAdviser
from app.services.stains.fake import FakeStainAdviser
from app.services.stains.gemini_adviser import GeminiStainAdviser
from app.services.sync.store import InMemorySyncStore, SqliteSyncStore, SyncStore


@lru_cache
def get_background_remover() -> BackgroundRemover:
    """The background remover.

    Cached because it is stateless and cheap to hold, and behind the interface
    so a learned matting model can replace it without any caller changing —
    the same seam `VisionProvider` gives the scan stages.
    """
    return BorderSampledRemover()


@lru_cache
def get_sync_store() -> SyncStore:
    """The sync store, built once per process.

    Cached because SQLite connections are not free and because the in-memory
    variant would otherwise lose everything between requests — which would look
    exactly like a server that silently drops data.
    """
    settings = get_settings()
    if settings.sync_db_path == ":memory:":
        return InMemorySyncStore()
    return SqliteSyncStore(settings.sync_db_path)


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

    _live_providers.append(provider)
    stages.append(ProviderStage(provider, cost=StageCost.NETWORK, cache=cache))

    return VisionPipeline(
        stages,
        sufficient_confidence=settings.sufficient_confidence,
    )


_live_providers: list[VisionProvider] = []
"""Providers built by `get_pipeline`, so their connection pools can be closed.

Tracked here rather than reached for through the pipeline's stages, which would
mean the shutdown path depended on the pipeline's internal shape.
"""

_live_identifiers: list[MachineIdentifier] = []
"""The same idea as `_live_providers`, for machine identifiers.

Kept separate rather than sharing that list: `MachineIdentifier` does not
structurally satisfy `VisionProvider` (different methods entirely), so typing
`_live_providers` to accept both would widen it for a shutdown-bookkeeping
convenience that only this module needs.
"""

_live_advisers: list[StainAdviser] = []
"""The same again for stain advisers, and separate for the same reason."""


@lru_cache
def get_stain_adviser() -> StainAdviser:
    """The stain adviser described by the current settings.

    Follows `get_machine_identifier` exactly, including reusing
    `VISION_PROVIDER` rather than adding a second setting: there is one AI
    backend either way, and a separate switch would only ever move in lockstep
    with this one.
    """
    settings = get_settings()
    if settings.vision_provider == "fake":
        adviser: StainAdviser = FakeStainAdviser()
    else:
        try:
            adviser = GeminiStainAdviser.from_settings(settings)
        except ProviderError as error:
            raise ProviderUnavailableError(
                str(error),
                hint="set GEMINI_API_KEY, or set VISION_PROVIDER=fake",
            ) from error

    _live_advisers.append(adviser)
    return adviser


@lru_cache
def get_machine_identifier() -> MachineIdentifier:
    """The machine identifier described by the current settings.

    Reuses `VISION_PROVIDER` rather than adding a second setting: there is one
    AI backend either way, and `/health`'s existing `geminiConfigured` /
    `visionProvider` fields already describe accurately whether this will
    work — a separate setting would only ever move in lockstep with this one.
    """
    settings = get_settings()
    if settings.vision_provider == "fake":
        identifier: MachineIdentifier = FakeMachineIdentifier()
    else:
        try:
            identifier = GeminiMachineIdentifier.from_settings(settings)
        except ProviderError as error:
            raise ProviderUnavailableError(
                str(error),
                hint="set GEMINI_API_KEY, or set VISION_PROVIDER=fake",
            ) from error

    _live_identifiers.append(identifier)
    return identifier


async def close_providers() -> None:
    """Releases every live provider's and identifier's resources, at shutdown."""
    for provider in (*_live_providers, *_live_identifiers, *_live_advisers):
        closer = getattr(provider, "aclose", None)
        if closer is not None:
            await closer()
    _live_providers.clear()
    _live_identifiers.clear()
    _live_advisers.clear()


def reset_wiring() -> None:
    """Clears the cached singletons.

    For tests, which build the app repeatedly with different settings in one
    process and would otherwise get the first pipeline every time.
    """
    get_pipeline.cache_clear()
    get_machine_identifier.cache_clear()
    get_stain_adviser.cache_clear()
    get_knowledge_cache.cache_clear()
    get_background_remover.cache_clear()
    # Closed before it is dropped: a SQLite store left to the garbage collector
    # holds its file handle and its WAL, and the next test opening the same
    # path inherits both.
    if get_sync_store.cache_info().currsize:
        get_sync_store().close()
    get_sync_store.cache_clear()
    _live_providers.clear()
    _live_identifiers.clear()
    _live_advisers.clear()
    get_settings.cache_clear()
