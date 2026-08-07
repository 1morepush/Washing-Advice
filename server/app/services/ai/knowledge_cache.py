"""What the system already knows, so it does not pay to learn it twice.

The "AI memory" idea: a wardrobe app scans the same label, the same brand and
the same garment repeatedly, and re-deriving all of it from scratch every time
is slow, costly and — because models are not deterministic — inconsistent.

This is deliberately implemented as a **pipeline stage at `StageCost.FREE`**
rather than a cache bolted onto the side of the orchestrator. That way "check
memory first" is not a special case in the pipeline; it is just the cheapest
stage, and it wins by the ordinary ordering rule.

## What it can and cannot do

It keys on a **hash of the image bytes**, so it recognises an identical image
being scanned again — a retry, a double-tap, the same photo re-uploaded. It
**cannot** recognise the same physical label photographed a second time at a
different angle; that needs a perceptual hash or an embedding, and pretending
otherwise would produce confident wrong answers on a garment the user has
genuinely re-photographed.

The brand prior is the part that generalises: once several Nike hoodies have
been scanned, their typical composition is a useful starting point when the next
label is unreadable.
"""

from __future__ import annotations

import hashlib
from collections import OrderedDict
from typing import Protocol, runtime_checkable

from app.schemas.common import Confident, Provenance
from app.schemas.scan import CareTagScanResult, ScanKind
from app.schemas.wardrobe import FabricComposition, Fiber, ItemType
from app.services.ai.base import ScanImage, ScanRequest, StageCost, StageOutcome


def image_signature(image: ScanImage) -> str:
    """A stable key for exact re-scans of the same image bytes."""
    return hashlib.sha256(image.data).hexdigest()


def brand_key(brand: str, item_type: ItemType | str) -> str:
    """A normalised key for brand-and-type priors."""
    type_value = item_type.value if isinstance(item_type, ItemType) else item_type
    return f"{brand.strip().lower()}::{type_value}"


@runtime_checkable
class KnowledgeCache(Protocol):
    """Remembers what has already been learned."""

    async def care_for_signature(self, signature: str) -> CareTagScanResult | None: ...

    async def remember_care(self, signature: str, result: CareTagScanResult) -> None: ...

    async def composition_prior(
        self, brand: str, item_type: ItemType | str
    ) -> Confident[FabricComposition] | None: ...

    async def observe_composition(
        self, brand: str, item_type: ItemType | str, composition: FabricComposition
    ) -> None: ...


class InMemoryKnowledgeCache:
    """A bounded in-process cache.

    Adequate for a single instance and for tests. A durable, shared
    implementation belongs behind the same protocol when the service is run as
    more than one process — no caller changes when that happens.
    """

    def __init__(self, max_entries: int = 2048) -> None:
        self._max_entries = max_entries
        self._care: OrderedDict[str, CareTagScanResult] = OrderedDict()
        self._compositions: dict[str, list[FabricComposition]] = {}

    async def care_for_signature(self, signature: str) -> CareTagScanResult | None:
        result = self._care.get(signature)
        if result is not None:
            self._care.move_to_end(signature)
        return result

    async def remember_care(self, signature: str, result: CareTagScanResult) -> None:
        # A reading that already admits it could not decode part of the label is
        # not worth remembering: caching it would make a poor scan permanent and
        # stop a better photograph from ever being taken.
        if not result.is_complete:
            return
        self._care[signature] = result
        self._care.move_to_end(signature)
        while len(self._care) > self._max_entries:
            self._care.popitem(last=False)

    async def composition_prior(
        self, brand: str, item_type: ItemType | str
    ) -> Confident[FabricComposition] | None:
        observations = self._compositions.get(brand_key(brand, item_type))
        if not observations:
            return None

        # The most common composition seen for this brand and type. Averaging
        # percentages across garments would invent a blend nobody makes.
        counts: dict[tuple[tuple[Fiber, int], ...], int] = {}
        for observation in observations:
            key = tuple(sorted(observation.root.items(), key=lambda kv: kv[0].value))
            counts[key] = counts.get(key, 0) + 1

        best_key, best_count = max(counts.items(), key=lambda kv: kv[1])
        agreement = best_count / len(observations)

        # Confidence rises with both how consistent the observations are and how
        # many there are. Two matching samples is a hint, not a fact, so the
        # sample factor is capped well below certainty.
        sample_factor = min(1.0, len(observations) / 5.0)
        confidence = round(agreement * sample_factor * 0.8, 4)
        if confidence <= 0.0:
            return None

        return Confident[FabricComposition](
            value=FabricComposition(dict(best_key)),
            confidence=confidence,
            source=Provenance.AI_INFERENCE,
        )

    async def observe_composition(
        self, brand: str, item_type: ItemType | str, composition: FabricComposition
    ) -> None:
        if not composition.is_plausible:
            return
        self._compositions.setdefault(brand_key(brand, item_type), []).append(composition)

    @property
    def size(self) -> int:
        return len(self._care)


class KnowledgeCacheStage:
    """The cache, as the pipeline's cheapest stage."""

    def __init__(self, cache: KnowledgeCache) -> None:
        self._cache = cache

    @property
    def name(self) -> str:
        return "knowledge-cache"

    @property
    def cost(self) -> StageCost:
        return StageCost.FREE

    def handles(self, kind: ScanKind) -> bool:
        # Only care-tag scans are cached. A garment photo varies too much
        # between shots for a byte-hash to hit, and a pile is never the same
        # twice — caching either would be dead weight that never answers.
        return kind is ScanKind.CARE_TAG

    async def run(self, request: ScanRequest) -> StageOutcome:
        signature = image_signature(request.primary)
        remembered = await self._cache.care_for_signature(signature)
        if remembered is None:
            return StageOutcome.declined(self.name, "no cached reading for this image")

        return StageOutcome(
            stage=self.name,
            result=remembered,
            confidence=remembered.confidence,
            notes=["served from memory; no model call was made"],
        )
