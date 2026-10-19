"""What the describer is asked, and the shape it must answer in.

The prompt is written against one failure: a listing that says something the
garment does not bear out. A buyer who is told "100% wool" and receives acrylic,
or a medium that turns out to be a small, asks for a refund and leaves a review,
and the seller never knew the claim was in their listing because a draft wrote
it. So most of this prompt argues for leaving things out. A gap costs the seller
a few seconds typing; a confident wrong fact costs them a sale.

That is also why the two fields that look most useful to guess — material and
size — are the two the prompt forbids guessing hardest. They are checked against
nothing here; the only defence is the model not writing them, so the reasons are
given rather than just the rule.

The response schema uses Gemini's OpenAPI subset, like the other prompts:
`type`, `properties`, `required`, `enum`, `items`, `nullable`.
"""

from __future__ import annotations

from enum import Enum
from typing import Any

from app.schemas.wardrobe import ItemType
from app.services.selling.base import DescribeRequest


def _values(enum_cls: type[Enum]) -> list[str]:
    return [str(member.value) for member in enum_cls]


LISTING_PROMPT = """\
You are writing the facts for a second-hand listing on Depop, from photographs of
one garment. The seller will check and correct what you write before anything is
posted, and a buyer who is told something the garment does not bear out will ask
for a refund. So report what these photographs show, and leave out what they do
not. A gap is cheap, because the seller fills it in. A wrong fact is not.

SEVERAL PHOTOGRAPHS ARE ONE GARMENT. Return one reading covering all of them,
never one per photograph. They may be in any order and the first is not
necessarily the front. A close-up of a label is evidence about the garment, and
so is a flaw that shows in only one shot. Never describe a side you were not
shown.

TITLE: the brand, the item, then the words a buyer types into Depop's search
box, most important first: "Nike vintage crewneck sweatshirt grey". At most 80
characters. Depop search matches the words in the title, so every word that is
not a search word is a search lost. No hype ("stunning", "amazing", "rare find",
"must have"), no emoji, no decoration, no size and no price. With no legible
brand, start with the item.

BRAND: only from a logo or a brand label you can actually read in these
photographs. A swoosh-shaped print is not a Nike logo, and a brand inferred from
styling is one a buyer can hold the seller to. Give `brandConfidence` honestly:
around 0.9 for a label you read, around 0.5 for a logo you can only half make
out. Omit the brand rather than guess. The app asks the seller to confirm what
you are unsure about and trusts what you are sure about, so a confident guess is
the worst thing you can return here.

MATERIAL: only if a care or composition label is photographed and legible, and
then as the label states it ("80% cotton, 20% polyester"). Never from how the
fabric looks or would feel. A buyer told "100% wool" who receives acrylic is a
refund and a bad review. If no composition label is in the photographs, omit
`material` entirely. That is the right answer, not a failure.

SIZE: only from a size label that is photographed, exactly as it is printed
("M", "W32 L30", "UK 10"). Never from how the garment sits on a bed or a hanger.
Size is the commonest reason a sale is returned, and a size read off a flat-lay
is wrong about as often as it is right. If no size label is in the photographs,
omit `sizeOnTag` entirely. Give `sizeConfidence` honestly when you do report it.

COLOURS: plain colour names a buyer filters by ("Grey", "Navy", "Cream"), with
the dominant one first and at most three. Not hex codes, and not shades such as
"heather charcoal": the filter has to match the word.

STYLE WORDS: words a buyer would search for, such as the cut ("crewneck",
"oversized", "boxy"), the era ("90s"), the style ("streetwear", "gorpcore") or
the print ("embroidered logo", "graphic"). At most six. Never the brand, which
has its own field, and never filler ("nice", "cool", "great"): a search word is
something a stranger would type, and filler is not.

ERA: only when the photographs show it, from a dated label or an unmistakable
cut. A purchase date is not an era. Omit it otherwise.

FLAWS: what a buyer would complain about, said plainly and with where it is:
"small mark on the left cuff", "cracking on the print". Look at the cuffs,
collar, hem, underarms, knees and seams, and at any print or logo. An empty list
is the right answer when you can see none. It is not a promise that there are
none, only a statement of what these photographs show, and the seller adds the
rest. Do not invent a flaw to look thorough.

SEARCH PHRASES, two of them, each a short phrase and not a sentence:
  depopSearch  what a buyer would type into Depop to find this exact item.
  retailSearch the product name you would search to find what this costs new,
               in the brand's own naming where you recognise the product
               ("Nike Club Fleece crew sweatshirt"). Without a recognisable
               product, the item described plainly.
They are not the title. They are what the app searches for, and the seller can
edit them before it does.
"""

