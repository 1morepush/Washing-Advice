"""Selling a garment on Depop, on the wire.

Mirrors `contracts/listing.schema.json`, which is the normative definition, and
the Dart side decodes exactly what is encoded here. Every constraint below is
one the schema states — a length, a count, a pattern — so a value this server
cannot construct is a value the schema would have refused, and a response that
gets as far as being built is one that validates.

Two kinds of model live here, and they are strict for different reasons.

The *request* models (`DescribeContext`, `PriceSearchRequest`) refuse an
unknown key, as the schema does. A misspelt `sizelabel` that was quietly ignored
would turn the seller's typed size back into a guess from a photograph, which is
the one thing the context exists to prevent.

The *response* models are checked at construction. Nothing the model wrote is
trusted to fit: the describers trim and drop what runs over (see
`services/selling/repair.py`) before building one of these, so a reading that
cannot be made to fit is an error the caller sees, not a field the app has to
guard against.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Annotated, Literal

from pydantic import AwareDatetime, ConfigDict, Field, StringConstraints, field_validator

from app.schemas.base import WireModel
from app.schemas.common import Confident
from app.schemas.scan import ScanDiagnostics
from app.schemas.wardrobe import ItemType

# --- Shared field types -----------------------------------------------------
#
# Named once so the same bound is not restated, with a chance to drift, on every
# model that carries it.

Title = Annotated[str, StringConstraints(strip_whitespace=True, min_length=3, max_length=80)]
SearchPhrase = Annotated[
    str, StringConstraints(strip_whitespace=True, min_length=3, max_length=120)
]
ColourName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=30)]
StyleWord = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=30)]
Flaw = Annotated[str, StringConstraints(strip_whitespace=True, min_length=3, max_length=120)]

TypedColour = Annotated[str, StringConstraints(strip_whitespace=True, max_length=30)]
"""A colour somebody typed. The schema bounds it above but not below, so a blank
one is accepted here and dropped by the model that holds it rather than refused."""

Money = Annotated[float, Field(gt=0, le=100_000)]
"""An amount in dollars. Only US dollars are carried; see the schema's `money`."""

HttpsUrl = Annotated[str, StringConstraints(pattern=r"^https://", max_length=2048)]


def _without_blanks(colours: list[str] | None) -> list[str] | None:
    """The colours that say something, or nothing at all if none do."""
    if not colours:
        return None
    return [colour for colour in colours if colour] or None


# --- describe: photographs in, a draft's facts out --------------------------


class SearchQueries(WireModel):
    """What to search for, one phrase per search.

    Written by the describe call and editable by the person before prices are
    looked up, so a wrong guess about the brand is a typo to fix rather than a
    wasted search.
    """

    model_config = ConfigDict(extra="forbid")

    depop: SearchPhrase
    retail: SearchPhrase


class ListingFacts(WireModel):
    """A draft of what a buyer needs to know, read from the photographs.

    Every optional field follows the scan contract's rule: absent means the
    photographs did not show it, never a guess presented as a reading. That is
    why `material` and `size_on_tag` have no fallback of any kind — a fabric
    guessed from a photograph is not something to sell a garment on.
    """

    title: Title
    item_type: ItemType
    brand: Confident[str] | None = None
    colors: Annotated[list[ColourName], Field(max_length=3)]
    material: Annotated[str, StringConstraints(max_length=120)] | None = None
    size_on_tag: Confident[str] | None = None
    style_words: Annotated[list[StyleWord], Field(max_length=6)]
    era: Annotated[str, StringConstraints(max_length=20)] | None = None
    visible_flaws: Annotated[list[Flaw], Field(max_length=5)]
    search_queries: SearchQueries


class DescribeResponse(WireModel):
    result: ListingFacts
    diagnostics: ScanDiagnostics


