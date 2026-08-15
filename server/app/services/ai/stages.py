"""Adapting a provider into a pipeline stage.

A provider is a *capability* — Gemini, a local model. A stage is a *step in a
strategy*. Keeping them separate means a new provider is registered once and
immediately works in every pipeline, and that a stage can exist with no provider
behind it at all (the knowledge cache is exactly that).
"""

from __future__ import annotations

import logging

from app.schemas.scan import ScanKind
from app.services.ai.base import (
    ProviderError,
    ScanRequest,
    StageCost,
    StageOutcome,
    VisionProvider,
)
from app.services.ai.knowledge_cache import KnowledgeCache, image_signature

logger = logging.getLogger(__name__)


class ProviderStage:
    """Runs a provider as a pipeline stage.

    Also writes what it learns back into the knowledge cache, so the next
    identical scan is answered for free. Doing that here rather than in the
    provider keeps providers stateless and makes the caching policy one
    decision in one place.
    """

    def __init__(
        self,
        provider: VisionProvider,
        *,
        cost: StageCost = StageCost.NETWORK,
        cache: KnowledgeCache | None = None,
    ) -> None:
        self._provider = provider
        self._cost = cost
        self._cache = cache

    @property
    def name(self) -> str:
        return self._provider.name

    @property
    def cost(self) -> StageCost:
        return self._cost

    def handles(self, kind: ScanKind) -> bool:
        return True

    async def run(self, request: ScanRequest) -> StageOutcome:
        try:
            match request.kind:
                case ScanKind.GARMENT:
                    return await self._garment(request)
                case ScanKind.CARE_TAG:
                    return await self._care_tag(request)
                case ScanKind.PILE:
                    return await self._pile(request)
        except ProviderError as error:
            # A provider failing is an ordinary outcome for a stage: the
            # pipeline should carry on and let another stage try, not collapse.
            # Logged rather than surfaced to the client — the client sees a
            # uniform "could not be identified" either way, but an operator
            # reading Render's logs needs to tell "bad photo" apart from
            # "bad API key" or "quota exceeded".
            logger.warning("stage %s declined: %s", self.name, error)
            return StageOutcome.declined(self.name, str(error))

    async def _garment(self, request: ScanRequest) -> StageOutcome:
        result = await self._provider.scan_garment(request.images)

        if self._cache is not None and result.brand is not None and result.composition is not None:
            await self._cache.observe_composition(
                result.brand.value,
                result.type.value,
                result.composition.value,
            )

        return StageOutcome(
            stage=self.name,
            result=result,
            confidence=result.type.confidence,
        )

    async def _care_tag(self, request: ScanRequest) -> StageOutcome:
        result = await self._provider.scan_care_tag(request.images)

        if self._cache is not None:
            # Keyed on the first photograph, as the lookup is. A second side
            # cannot be part of the key without making the cache miss whenever
            # somebody photographs the same label in a different order.
            await self._cache.remember_care(image_signature(request.primary), result)
            if request.known_brand and result.composition is not None:
                await self._cache.observe_composition(
                    request.known_brand,
                    request.known_type or "other",
                    result.composition.value,
                )

        return StageOutcome(
            stage=self.name,
            result=result,
            confidence=result.confidence,
        )

    async def _pile(self, request: ScanRequest) -> StageOutcome:
        result = await self._provider.scan_pile(request.primary)
        # A pile's confidence is that of its least certain detection: an answer
        # is only as good as the item most likely to have been misread.
        confidence = (
            min(item.detection_confidence for item in result.items) if result.items else 0.0
        )
        return StageOutcome(stage=self.name, result=result, confidence=confidence)
