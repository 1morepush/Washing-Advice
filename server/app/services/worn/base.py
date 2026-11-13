"""What it takes to find the clothes a person is wearing.

Its own Protocol rather than a fourth `ScanKind`, for the reason the condition
reader is: the pipeline orders stages by cost and lets a remembered answer
pre-empt a paid one, and neither applies. A photograph of somebody in today's
outfit is never a repeat of a question already answered, so the knowledge cache
has nothing to offer, and what comes back is not a fact to be merged with
another stage's but pixels cut from this one photograph.

The reader only *finds*: what is worn, and where, and (if the model can) an
outline of each piece. Turning an outline into a picture is
`worn.cutting`, which is deterministic and does not belong behind a model's
interface.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol, runtime_checkable

from app.schemas.scan import GarmentScanResult
from app.services.ai.base import ScanImage
from app.services.worn.cutting import NormalisedBox


@dataclass(frozen=True, slots=True)
class RawDetection:
    """One piece of clothing as a reader saw it, before anything is checked."""

    scan: GarmentScanResult
    box: NormalisedBox
    detection_confidence: float

    mask: str | None = None
    """The outline as the model sent it: a base64 PNG probability map sized to
    the box, possibly with a `data:` prefix. Optional because a model may not
    return one, and unchecked because `cutting` is what decides whether to
    believe it."""


@runtime_checkable
class WornScanner(Protocol):
    @property
    def name(self) -> str: ...

    async def read(self, image: ScanImage) -> list[RawDetection]:
        """Every garment and accessory the person in [image] is wearing.

        [image] is already upright: its boxes and masks are measured against
        these pixels, so the cut must be made from the same ones.
        """
        ...
