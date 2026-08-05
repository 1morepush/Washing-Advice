"""The vision pipeline's core abstractions.

The orchestration layer exists so that *how* a scan is answered is a
configuration decision rather than a code change. Today one stage is registered
— Gemini. Tomorrow an on-device OCR pass, a cached answer, or a different model
can be inserted without any caller knowing.

The shape is a **pipeline of stages ordered by cost**. Each stage may answer
fully, answer partially, or decline, and the pipeline stops as soon as the
accumulated answer is good enough. "Check memory first, ask the expensive model
only if needed" then falls out of the design rather than being special-cased.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum
from typing import Protocol, runtime_checkable

from app.schemas.care import CareConstraint
from app.schemas.scan import (
    CareTagScanResult,
    GarmentScanResult,
    PileScanResult,
    ScanKind,
)

ScanResult = GarmentScanResult | CareTagScanResult | PileScanResult


class StageCost(IntEnum):
    """What a stage costs to run. The pipeline tries cheap stages first.

    An `IntEnum` so stages sort naturally: memory before device before network.
    """

    FREE = 0
    """Answered from memory or a local lookup. No model, no network."""

    ON_DEVICE = 1
    """Local computation or an on-device model. Cheap, but not free."""

    NETWORK = 2
    """A paid, rate-limited call to a remote model."""


@dataclass(frozen=True, slots=True)
class ScanImage:
    """Image bytes and enough context for a provider to work with.

    Held in memory only — never written to disk, never logged. A wardrobe is a
    photographic record of someone's home and possessions, and this service has
    no reason to retain any of it.
    """

    data: bytes
    mime_type: str = "image/jpeg"

    @property
    def size_bytes(self) -> int:
        return len(self.data)

    def __repr__(self) -> str:
        # Deliberately omits the bytes. repr() ends up in tracebacks and log
        # lines, which is exactly where image data must never appear.
        return f"ScanImage(mime_type={self.mime_type!r}, {self.size_bytes} bytes)"


@dataclass(frozen=True, slots=True)
class ScanRequest:
    """A request to identify something from one or more photographs."""

    kind: ScanKind
    images: list[ScanImage]

    known_brand: str | None = None
    """A brand the caller already knows, used to look up a composition prior."""

    known_type: str | None = None
    """A garment type the caller already knows, which narrows the prompt."""

    def __post_init__(self) -> None:
        if not self.images:
            raise ValueError("a scan request needs at least one image")

    @property
    def primary(self) -> ScanImage:
        """The image to use for single-image scans."""
        return self.images[0]


@dataclass(slots=True)
class StageOutcome:
    """What one stage produced.

    A stage may return a complete result, or a partial care reading that a later
    stage completes. `confidence` is the stage's own assessment, and is what the
    pipeline uses to decide whether to keep going.
    """

    stage: str
    result: ScanResult | None = None
    confidence: float = 0.0

    partial_care: CareConstraint | None = None
    """A partial care reading, for stages that recover only part of a label."""

    notes: list[str] = field(default_factory=list)

    @property
    def answered(self) -> bool:
        return self.result is not None

    @property
    def contributed(self) -> bool:
        return self.result is not None or self.partial_care is not None

    @classmethod
    def declined(cls, stage: str, reason: str) -> StageOutcome:
        """A stage that had nothing to contribute."""
        return cls(stage=stage, notes=[reason])


@runtime_checkable
class VisionStage(Protocol):
    """One step in the pipeline.

    Implementations must be safe to call concurrently and must not mutate the
    request.
    """

    @property
    def name(self) -> str:
        """Stable identifier, reported in diagnostics."""
        ...

    @property
    def cost(self) -> StageCost:
        """How expensive this stage is, which sets its place in the order."""
        ...

    def handles(self, kind: ScanKind) -> bool:
        """Whether this stage can contribute to this kind of scan."""
        ...

    async def run(self, request: ScanRequest) -> StageOutcome:
        """Attempts to answer.

        Must not raise for an ordinary failure to answer — return
        `StageOutcome.declined` instead, so one stage being unavailable never
        takes down the whole pipeline.
        """
        ...


@runtime_checkable
class VisionProvider(Protocol):
    """A model backend that can answer every kind of scan.

    Kept separate from `VisionStage` on purpose: a provider is a *capability*
    (Gemini, a local model), while a stage is a *step in a strategy*.
    `ProviderStage` adapts one to the other, so a new provider is registered
    once and works in every pipeline.
    """

    @property
    def name(self) -> str: ...

    async def scan_garment(self, images: list[ScanImage]) -> GarmentScanResult: ...

    async def scan_care_tag(self, image: ScanImage) -> CareTagScanResult: ...

    async def scan_pile(self, image: ScanImage) -> PileScanResult: ...


class ProviderError(RuntimeError):
    """A provider could not produce a usable answer.

    Raised for a genuine failure — the model was unreachable, or returned
    something that would not validate. Distinct from a stage *declining*, which
    is an ordinary outcome and not an error.
    """

    def __init__(self, provider: str, message: str) -> None:
        super().__init__(f"{provider}: {message}")
        self.provider = provider
