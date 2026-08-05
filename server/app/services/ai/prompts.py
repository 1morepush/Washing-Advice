"""Prompts and response schemas for structured extraction.

Kept in one file because the prompt and the schema are a pair: neither is
meaningful without the other, and changing one without the other is how a
provider starts silently returning fields nobody reads.

The response schemas use Gemini's OpenAPI subset — `type`, `properties`,
`required`, `enum`, `items`, `nullable`. No `$ref`, no `oneOf`, so shared
fragments are built by the helpers below rather than referenced.
"""

from __future__ import annotations

from enum import Enum
from typing import Any

from app.schemas.care import (
    Agitation,
    BleachAllowance,
    CareWarning,
    CleaningSolvent,
    IronTemperature,
    NaturalDryMethod,
    TumbleDryHeat,
    WashMethod,
)
from app.schemas.wardrobe import (
    Fiber,
    Fit,
    ItemType,
    Pattern,
    Season,
    SleeveLength,
    StyleCut,
)


def _values(enum_cls: type[Enum]) -> list[str]:
    """The wire values of an enum, for a response-schema `enum` list."""
    return [str(member.value) for member in enum_cls]


_CONFIDENCE = {
    "type": "number",
    "description": "0 to 1. Be honest — a low number is far more useful than a confident guess.",
}

_COLORS = {
    "type": "array",
    "description": "Colours present, most-covering first. At most three.",
    "items": {
        "type": "object",
        "properties": {
            "hex": {
                "type": "string",
                "description": "Six-digit hex, e.g. #1F2A44. Always hex, never a colour name.",
            },
            "coverage": {
                "type": "number",
                "description": "Fraction of the garment showing this colour, 0 to 1.",
            },
            "name": {"type": "string", "description": "Plain name, e.g. 'Navy'."},
        },
        "required": ["hex", "coverage"],
    },
}

_COMPOSITION = {
    "type": "array",
    "description": "Fibre percentages, only if actually legible.",
    "items": {
        "type": "object",
        "properties": {
            "fiber": {"type": "string", "enum": _values(Fiber)},
            "percent": {"type": "integer"},
        },
        "required": ["fiber", "percent"],
    },
}


def _garment_properties() -> dict[str, Any]:
    return {
        "type": {"type": "string", "enum": _values(ItemType)},
        "typeConfidence": _CONFIDENCE,
        "colors": _COLORS,
        "colorConfidence": _CONFIDENCE,
        "composition": _COMPOSITION,
        "compositionConfidence": _CONFIDENCE,
        "brand": {
            "type": "string",
            "description": "Only if a logo or label is legible.",
        },
        "brandConfidence": _CONFIDENCE,
        "pattern": {"type": "string", "enum": _values(Pattern)},
        "patternConfidence": _CONFIDENCE,
        "sleeveLength": {"type": "string", "enum": _values(SleeveLength)},
        "fit": {"type": "string", "enum": _values(Fit)},
        "styleCut": {"type": "string", "enum": _values(StyleCut)},
        "seasons": {
            "type": "array",
            "items": {"type": "string", "enum": _values(Season)},
        },
        "suggestedName": {
            "type": "string",
            "description": "Short natural name, e.g. 'Grey Nike hoodie'.",
        },
        "distinguishingText": {
            "type": "string",
            "description": "Any text or slogan printed on the garment itself.",
        },
    }


GARMENT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": _garment_properties(),
    "required": ["type", "typeConfidence"],
}


GARMENT_PROMPT = """\
You are identifying a single item of clothing from photographs, for a wardrobe app.

Report only what you can actually see. If the brand is not legible, omit it — do
not infer a brand from styling. If the fibre content is not printed anywhere in
the image, omit composition entirely rather than guessing from appearance; a
guess here can lead to a garment being washed at a temperature that destroys it.

Confidence values must be honest. A 0.4 that turns out right is far more useful
to this app than a 0.95 that turns out wrong, because the app asks the user to
confirm anything it is unsure about and silently trusts anything it is not.

Colours must be six-digit hex codes sampled from the garment itself, not from
shadows or the background. List at most three, most-covering first.

If text or a slogan is printed on the garment, report it in distinguishingText —
it is the single most useful signal for telling two similar garments apart later.
"""


