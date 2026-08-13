"""Treating a stain, on the wire.

Every name here has a counterpart in
`packages/wardrobe_core/lib/src/care/stains/stain_treatment.dart`, and the Dart
side decodes enums with `values.byName`, so a member's *value* here must equal
the Dart identifier exactly. A mismatch is not a build error in either language
— it is a step the app silently drops on a user's phone.

The structured fields beside `instruction` are the point of this schema. The
app refuses steps its garment's care forbids, and it cannot do that from prose:
"soak in hot water" and "soak in cool water" are one word apart in a sentence
and worlds apart for a wool jumper. A model that returned only paragraphs would
be unvettable, so the contract makes the checkable facts mandatory to state.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import Field

from app.schemas.base import WireModel
from app.schemas.scan import ScanDiagnostics


class BleachUse(StrEnum):
    """Which bleach a step calls for.

    Split because care labels split them, and the difference decides whether a
    garment survives: "non-chlorine only" is the commonest bleach symbol on
    clothing, and collapsing it into "bleach" would throw away most of what
    actually shifts a stain.
    """

    CHLORINE = "chlorine"
    OXYGEN = "oxygen"


class TreatmentStep(WireModel):
    """One instruction, with the facts that make it checkable."""

    instruction: str = Field(min_length=1, max_length=400)
    because: str | None = Field(default=None, max_length=400)

    temperature_c: int | None = Field(default=None, ge=0, le=95)
    bleach: BleachUse | None = None
    is_machine_wash: bool = False
    abrades: bool = False


class StainAdviceRequest(WireModel):
    """What the app knows about the garment and what was spilled on it.

    The garment is described in the words the app already renders on its own
    screens rather than as a structure. Two reasons: the model reasons better
    about "70% Wool, 30% Polyester" than about an enum map, and it keeps this
    endpoint from growing a second, drifting copy of the wardrobe model. The
    *checking* does not happen here anyway — it happens in the core, against
    the real values.
    """

    substance: str = Field(min_length=1, max_length=200)

    fabric: str = Field(min_length=1, max_length=200)
    color: str | None = Field(default=None, max_length=100)

    care: str = Field(min_length=1, max_length=600)

    note: str | None = Field(default=None, max_length=500)


class StainAdviceResponse(WireModel):
    steps: list[TreatmentStep]

    # What the model believes the stain to be, in a line. Shown so the user can
    # correct a misread before following advice aimed at the wrong substance.
    identified_as: str | None = None

    diagnostics: ScanDiagnostics | None = None
