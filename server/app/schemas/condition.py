"""Looking a garment over for wear, on the wire.

`WearType` and `WearSeverity` have counterparts in
`packages/wardrobe_core/lib/src/wardrobe/model/condition.dart`, and the Dart
side decodes them with `values.byName` — so a member's *value* here must equal
the Dart identifier exactly. A mismatch is not a build error in either language;
it is an observation the app silently drops on somebody's phone.

Two fields carry more weight than they look. `confidence` is what the core's
floor is applied to, and a model that reported everything at 0.9 would make the
floor decorative — so the prompt spends real length on when to be unsure.
`note` says *where* on the garment, which is what lets somebody check the claim
against the thing in their hands in about two seconds. A report of pilling with
nowhere to look is one nobody can confirm or deny.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import Field

from app.schemas.base import WireModel
from app.schemas.scan import ScanDiagnostics


class WearType(StrEnum):
    """A kind of wear that can be seen on a garment."""

    FADING = "fading"
    PILLING = "pilling"
    HOLE = "hole"
    TEAR = "tear"
    STAIN = "stain"
    STRETCHED_OUT = "stretchedOut"
    SHRUNK = "shrunk"
    LOOSE_SEAM = "looseSeam"
    BROKEN_FASTENER = "brokenFastener"
    ODOUR = "odour"


class WearSeverity(StrEnum):
    SLIGHT = "slight"
    MODERATE = "moderate"
    SEVERE = "severe"


class ObservedWear(WireModel):
    """One thing the model believes it can see."""

    type: WearType
    severity: WearSeverity
    confidence: float = Field(ge=0.0, le=1.0)
    note: str | None = Field(
        default=None,
        max_length=200,
        description="Where on the garment, e.g. 'along the inner sleeve'.",
    )


class ConditionScanResult(WireModel):
    """Everything the model saw on one garment.

    An empty list is a real answer and the commonest one. Most garments are
    fine, and a reader that had to report *something* would report noise.
    """

    observed: list[ObservedWear] = Field(default_factory=list)


class ConditionResponse(WireModel):
    result: ConditionScanResult
    diagnostics: ScanDiagnostics | None = None
