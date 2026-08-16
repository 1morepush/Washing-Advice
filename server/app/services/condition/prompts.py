"""What the reader is asked, and the shape it must answer in.

The prompt spends most of its length arguing *against* finding things, which is
the opposite of how these are usually written and is the whole difficulty of
this feature.

A model asked "what is wrong with this garment?" will answer, because that is
what the question invites. Shadows in the weave become pilling, a fold becomes
a stretched hem, the pattern near a seam becomes a tear. Every one of those
reports costs the user a moment of attention and, if accepted, changes how the
garment is washed from the next load onward. A reader that finds something on
every jumper is one people stop reading, and then they miss the hole.

So the instruction is that most garments are fine, and that saying so is the
right answer. The confidence number is the other half: the core drops anything
under its floor, which is only useful if the model actually spends the range.
A reader that reported everything at 0.9 would make the floor decorative.
"""

from __future__ import annotations

from typing import Any

from app.services.condition.base import ConditionRequest

CONDITION_PROMPT = """You are looking at photographs of one garment somebody
owns, to see whether it has worn.

**Most garments are fine.** Returning an empty list is the correct answer far
more often than not, and it is what you should return unless something is
genuinely visible. Do not go looking for a finding to justify the request.

Report only what you can actually see in these photographs:

- `fading` — colour visibly lost, especially unevenly or at the seams.
- `pilling` — small balls of fibre on the surface, usually where the garment
  rubs: underarms, inner thighs, cuffs.
- `hole` / `tear` — you can see through the fabric, or it has parted.
- `stain` — a mark that is not part of the pattern.
- `stretchedOut` — a cuff, neckline or waistband no longer holding shape.
- `shrunk` — visibly out of proportion for the garment type.
- `looseSeam` — stitching come away.
- `brokenFastener` — a missing button, a broken zip.

Do NOT report:

- `odour` — you cannot smell a photograph. Never return it.
- Anything you are inferring from the garment's age, type or fabric rather than
  seeing. A wool jumper is not pilling because wool pills.
- Creases, folds and the way it is lying. A garment photographed on a bed has
  shadows in it, and none of them are wear.
- The pattern. A deliberate distressed finish on denim is not a hole, and a
  printed mark is not a stain.

BE HONEST ABOUT `confidence`, and use the whole range:

- Above 0.8 only when it is unmistakable and well lit.
- Around 0.5-0.7 when you can see something but the photograph is not good
  enough to be sure what.
- Below 0.5 when you are essentially guessing — and prefer leaving it out
  entirely to reporting a guess.

The app hides anything you are not sure enough about, so a low number is not a
wasted answer. A high number on something that turns out to be a shadow is
worse than saying nothing at all, because it teaches the owner to ignore you.

Put *where* it is in `note`, in a few words — "along the inner sleeve", "at the
left cuff". That is what lets somebody look at the garment and check you.
"""

CONDITION_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "observed": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {
                        "type": "string",
                        "enum": [
                            "fading",
                            "pilling",
                            "hole",
                            "tear",
                            "stain",
                            "stretchedOut",
                            "shrunk",
                            "looseSeam",
                            "brokenFastener",
                        ],
                    },
                    "severity": {
                        "type": "string",
                        "enum": ["slight", "moderate", "severe"],
                    },
                    "confidence": {
                        "type": "number",
                        "description": "0 to 1. Be honest and use the whole range.",
                    },
                    "note": {
                        "type": "string",
                        "nullable": True,
                        "description": "Where on the garment, in a few words.",
                    },
                },
                "required": ["type", "severity", "confidence"],
            },
        },
    },
    "required": ["observed"],
}


def describe(request: ConditionRequest) -> str:
    """The prompt with this garment appended."""
    lines = [CONDITION_PROMPT, "", f"Garment: {request.garment}"]
    if request.fabric:
        lines.append(f"Fabric: {request.fabric}")
    if request.known:
        # So the model is not asked to re-find what the owner already knows,
        # and so "worse than last time" is a judgement it can actually make.
        lines.append(f"Already recorded: {request.known}")
    return "\n".join(lines)
