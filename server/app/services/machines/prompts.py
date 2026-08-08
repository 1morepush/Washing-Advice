"""Prompts and response schemas for identifying a washer or dryer from its
brand and model name alone — no photograph, since there usually isn't one.

Unlike every other prompt in this service, there is nothing to look at: the
answer rests entirely on what the model already knows about that appliance
from its training data. That is why `identified` exists and is checked before
anything else in the reply — a plausible-sounding but invented cycle list is
worse than admitting the model doesn't recognise this one, because it gets
acted on against a real garment rather than merely displayed next to a photo
the user can double-check it against.
"""

from __future__ import annotations

from enum import Enum
from typing import Any

from app.schemas.care import Agitation, TumbleDryHeat
from app.schemas.machines import (
    DryerOption,
    DrynessControl,
    DryProgramKind,
    FabricClass,
    WasherOption,
    WashProgramKind,
)


def _values(enum_cls: type[Enum]) -> list[str]:
    """The wire values of an enum, for a response-schema `enum` list."""
    return [str(member.value) for member in enum_cls]


_IDENTIFIED = {
    "type": "boolean",
    "description": (
        "True only if you have specific, reliable knowledge of this exact "
        "make and model's real programme line-up — not a guess extrapolated "
        "from the brand in general. False if the model or brand is "
        "unfamiliar, too generic to pin down, or you are not confident. When "
        "false, every other field may be omitted."
    ),
}

_SUITABLE_FOR = {
    "type": "array",
    "items": {"type": "string", "enum": _values(FabricClass)},
}

_CAPACITY = {
    "type": "number",
    "description": "Rated dry-laundry capacity in kilograms.",
}

_DURATION = {"type": "integer", "description": "Typical duration in minutes."}

_MAX_LOAD_FRACTION = {
    "type": "number",
    "description": "Fraction of the machine's rated capacity this programme allows, 0 to 1.",
}

_DISPLAY_NAME = {
    "type": "string",
    "description": "Exactly what the dial or display calls this programme.",
}


WASHER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "identified": _IDENTIFIED,
        "capacityKg": _CAPACITY,
        "programs": {
            "type": "array",
            "description": "Every distinct named programme this machine offers.",
            "items": {
                "type": "object",
                "properties": {
                    "displayName": _DISPLAY_NAME,
                    "kind": {"type": "string", "enum": _values(WashProgramKind)},
                    "availableTempsC": {
                        "type": "array",
                        "items": {"type": "integer"},
                        "description": "Selectable temperatures in Celsius. 0 means cold.",
                    },
                    "defaultTempC": {"type": "integer"},
                    "agitation": {"type": "string", "enum": _values(Agitation)},
                    "spinSpeedsRpm": {
                        "type": "array",
                        "items": {"type": "integer"},
                        "description": "Selectable spin speeds. 0 means spin off.",
                    },
                    "suitableFor": _SUITABLE_FOR,
                    "maxLoadFraction": _MAX_LOAD_FRACTION,
                    "typicalDurationMinutes": _DURATION,
                },
                "required": ["displayName", "kind", "defaultTempC", "agitation"],
            },
        },
        "options": {
            "type": "array",
            "items": {"type": "string", "enum": _values(WasherOption)},
        },
    },
    "required": ["identified"],
}


WASHER_PROMPT = """\
You are being asked about a specific washing machine model, not a photograph.

The user typed a brand and model. Report its real programme line-up if — and
only if — you have specific, reliable knowledge of this exact appliance from
your training data. Set identified to false rather than extrapolating a
plausible-sounding line-up from the brand's other machines or from what
washing machines in general typically offer; a wrong guess here gets acted on
against a real garment, which makes it far worse than a vision guess that is
merely displayed and can be checked against a photo.

When you do know the machine, list every distinct named programme it has —
typically six to twelve — using the exact name printed on its dial or
display in displayName. kind classifies what the programme is for, using the
closest match; it does not need to match the display name.

availableTempsC and spinSpeedsRpm are the selectable values on that specific
programme, not the machine's overall range — a Delicates cycle rarely offers
the same spin ceiling as Cotton. 0 means "cold" for temperature and "no spin"
for spin.

Estimate capacityKg from the model if you know it; otherwise give a reasonable
estimate for that class of machine (a typical front loader is 7-9kg, a typical
top loader 10-13kg) rather than omitting it.
"""


DRYER_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "identified": _IDENTIFIED,
        "capacityKg": _CAPACITY,
        "programs": {
            "type": "array",
            "description": "Every distinct named programme this machine offers.",
            "items": {
                "type": "object",
                "properties": {
                    "displayName": _DISPLAY_NAME,
                    "kind": {"type": "string", "enum": _values(DryProgramKind)},
                    "availableHeats": {
                        "type": "array",
                        "items": {"type": "string", "enum": _values(TumbleDryHeat)},
                    },
                    "defaultHeat": {"type": "string", "enum": _values(TumbleDryHeat)},
                    "suitableFor": _SUITABLE_FOR,
                    "control": {
                        "type": "string",
                        "enum": _values(DrynessControl),
                        "description": "Moisture-sensor stop, or a fixed timed cycle.",
                    },
                    "maxLoadFraction": _MAX_LOAD_FRACTION,
                    "typicalDurationMinutes": _DURATION,
                },
                "required": ["displayName", "kind", "defaultHeat"],
            },
        },
        "options": {
            "type": "array",
            "items": {"type": "string", "enum": _values(DryerOption)},
        },
    },
    "required": ["identified"],
}


DRYER_PROMPT = """\
You are being asked about a specific tumble dryer model, not a photograph.

The same rule as for a washing machine applies: set identified to false
rather than extrapolating a plausible line-up from the brand in general,
since a wrong guess here gets acted on against a real garment. Report every
distinct named programme using the exact name on its dial or display, with
kind classifying what it is for.

availableHeats are the selectable heat settings on that specific programme,
not the machine's overall range. control is sensor when the cycle stops on a
moisture sensor and timed when it runs a fixed duration regardless of load —
most modern dryers offer both, on different programmes.

Estimate capacityKg from the model if you know it; otherwise a reasonable
estimate for that class of machine (a typical dryer is 7-9kg) rather than
omitting it.
"""
