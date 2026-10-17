"""A deterministic describer, for tests and for running without a key.

Derived from a hash of the first photograph, like the other fakes, so one image
always reads the same way and different images read differently — a fake that
returned one canned draft would make every screen test look like it passed for
the wrong reason.

And it varies on purpose in the ways the real reading does. Some drafts have no
brand, no material, no size, no era and no flaws, because that is the commonest
real answer for a photograph with no label in it, and a screen that has only
ever been drawn with a full draft has not been drawn at all.

It honours the seller's known facts by the same function the real describer
uses, so the rule that a typed brand wins is exercised in every run without a
key rather than only against a mocked model.
"""

from __future__ import annotations

import hashlib

from app.schemas.common import Confident, Provenance
from app.schemas.selling import ListingFacts, SearchQueries
from app.schemas.wardrobe import ItemType
from app.services.selling.base import DescribeRequest
from app.services.selling.known import apply_known

_ITEMS: tuple[tuple[ItemType, str, str, tuple[str, ...]], ...] = (
    # (type, how a title says it, how a shop names it, search words)
    (
        ItemType.SWEATSHIRT,
        "crewneck sweatshirt",
        "crew sweatshirt",
        ("crewneck", "embroidered logo"),
    ),
    (ItemType.HOODIE, "pullover hoodie", "pullover hoodie", ("pullover", "oversized")),
    (ItemType.JEANS, "straight leg jeans", "straight jeans", ("straight leg", "denim")),
    (ItemType.T_SHIRT, "graphic t-shirt", "t-shirt", ("graphic", "boxy")),
    (ItemType.JACKET, "bomber jacket", "bomber jacket", ("bomber", "zip up")),
    (ItemType.DRESS, "midi dress", "midi dress", ("midi", "floral")),
)

_COLOURS: tuple[str, ...] = ("Grey", "Black", "Navy", "White", "Green")
_BRANDS: tuple[str | None, ...] = ("Nike", "Levi's", "Champion", "Carhartt", None)
_SIZES: tuple[str, ...] = ("S", "M", "L", "W32 L30")


class FakeListingDescriber:
    @property
    def name(self) -> str:
        return "fake"

    async def describe(self, request: DescribeRequest) -> ListingFacts:
        # Seeded from the first photograph, so a second one does not change the
        # reading of a garment the tests already pin.
        seed = int.from_bytes(hashlib.sha256(request.images[0].data).digest()[:4], "big")

        item_type, noun, shop_noun, words = _ITEMS[seed % len(_ITEMS)]
        colour = _COLOURS[(seed >> 3) % len(_COLOURS)]
        brand = _BRANDS[(seed >> 6) % len(_BRANDS)]
        era = "90s" if (seed >> 9) % 4 == 0 else None
        material = "80% cotton, 20% polyester" if (seed >> 11) % 3 == 0 else None
        size = _SIZES[(seed >> 13) % len(_SIZES)] if (seed >> 15) % 2 == 0 else None
        flaws = ["small mark on the left cuff"] if (seed >> 16) % 3 == 0 else []

        title = " ".join(part for part in (brand, era, noun, colour.lower()) if part)
        retail = " ".join(part for part in (brand, shop_noun, colour.lower()) if part)

        facts = ListingFacts(
            title=title,
            item_type=item_type,
            brand=(
                Confident[str](value=brand, confidence=0.9, source=Provenance.AI_INFERENCE)
                if brand
                else None
            ),
            colors=[colour],
            material=material,
            size_on_tag=(
                Confident[str](value=size, confidence=0.85, source=Provenance.AI_INFERENCE)
                if size
                else None
            ),
            style_words=[*words, *([era] if era else [])],
            era=era,
            visible_flaws=flaws,
            search_queries=SearchQueries(depop=title, retail=retail),
        )
        return apply_known(facts, request.known)
