"""ISO 3758 care vocabulary, mirroring `wardrobe_core`'s care context.

The important type here is `CareConstraint`: every field is optional, and `None`
means *the label did not state this* — categorically different from "the label
permits this". A creased label whose drying symbol is illegible must come back
with `tumble_dry_allowed=None` so the core's rule table fills the gap from fibre
content. Returning `True` would read as permission the manufacturer never gave,
and is how a wool blend ends up in a tumble dryer.

See `docs/adr/0004-label-overrides-rules.md`.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Any

from pydantic import Field

from app.schemas.base import WireModel

_STATED_FIELDS: tuple[str, ...] = (
    "method",
    "max_temp_c",
    "agitation",
    "bleach",
    "tumble_dry_allowed",
    "tumble_dry_heat",
    "natural_dry",
    "dry_in_shade",
    "do_not_wring",
    "iron_temperature",
    "steam_allowed",
    "do_not_dry_clean",
    "solvent",
)


class WashMethod(StrEnum):
    MACHINE = "machine"
    HAND = "hand"
    DO_NOT_WASH = "doNotWash"


class Agitation(StrEnum):
    """Mechanical action, from the bars beneath the wash tub.

    A tub with **no bars** means `NORMAL` and must be reported as such. Leaving
    it unset instead makes every ordinary garment inherit the core's
    conservative default and get recommended a gentle cycle it does not need —
    which under-cleans and quietly erodes trust in every other recommendation.
    """

    NORMAL = "normal"
    MILD = "mild"
    VERY_MILD = "veryMild"


class BleachAllowance(StrEnum):
    ANY = "any"
    NON_CHLORINE_ONLY = "nonChlorineOnly"
    NONE = "none"


class TumbleDryHeat(StrEnum):
    NO_HEAT = "noHeat"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class NaturalDryMethod(StrEnum):
    LINE_DRY = "lineDry"
    DRIP_DRY = "dripDry"
    FLAT_DRY = "flatDry"


class IronTemperature(StrEnum):
    NONE = "none"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


class CleaningSolvent(StrEnum):
    PERCHLOROETHYLENE = "perchloroethylene"
    HYDROCARBON = "hydrocarbon"
    WET_CLEAN = "wetClean"


class CareWarning(StrEnum):
    WASH_INSIDE_OUT = "washInsideOut"
    WASH_SEPARATELY = "washSeparately"
    WASH_WITH_LIKE_COLOURS = "washWithLikeColours"
    DO_NOT_SOAK = "doNotSoak"
    USE_MESH_BAG = "useMeshBag"
    CLOSE_FASTENINGS = "closeFastenings"
    REMOVE_PROMPTLY = "removePromptly"
    RESHAPE_WHILE_DAMP = "reshapeWhileDamp"
    DO_NOT_USE_SOFTENER = "doNotUseSoftener"
    IRON_ON_REVERSE = "ironOnReverse"
    # "Do not iron decoration", printed on anything with a transfer or a
    # print. Distinct from IRON_ON_REVERSE, which says how to iron the whole
    # garment, and from an absent ironTemperature, which would forbid ironing
    # the fabric as well. The garment is ironable; the graphic is not.
    DO_NOT_IRON_DECORATION = "doNotIronDecoration"


class CareConstraint(WireModel):
    """A partial set of care requirements — exactly what a label states.

    Serialised with `exclude_none=True` so an unstated field is absent from the
    JSON rather than present as null, matching `contracts/care_constraint.schema.json`.
    """

    method: WashMethod | None = None
    max_temp_c: int | None = Field(default=None, ge=0, le=95)
    agitation: Agitation | None = None
    bleach: BleachAllowance | None = None
    tumble_dry_allowed: bool | None = Field(default=None)
    tumble_dry_heat: TumbleDryHeat | None = Field(default=None)
    natural_dry: NaturalDryMethod | None = Field(default=None)
    dry_in_shade: bool | None = Field(default=None)
    do_not_wring: bool | None = Field(default=None)
    iron_temperature: IronTemperature | None = Field(default=None)
    steam_allowed: bool | None = Field(default=None)
    do_not_dry_clean: bool | None = Field(default=None)
    solvent: CleaningSolvent | None = None
    warnings: list[CareWarning] = Field(default_factory=list)

    @property
    def stated_fields(self) -> set[str]:
        """Which care fields this constraint actually states."""
        return {name for name in _STATED_FIELDS if getattr(self, name) is not None}

    @property
    def states_nothing(self) -> bool:
        return not self.stated_fields and not self.warnings

    def merged_with(self, other: CareConstraint) -> CareConstraint:
        """Combines two partial readings, preferring whatever `self` states.

        Used to fold a cached reading into a fresh one, and to combine stages
        that each read part of a label — an on-device OCR pass may recover the
        fibre percentages while the wash symbols stay illegible.
        """
        merged: dict[str, Any] = {}
        for name in _STATED_FIELDS:
            mine = getattr(self, name)
            merged[name] = mine if mine is not None else getattr(other, name)
        merged["warnings"] = sorted({*self.warnings, *other.warnings}, key=lambda w: w.value)
        return CareConstraint(**merged)