LISTING_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "title": {
            "type": "string",
            "description": "Brand, item, search words. At most 80 characters. No hype.",
        },
        "itemType": {"type": "string", "enum": _values(ItemType)},
        "brand": {
            "type": "string",
            "nullable": True,
            "description": "Only from a legible logo or brand label. Omit otherwise.",
        },
        "brandConfidence": {
            "type": "number",
            "description": "0 to 1. Honest: a guess is better reported low than omitted high.",
        },
        "colors": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Plain colour names, dominant first. At most three.",
        },
        "material": {
            "type": "string",
            "nullable": True,
            "description": "As a photographed composition label states it. Omit otherwise.",
        },
        "sizeOnTag": {
            "type": "string",
            "nullable": True,
            "description": "As printed on a photographed size label. Omit otherwise.",
        },
        "sizeConfidence": {"type": "number", "description": "0 to 1."},
        "styleWords": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Search words: cut, era, style, print. No brand or filler. At most six.",
        },
        "era": {
            "type": "string",
            "nullable": True,
            "description": "Only when a photograph shows it, e.g. '90s'.",
        },
        "visibleFlaws": {
            "type": "array",
            "items": {"type": "string"},
            "description": "What a buyer would complain about, with where. Empty if none visible.",
        },
        "depopSearch": {
            "type": "string",
            "description": "What a buyer would type into Depop to find this item.",
        },
        "retailSearch": {
            "type": "string",
            "description": "The product name to search for its price new.",
        },
    },
    "required": [
        "title",
        "itemType",
        "colors",
        "styleWords",
        "visibleFlaws",
        "depopSearch",
        "retailSearch",
    ],
}


def describe(request: DescribeRequest) -> str:
    """The prompt with what the seller already knows appended.

    The known facts are stated as given and as outranking the photographs,
    because that is how the result treats them afterwards. Saying so here as
    well means the title and the search phrases are written around them rather
    than around a reading they are about to be laid over.
    """
    lines = [LISTING_PROMPT]

    known = request.known
    if known is not None:
        given: list[str] = []
        if known.item_type:
            given.append(f"Item type: {known.item_type.value}")
        if known.brand:
            given.append(f"Brand: {known.brand}")
        if known.colors:
            given.append(f"Colours: {', '.join(known.colors)}")
        if known.material:
            given.append(f"Material, from the care label: {known.material}")
        if known.size_label:
            given.append(f"Size, from the size label: {known.size_label}")
        if given:
            lines.append("")
            lines.append(
                "THE SELLER ALREADY KNOWS THESE. They outrank anything you see in "
                "the photographs, so use them as given in the title and the search "
                "phrases and never contradict them:"
            )
            lines.extend(f"- {fact}" for fact in given)

    notes = request.context.notes if request.context else None
    if notes:
        lines.append("")
        lines.append(
            "The seller's own note is background, not text for the listing. Do not "
            "copy it into the title. If it names a flaw, list that flaw. Do not turn "
            "a purchase date or a count of wears into an era:"
        )
        lines.append(f'"{notes}"')

    return "\n".join(lines)
