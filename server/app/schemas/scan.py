"""The scan results this server produces — the API's contract with the app.

Mirrors the `vision` context in `wardrobe_core`: the core defines what a scan
must produce, and this is the wire form of it.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import Field, field_validator

from app.schemas.base import WireModel
from app.schemas.care import CareConstraint
from app.schemas.common import BoundingBox, Confident
from app.schemas.limits import (
    MAX_BRAND,
    MAX_COUNTRY,
    MAX_NAME,
    MAX_PRINTED_TEXT,
    MAX_RAW_TEXT,
    clamp,
)
from app.schemas.wardrobe import (
    ColorPalette,
    FabricComposition,
    Fit,
    ItemType,
    Pattern,
    Season,
    SleeveLength,
    StyleCut,
)


class ScanKind(StrEnum):
    """What a caller is asking the pipeline to do."""

    GARMENT = "garment"
    CARE_TAG = "careTag"
    PILE = "pile"


class GarmentScanResult(WireModel):
    """What identifying a single garment produces."""

    type: Confident[ItemType]
    colors: Confident[ColorPalette] | None = None
    composition: Confident[FabricComposition] | None = None
    brand: Confident[str] | None = None
    pattern: Confident[Pattern] | None = None
    sleeve_length: Confident[SleeveLength] | None = Field(default=None)
    fit: Confident[Fit] | None = None
    style_cut: Confident[StyleCut] | None = Field(default=None)
    seasons: list[Season] = Field(default_factory=list)

    suggested_name: str | None = Field(
        default=None,
        description="A name to prefill, e.g. 'Grey Nike hoodie'.",
    )
    distinguishing_text: str | None = Field(
        default=None,
        description=(
            "Text printed on the garment. Unusually discriminating for "
            "re-identification: two black t-shirts are hard to tell apart "
            "until one of them says 'Nirvana'."
        ),
    )

    @field_validator("suggested_name", mode="after")
    @classmethod
    def _short_name(cls, value: str | None) -> str | None:
        """Keeps a name to a name.

        Applied here rather than in the Gemini provider so it covers every
        provider and holds at the contract, which is where the app's trust in
        this field actually begins. See `schemas/limits.py` for why a runaway
        is trimmed rather than refused.
        """
        return clamp(value, MAX_NAME)

    @field_validator("distinguishing_text", mode="after")
    @classmethod
    def _short_printed_text(cls, value: str | None) -> str | None:
        return clamp(value, MAX_PRINTED_TEXT)

    @field_validator("brand", mode="after")
    @classmethod
    def _short_brand(cls, value: Confident[str] | None) -> Confident[str] | None:
        if value is None:
            return None
        shortened = clamp(value.value, MAX_BRAND)
        # A brand that was only whitespace is no brand, and passing it on as an
        # empty string would put a blank chip on the item screen.
        if shortened is None:
            return None
        return value.model_copy(update={"value": shortened})


class CareTagScanResult(WireModel):
    """What reading a care label produces."""

    instructions: CareConstraint
    confidence: float = Field(ge=0.0, le=1.0)
    composition: Confident[FabricComposition] | None = None
    country_of_origin: Confident[str] | None = None
    symbols_found: list[str] = Field(default_factory=list)
    unreadable_symbol_count: int = Field(
        default=0,
        ge=0,
        description=(
            "Symbols visible but not interpretable. Lets the app honestly say "
            "part of the label could not be read, rather than presenting an "
            "incomplete answer as a complete one."
        ),
    )
    raw_text: str | None = Field(default=None)
    language: str | None = Field(
        default=None,
        description=(
            "ISO 639-1 code of the words on the label, if any were legible. "
            "The symbols are ISO 3758 and mean the same everywhere, so a label "
            "with none of this is a symbols-only label rather than a failure."
        ),
    )

    @field_validator("raw_text", mode="after")
    @classmethod
    def _bounded_raw_text(cls, value: str | None) -> str | None:
        return clamp(value, MAX_RAW_TEXT)

    @field_validator("country_of_origin", mode="after")
    @classmethod
    def _short_country(cls, value: Confident[str] | None) -> Confident[str] | None:
        # This one is filtered and sorted on, not just displayed: a runaway
        # here becomes a permanent row in the insights chart and an entry in
        # the filter sheet that matches one garment forever.
        if value is None:
            return None
        shortened = clamp(value.value, MAX_COUNTRY)
        if shortened is None:
            return None
        return value.model_copy(update={"value": shortened})

    @property
    def is_complete(self) -> bool:
        return self.unreadable_symbol_count == 0


class DetectedItem(WireModel):
    """One garment located within a photo of a pile."""

    scan: GarmentScanResult
    bounding_box: BoundingBox = Field()
    detection_confidence: float = Field(
        ge=0.0,
        le=1.0,
        description=(
            "How sure the model is that this is a distinct garment — separate "
            "from how sure it is about the garment's attributes."
        ),
    )


class PileScanResult(WireModel):
    """What scanning a whole pile produces."""

    items: list[DetectedItem] = Field(default_factory=list)
    partially_obscured_count: int = Field(
        default=0,
        ge=0,
        description=(
            "Garments visible but too obscured to identify. Reported rather "
            "than hidden, so the user can reshuffle the pile and rescan."
        ),
    )

    @property
    def count(self) -> int:
        return len(self.items)


class ScanDiagnostics(WireModel):
    """How a result was arrived at.

    Returned with every scan so the pipeline is observable in production: which
    stages ran, which answered, and whether the answer came from memory rather
    than a paid model call.
    """

    stages_run: list[str] = Field(default_factory=list)
    stage_answered: str | None = Field(default=None)
    served_from_cache: bool = False
    elapsed_ms: int = Field(default=0, ge=0)


class GarmentScanResponse(WireModel):
    result: GarmentScanResult
    diagnostics: ScanDiagnostics


class CareTagScanResponse(WireModel):
    result: CareTagScanResult
    diagnostics: ScanDiagnostics


class PileScanResponse(WireModel):
    result: PileScanResult
    diagnostics: ScanDiagnostics