class KnownFacts(WireModel):
    """What the app already knows about a garment from the wardrobe.

    Outranks a fresh reading of the photographs: a brand somebody typed is not
    second-guessed from a swoosh-shaped print.
    """

    model_config = ConfigDict(extra="forbid")

    item_type: ItemType | None = None
    brand: Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)] | None = None
    colors: Annotated[list[TypedColour], Field(max_length=3)] | None = None
    material: Annotated[str, StringConstraints(strip_whitespace=True, max_length=120)] | None = None
    size_label: Annotated[str, StringConstraints(strip_whitespace=True, max_length=30)] | None = (
        None
    )

    @field_validator("brand", "material", "size_label", mode="after")
    @classmethod
    def _blank_is_unknown(cls, value: str | None) -> str | None:
        """Reads a blank as "the wardrobe does not know".

        A garment whose brand field was cleared sends `""`, and an empty string
        taken as a known brand would overwrite whatever the photographs show
        with nothing.
        """
        return value or None

    @field_validator("colors", mode="after")
    @classmethod
    def _no_blank_colours(cls, value: list[str] | None) -> list[str] | None:
        return _without_blanks(value)


class DescribeContext(WireModel):
    """The multipart field `context` of `POST /v1/sell/describe`, as JSON text."""

    model_config = ConfigDict(extra="forbid")

    known: KnownFacts | None = None
    notes: Annotated[str, StringConstraints(strip_whitespace=True, max_length=300)] | None = Field(
        default=None,
        description="Anything the person typed about it ('bought in 2019, worn twice').",
    )


# --- prices: search phrases in, comparable listings and retail prices out ----


class Comparable(WireModel):
    """A listing on Depop for the same or a similar item.

    Every one came back from a web search made for this request, and its price
    was found in the text of that page — a comparable the server cannot point to
    is dropped, not shown.
    """

    title: Annotated[str, StringConstraints(min_length=1, max_length=200)]
    url: HttpsUrl
    price: Money
    currency: Literal["USD"] = "USD"
    sold: bool | None = Field(
        default=None,
        description=(
            "True when the page says it sold, false when it is still for sale, "
            "absent when the page does not say."
        ),
    )
    condition: Annotated[str, StringConstraints(max_length=40)] | None = None
    match: Literal["same", "similar"]
    why: Annotated[str, StringConstraints(max_length=160)] | None = None


class RetailReference(WireModel):
    """What the same or a similar item costs new. Never from a resale site."""

    title: Annotated[str, StringConstraints(min_length=1, max_length=200)]
    url: HttpsUrl
    price: Money
    currency: Literal["USD"] = "USD"
    seller: Annotated[str, StringConstraints(max_length=80)] | None = None
    match: Literal["same", "similar"]


class ExcludedCounts(WireModel):
    """What the search found and the server would not show, by reason.

    Shown to the person so an empty list reads as "nothing usable" rather than
    "nothing looked".
    """

    not_usd: int = Field(ge=0)
    unverified_price: int = Field(ge=0)
    not_comparable: int = Field(ge=0)

    @classmethod
    def zero(cls) -> ExcludedCounts:
        return cls(not_usd=0, unverified_price=0, not_comparable=0)


class PriceSearchStatus(StrEnum):
    """How the search went. Never an HTTP error: a listing can be written without one."""

    OK = "ok"
    NOT_CONFIGURED = "notConfigured"
    QUOTA_EXCEEDED = "quotaExceeded"
    UNAVAILABLE = "unavailable"


class PriceSearch(WireModel):
    status: PriceSearchStatus
    searched_at: AwareDatetime | None = Field(
        default=None,
        description="When the search ran, so a price checked three weeks ago says so.",
    )
    provider: Annotated[str, StringConstraints(max_length=40)] | None = None
    queries: SearchQueries
    comparables: Annotated[list[Comparable], Field(max_length=12)]
    retail: Annotated[list[RetailReference], Field(max_length=6)]
    excluded: ExcludedCounts


class PriceSearchResponse(WireModel):
    result: PriceSearch
    diagnostics: ScanDiagnostics


class PriceSearchRequest(WireModel):
    """The body of `POST /v1/sell/prices`."""

    model_config = ConfigDict(extra="forbid")

    queries: SearchQueries
    item_type: ItemType
    title: Title
    brand: Annotated[str, StringConstraints(strip_whitespace=True, max_length=60)] | None = None
    colors: Annotated[list[TypedColour], Field(max_length=3)] | None = None

    @field_validator("brand", mode="after")
    @classmethod
    def _blank_brand_is_none(cls, value: str | None) -> str | None:
        return value or None

    @field_validator("colors", mode="after")
    @classmethod
    def _no_blank_colours(cls, value: list[str] | None) -> list[str] | None:
        return _without_blanks(value)