CARE_TAG_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "instructions": {
            "type": "object",
            "properties": {
                "method": {"type": "string", "enum": _values(WashMethod)},
                "maxTempC": {"type": "integer"},
                "agitation": {"type": "string", "enum": _values(Agitation)},
                "bleach": {"type": "string", "enum": _values(BleachAllowance)},
                "tumbleDryAllowed": {"type": "boolean"},
                "tumbleDryHeat": {"type": "string", "enum": _values(TumbleDryHeat)},
                "naturalDry": {"type": "string", "enum": _values(NaturalDryMethod)},
                "dryInShade": {"type": "boolean"},
                "doNotWring": {"type": "boolean"},
                "ironTemperature": {"type": "string", "enum": _values(IronTemperature)},
                "steamAllowed": {"type": "boolean"},
                "doNotDryClean": {"type": "boolean"},
                "solvent": {"type": "string", "enum": _values(CleaningSolvent)},
                "warnings": {
                    "type": "array",
                    "items": {"type": "string", "enum": _values(CareWarning)},
                },
            },
        },
        "confidence": _CONFIDENCE,
        "composition": _COMPOSITION,
        "compositionConfidence": _CONFIDENCE,
        "symbolsFound": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Identifiers of symbols you decoded, e.g. 'wash.30'.",
        },
        "unreadableSymbolCount": {
            "type": "integer",
            "description": "Symbols clearly present but which you could not decode.",
        },
        "rawText": {"type": "string", "description": "All text visible on the label."},
    },
    "required": ["instructions", "confidence"],
}


CARE_TAG_PROMPT = """\
You are reading a clothing care label and translating its ISO 3758 symbols into
structured data.

THE MOST IMPORTANT RULE: omit any field you cannot actually read. If the drying
symbol is creased, faded, cut off or absent, leave `tumbleDryAllowed` out of the
response entirely. Do not substitute a sensible default and do not infer it from
the fabric.

This matters because of what happens downstream. An omitted field means "the
label did not say", and the app fills it from a conservative rule table. A field
you supply means "the manufacturer stated this", and it overrides those rules. A
guessed `tumbleDryAllowed: true` is therefore not a small inaccuracy — it is the
app being told the manufacturer approved a tumble dryer, and it is how a wool
blend gets ruined.

A SECOND RULE THAT IS EASY TO GET WRONG: a wash tub with NO bars beneath it
means normal agitation. That is a stated fact, not an absent one, so report
`agitation: "normal"`. One bar means "mild", two bars mean "veryMild". Only omit
agitation if the tub symbol itself is unreadable.

Count every symbol that is visibly present but which you could not decode in
`unreadableSymbolCount`. The app uses it to tell the user that part of their
label could not be read, which is far better than silently returning a partial
answer as though it were complete.

Transcribe fibre percentages only if they are printed and legible.
"""


PILE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    **_garment_properties(),
                    "boundingBox": {
                        "type": "object",
                        "properties": {
                            "left": {"type": "number"},
                            "top": {"type": "number"},
                            "width": {"type": "number"},
                            "height": {"type": "number"},
                        },
                        "required": ["left", "top", "width", "height"],
                    },
                    "detectionConfidence": _CONFIDENCE,
                },
                "required": [
                    "type",
                    "typeConfidence",
                    "boundingBox",
                    "detectionConfidence",
                ],
            },
        },
        "partiallyObscuredCount": {
            "type": "integer",
            "description": "Garments visible but too buried to identify.",
        },
    },
    "required": ["items"],
}


PILE_PROMPT = """\
You are looking at a pile of laundry and identifying the separate garments in it.

Report one entry per distinct garment you can identify. Bounding boxes are in
normalised coordinates from the top-left, so every value is between 0 and 1.

Do not report the same garment twice. A sleeve and the shirt it belongs to are
one garment, not two.

Count garments that are clearly present but too buried or overlapped to identify
in `partiallyObscuredCount`, and leave them out of `items`. The app tells the
user to reshuffle the pile and rescan, which is far more useful than a confident
guess about a shape under three other things.

Per-garment fields follow the same rules as a single-garment scan: omit anything
you cannot actually see, and keep confidences honest — the app confirms low
confidence items with the user and silently trusts high ones.
"""
