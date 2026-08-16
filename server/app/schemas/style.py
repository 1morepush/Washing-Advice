"""Asking for outfit ideas, on the wire.

Text rather than photographs, and that is the design rather than a shortcut.
The wardrobe already holds what a stylist needs as structured facts — type,
colour, pattern, fit, fabric — read once when each garment was scanned. Sending
forty photographs to re-derive them would cost a multiple of the time and money
for facts the app is already surer about than a fresh glance would be.

What comes back names item ids and gives a reason. Neither is trusted: the ids
are resolved against the wardrobe and the outfit is checked for structural
sense by `StyleVetting` in the core before anything reaches a screen. The reason
is passed through untouched, because the judgement is the thing being asked for.
"""

from __future__ import annotations

from pydantic import Field

from app.schemas.base import WireModel
from app.schemas.scan import ScanDiagnostics


class StyleCandidate(WireModel):
    """One garment, as the stylist is told about it.

    Deliberately not the full wardrobe item. A stylist needs what a garment
    looks like and roughly how formal it is; it has no use for wash
    temperatures, purchase prices or event history, and every field sent is
    tokens spent and one more thing to keep in step across two languages.
    """

    id: str
    name: str
    type: str = Field(description="Garment type, e.g. 'Dress shirt'.")
    category: str = Field(description="Where it sits on the body, e.g. 'Tops'.")
    colors: list[str] = Field(
        default_factory=list,
        description="Plain colour names, most-covering first.",
    )
    fabric: str | None = Field(default=None, description="e.g. '100% Cotton'.")
    pattern: str | None = None
    fit: str | None = None
    brand: str | None = None


class StyleRequest(WireModel):
    """The wardrobe to choose from, and what the outfits are for."""

    occasion: str = Field(description="e.g. 'work', 'everyday', 'evening'.")
    season: str | None = None
    count: int = Field(default=4, ge=1, le=8)
    wardrobe: list[StyleCandidate]
    note: str | None = Field(
        default=None,
        description="Anything the user added, e.g. 'it will be cold'.",
    )


class ProposedOutfit(WireModel):
    """One outfit, named by ids the caller supplied."""

    item_ids: list[str]
    rationale: str = Field(
        description="Why these go together, in one or two sentences.",
    )


class StyleResponse(WireModel):
    """Wrapped in `result` like every other endpoint's answer."""

    result: list[ProposedOutfit]
    diagnostics: ScanDiagnostics | None = None
