"""What it takes to look a garment over.

Its own Protocol rather than a fourth `ScanKind`, and that is a considered
choice rather than a shortcut. The pipeline exists to order stages by cost and
to let a cached answer pre-empt a paid one — neither applies here. A photograph
of *this* jumper today is never a repeat of a previous question, so the
knowledge cache has nothing to offer and a cache stage would be dead weight in
front of every call.

What this does need is the garment itself: pilling on wool and pilling on
polyester look different, and a reader told nothing about the fabric is
guessing. `ScanRequest` carries a brand and a type and no way to say that.
Widening it for one caller would have cost more than a small Protocol.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol, runtime_checkable

from app.schemas.condition import ConditionScanResult
from app.services.ai.base import ScanImage


@dataclass(frozen=True, slots=True)
class ConditionRequest:
    """The garment, described in the words the app already shows for it.

    Text rather than structure, for the same reason stain advice is: the model
    reasons better about "70% Wool, 30% Polyester" than about an enum map, and
    it keeps this endpoint from growing a second, drifting copy of the wardrobe
    model.
    """

    images: list[ScanImage]
    garment: str
    """What it is, e.g. 'Navy wool jumper'."""

    fabric: str | None = None
    known: str | None = None
    """Wear already recorded, so the model is not asked to re-find it."""

    def __post_init__(self) -> None:
        if not self.images:
            raise ValueError("a condition scan needs at least one image")


@runtime_checkable
class ConditionReader(Protocol):
    @property
    def name(self) -> str: ...

    async def read(self, request: ConditionRequest) -> ConditionScanResult: ...
