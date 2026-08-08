"""A washing machine or dryer, mirroring `wardrobe_core`'s machines context.

Every name and field here has an exact counterpart in
`packages/wardrobe_core/lib/src/machines/model/washer_profile.dart` and
`dryer_profile.dart` — those classes' own `toJson`/`fromJson` are what decode
what this server sends, so a mismatched enum member or field name is a silent
runtime failure on a user's phone rather than a build error here.

`Agitation` and `TumbleDryHeat` are not redefined: they already exist in
`app.schemas.care`, built for reading a care label's wash-tub and dry-dot
symbols, and their values already match the Dart enums a washer/dryer
programme also uses.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import Field

from app.schemas.base import WireModel
from app.schemas.care import Agitation, TumbleDryHeat
from app.schemas.scan import ScanDiagnostics


class FabricClass(StrEnum):
    """How a fabric behaves in a machine, mirroring the Dart `FabricClass`.

    Lives here rather than in `wardrobe.py`: it is a laundry-mechanics concept
    used by machine programmes, and this is its first and only appearance on
    the wire — `wardrobe_core` keeps its own copy in the wardrobe model, used
    far more broadly there.
    """

    DELICATE = "delicate"
    NORMAL = "normal"
    HEAVY = "heavy"


class WashProgramKind(StrEnum):
    """The role a wash programme plays, independent of what a dial calls it."""

    COTTON = "cotton"
    SYNTHETICS_MIXED = "syntheticsMixed"
    DELICATES = "delicates"
    WOOL = "wool"
    HAND_WASH = "handWash"
    QUICK = "quick"
    HEAVY_DUTY = "heavyDuty"
    SPORTSWEAR = "sportswear"
    BEDDING = "bedding"
    ECO = "eco"
    RINSE_SPIN = "rinseSpin"
    DRUM_CLEAN = "drumClean"


class WasherOption(StrEnum):
    EXTRA_RINSE = "extraRinse"
    PREWASH = "prewash"
    STEAM = "steam"
    STAIN_REMOVAL = "stainRemoval"
    DELAY_START = "delayStart"
    ECO_MODE = "ecoMode"
    SOFTENER_DISPENSER = "softenerDispenser"
    TIME_SAVER = "timeSaver"


class DryProgramKind(StrEnum):
    NORMAL = "normal"
    PERMANENT_PRESS = "permanentPress"
    DELICATES = "delicates"
    WOOL = "wool"
    AIR_FLUFF = "airFluff"
    TIMED_DRY = "timedDry"
    BEDDING = "bedding"
    QUICK = "quick"
    STEAM_REFRESH = "steamRefresh"


class DryerOption(StrEnum):
    WRINKLE_GUARD = "wrinkleGuard"
    STEAM = "steam"
    ECO_DRY = "ecoDry"
    # Verbatim, not a typo introduced here: the Dart enum member is spelled
    # this way, `.byName()` matches on the identifier rather than a label, and
    # correcting the spelling here would silently break every dryer with a
    # damp-dry signal.
    DAMD_DRY_STOP = "damdDryStop"
    SANITIZE = "sanitize"
    REVERSE_TUMBLE = "reverseTumble"


class DrynessControl(StrEnum):
    SENSOR = "sensor"
    TIMED = "timed"


class WashProgram(WireModel):
    """One programme on a washing machine.

    `id` is never asked of the model — it is assigned server-side after
    parsing, the same as every other id in a scan result. Gemini has no
    business inventing an identifier for a database row it will never see.
    """

    id: str
    display_name: str
    kind: WashProgramKind
    available_temps_c: list[int] = Field(default_factory=list)
    default_temp_c: int
    agitation: Agitation
    spin_speeds_rpm: list[int] = Field(default_factory=list)
    suitable_for: list[FabricClass] = Field(default_factory=list)
    max_load_fraction: float = Field(default=1.0, gt=0.0, le=1.0)
    typical_duration_minutes: int = Field(default=90, gt=0)


class WasherProfile(WireModel):
    id: str
    brand: str
    model: str
    capacity_kg: float = Field(gt=0.0)
    programs: list[WashProgram] = Field(default_factory=list)
    options: list[WasherOption] = Field(default_factory=list)
    # Always false here: see `WasherProfile.isVerifiedModel` in the Dart core.
    # An AI guess at a specific model's cycle line-up is exactly the kind of
    # thing that field exists to flag, not an exception to it.
    is_verified_model: bool = False


class DryProgram(WireModel):
    id: str
    display_name: str
    kind: DryProgramKind
    available_heats: list[TumbleDryHeat] = Field(default_factory=list)
    default_heat: TumbleDryHeat
    suitable_for: list[FabricClass] = Field(default_factory=list)
    control: DrynessControl = DrynessControl.SENSOR
    max_load_fraction: float = Field(default=1.0, gt=0.0, le=1.0)
    typical_duration_minutes: int = Field(default=60, gt=0)


class DryerProfile(WireModel):
    id: str
    brand: str
    model: str
    capacity_kg: float = Field(gt=0.0)
    programs: list[DryProgram] = Field(default_factory=list)
    options: list[DryerOption] = Field(default_factory=list)
    is_verified_model: bool = False


class MachineIdentifyRequest(WireModel):
    """What the user typed into Settings — nothing more."""

    brand: str = Field(min_length=1, max_length=100)
    model: str = Field(min_length=1, max_length=100)


class WasherIdentifyResponse(WireModel):
    result: WasherProfile
    diagnostics: ScanDiagnostics


class DryerIdentifyResponse(WireModel):
    result: DryerProfile
    diagnostics: ScanDiagnostics
