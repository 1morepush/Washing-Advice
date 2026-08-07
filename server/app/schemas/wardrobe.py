"""Garment vocabulary, mirroring `wardrobe_core`'s wardrobe context.

These enums are the closed vocabulary the vision model must answer within, and
that constraint is the point. Asked openly "what garment is this?", a model
returns "sweatshirt" on one call and "hooded sweatshirt" on the next, and
neither maps to anything the domain core can act on.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import Field, RootModel, field_validator, model_validator

from app.schemas.base import WireModel


class ItemKind(StrEnum):
    GARMENT = "garment"
    FOOTWEAR = "footwear"
    BAG = "bag"
    ACCESSORY = "accessory"
    JEWELRY = "jewelry"
    LINEN = "linen"


class ItemType(StrEnum):
    """Every recognisable item type. Values match the Dart `ItemType` exactly."""

    T_SHIRT = "tShirt"
    LONG_SLEEVE_SHIRT = "longSleeveShirt"
    DRESS_SHIRT = "dressShirt"
    POLO_SHIRT = "poloShirt"
    BLOUSE = "blouse"
    TANK_TOP = "tankTop"
    SWEATER = "sweater"
    CARDIGAN = "cardigan"
    HOODIE = "hoodie"
    SWEATSHIRT = "sweatshirt"
    JEANS = "jeans"
    TROUSERS = "trousers"
    CHINOS = "chinos"
    SHORTS = "shorts"
    SKIRT = "skirt"
    LEGGINGS = "leggings"
    DRESS = "dress"
    JUMPSUIT = "jumpsuit"
    JACKET = "jacket"
    BLAZER = "blazer"
    COAT = "coat"
    VEST = "vest"
    UNDERWEAR = "underwear"
    BRA = "bra"
    SOCKS = "socks"
    TIGHTS = "tights"
    PAJAMAS = "pajamas"
    ROBE = "robe"
    ACTIVEWEAR_TOP = "activewearTop"
    ACTIVEWEAR_BOTTOM = "activewearBottom"
    SWIMWEAR = "swimwear"
    SCARF = "scarf"
    HAT = "hat"
    GLOVES = "gloves"
    BELT = "belt"
    TIE = "tie"
    SNEAKERS = "sneakers"
    BOOTS = "boots"
    DRESS_SHOES = "dressShoes"
    SANDALS = "sandals"
    HANDBAG = "handbag"
    BACKPACK = "backpack"
    HAND_TOWEL = "handTowel"
    BATH_TOWEL = "bathTowel"
    BED_SHEET = "bedSheet"
    PILLOWCASE = "pillowcase"
    DUVET_COVER = "duvetCover"
    BLANKET = "blanket"
    OTHER = "other"


class Fiber(StrEnum):
    COTTON = "cotton"
    LINEN = "linen"
    HEMP = "hemp"
    RAMIE = "ramie"
    WOOL = "wool"
    CASHMERE = "cashmere"
    SILK = "silk"
    VISCOSE = "viscose"
    MODAL = "modal"
    LYOCELL = "lyocell"
    ACETATE = "acetate"
    POLYESTER = "polyester"
    NYLON = "nylon"
    ACRYLIC = "acrylic"
    ELASTANE = "elastane"
    DOWN = "down"
    LEATHER = "leather"
    OTHER = "other"


class Pattern(StrEnum):
    SOLID = "solid"
    STRIPED = "striped"
    CHECKED = "checked"
    PLAID = "plaid"
    FLORAL = "floral"
    POLKA_DOT = "polkaDot"
    GRAPHIC = "graphic"
    CAMOUFLAGE = "camouflage"
    ANIMAL_PRINT = "animalPrint"
    COLOR_BLOCK = "colorBlock"
    HEATHERED = "heathered"
    OTHER = "other"


class SleeveLength(StrEnum):
    SLEEVELESS = "sleeveless"
    SHORT_SLEEVE = "shortSleeve"
    THREE_QUARTER = "threeQuarter"
    LONG_SLEEVE = "longSleeve"


class Season(StrEnum):
    SPRING = "spring"
    SUMMER = "summer"
    AUTUMN = "autumn"
    WINTER = "winter"
    ALL_SEASON = "allSeason"


class Fit(StrEnum):
    SLIM = "slim"
    REGULAR = "regular"
    RELAXED = "relaxed"
    OVERSIZED = "oversized"


class StyleCut(StrEnum):
    MENS = "mens"
    WOMENS = "womens"
    UNISEX = "unisex"
    KIDS = "kids"


class FabricComposition(RootModel[dict[Fiber, int]]):
    """Fibre percentages by weight, as printed on a label.

    A `RootModel` so it serialises as a bare object — `{"cotton": 80,
    "polyester": 20}` — exactly matching the Dart `FabricComposition.toJson`
    and `contracts/scan_results.schema.json`. Wrapping it in a named field
    would have been the obvious Pydantic shape and the wrong wire shape.
    """

    root: dict[Fiber, int] = Field(default_factory=dict)

    @field_validator("root")
    @classmethod
    def _check_and_drop_zeroes(cls, value: dict[Fiber, int]) -> dict[Fiber, int]:
        for fiber, percent in value.items():
            if not 0 <= percent <= 100:
                raise ValueError(f"{fiber.value} is {percent}%, outside 0..100")
        return {fiber: pct for fiber, pct in value.items() if pct > 0}

    @property
    def percentages(self) -> dict[Fiber, int]:
        return self.root

    @property
    def total(self) -> int:
        return sum(self.root.values())

    @property
    def is_plausible(self) -> bool:
        """Whether the percentages total something a real label could show.

        A tolerance of 2 points absorbs rounding and minor OCR slips; further out
        suggests the scan was misread and should be re-checked rather than
        trusted.
        """
        return bool(self.root) and abs(self.total - 100) <= 2


class ItemColor(WireModel):
    """A colour in CIELAB (D65), with the share of the garment it covers.

    CIELAB rather than RGB because the core compares colours perceptually with
    CIEDE2000 — RGB distance rates dark navy and dark brown as far apart while
    calling two obviously different pastels close, which mis-sorts laundry.
    """

    l: float = Field(ge=0.0, le=100.0)  # noqa: E741 — CIE L*, the standard name
    a: float = Field(ge=-128.0, le=128.0)
    b: float = Field(ge=-128.0, le=128.0)
    coverage: float = Field(default=1.0, ge=0.0, le=1.0)
    name: str | None = None


class ColorPalette(RootModel[list[ItemColor]]):
    """The colours on one garment, ordered by coverage, largest first.

    A `RootModel` for the same reason as [FabricComposition] — the wire shape is
    a bare array, matching the Dart `ColorPalette.toJson`.
    """

    root: list[ItemColor] = Field(default_factory=list)

    @model_validator(mode="after")
    def _sort_by_coverage(self) -> ColorPalette:
        self.root.sort(key=lambda c: c.coverage, reverse=True)
        return self

    @property
    def colors(self) -> list[ItemColor]:
        return self.root

    @property
    def dominant(self) -> ItemColor | None:
        return self.root[0] if self.root else None
