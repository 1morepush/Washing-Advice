"""Shared value types, mirroring `wardrobe_core`'s shared kernel.

Every name and every JSON key here has a counterpart in the Dart core. That
correspondence is not decorative: the app decodes exactly what this server
encodes, so a silent rename becomes a runtime failure on a user's phone. It is
pinned by the golden fixtures in `contracts/examples/`, which tests on both
sides parse.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Generic, TypeVar

from pydantic import Field

from app.schemas.base import WireModel

T = TypeVar("T")


class Provenance(StrEnum):
    """Where a believed fact came from, weakest evidence first.

    The declaration order is load-bearing — `resolution_rank` depends on it, and
    it must stay identical to the Dart `Provenance` enum.
    """

    FALLBACK_DEFAULT = "fallbackDefault"
    AI_INFERENCE = "aiInference"
    CARE_RULE = "careRule"
    TAG_SCAN = "tagScan"
    USER_EDITED = "userEdited"

    @property
    def resolution_rank(self) -> int:
        """Higher wins when two sources claim the same field."""
        return _PROVENANCE_ORDER.index(self)


_PROVENANCE_ORDER: tuple[Provenance, ...] = (
    Provenance.FALLBACK_DEFAULT,
    Provenance.AI_INFERENCE,
    Provenance.CARE_RULE,
    Provenance.TAG_SCAN,
    Provenance.USER_EDITED,
)


class Confident(WireModel, Generic[T]):
    """A value the system believes, with how strongly and on what basis.

    The honest shape of a model's output. Returning a bare value would force the
    app to invent a confidence, and the app's decision to ask "Is this your grey
    Nike hoodie?" rather than assume depends on this being real.
    """

    value: T
    confidence: float = Field(ge=0.0, le=1.0)
    source: Provenance = Provenance.AI_INFERENCE

    def attenuated_by(self, factor: float) -> Confident[T]:
        """Reduces confidence to reflect an additional uncertain step.

        Used when a belief rests on another belief: care rules applied to an
        AI-guessed fibre composition cannot be more certain than that guess was.
        """
        return Confident[T](
            value=self.value,
            confidence=self.confidence * min(1.0, max(0.0, factor)),
            source=self.source,
        )


def resolve(a: Confident[T], b: Confident[T]) -> Confident[T]:
    """Picks the belief that should win when two sources describe one field.

    Stronger provenance wins outright; within the same provenance the more
    confident belief wins. Deliberately not confidence-only — a hesitant care
    label still beats a breezy guess from a photograph.

    Mirrors `Confident.resolve` in the Dart core. If the two ever diverged, the
    same inputs would produce different advice depending on which side merged.
    """
    delta = a.source.resolution_rank - b.source.resolution_rank
    if delta != 0:
        return a if delta > 0 else b
    return a if a.confidence >= b.confidence else b


class BoundingBox(WireModel):
    """A rectangle in normalised image coordinates, 0..1 from the top left.

    Normalised so the value survives the image being resized or re-encoded
    between the device and the provider.
    """

    left: float = Field(ge=0.0, le=1.0)
    top: float = Field(ge=0.0, le=1.0)
    width: float = Field(gt=0.0, le=1.0)
    height: float = Field(gt=0.0, le=1.0)

    @property
    def right(self) -> float:
        return self.left + self.width

    @property
    def bottom(self) -> float:
        return self.top + self.height

    @property
    def area(self) -> float:
        return self.width * self.height

    def overlap_with(self, other: BoundingBox) -> float:
        """Fraction of the smaller box that the two share.

        Used to drop duplicate detections of one garment, which vision models
        produce routinely on a cluttered pile.
        """
        overlap_width = min(self.right, other.right) - max(self.left, other.left)
        overlap_height = min(self.bottom, other.bottom) - max(self.top, other.top)
        if overlap_width <= 0 or overlap_height <= 0:
            return 0.0
        smaller = min(self.area, other.area)
        return 0.0 if smaller == 0 else (overlap_width * overlap_height) / smaller
