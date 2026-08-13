"""What the model is asked, and the shape it must answer in.

The prompt spends most of its length on one instruction: **state the checkable
facts**. The app refuses steps its garment's care forbids, and it can only do
that from the structured fields — a step that says "soak in hot water" and
leaves `temperatureC` null is a step nothing can vet, so it passes straight
through to a user with a wool jumper. Prose alone is the failure mode this
whole design exists to prevent, and the prompt has to say so explicitly because
the natural way to write an instruction is as a sentence.

The model is also told not to do the safety reasoning itself. It does not know
this garment's care label — only a summary — and a model that started dropping
its own steps would produce a shorter answer for the wrong reasons and hide the
refusal from the person who needs to see it.
"""

from __future__ import annotations

from typing import Any

STAIN_PROMPT = """You are advising on removing a stain from a specific garment.

Give an ordered sequence of steps someone can follow right now, at home. Be
concrete: name the agent, the water temperature, and how long to leave it.
Prefer the treatment that is standard for this substance on this fibre.

State the checkable facts on every step, not just in the sentence:

- `temperatureC` whenever the step involves water at a stated temperature. Use
  20 for a cold tap, 30-40 for warm. If a step names no temperature, leave it
  null.
- `bleach` whenever the step uses one: "chlorine" for household/sodium
  hypochlorite bleach, "oxygen" for percarbonate or peroxide-based bleach.
- `isMachineWash` true for any step that puts the garment through a machine.
- `abrades` true for any step that rubs, scrubs, brushes or works the fabric.

These fields are how the app checks a step against the garment's own care
label. A step whose sentence says "hot water" while `temperatureC` is null
cannot be checked, and will be shown to someone whose label forbids it.

Do NOT leave out a step because you think it might be unsafe for this garment,
and do NOT soften a treatment to make it universally safe. The app holds the
garment's real care label and removes what it forbids, and it tells the user
what it removed and why. Your job is the treatment that actually works for the
substance; the app's job is whether this garment can take it.

If the substance is one where acting fast matters, or where a common instinct
is wrong (hot water setting a protein stain, rubbing spreading an oil stain),
say so in `because` on the step it applies to.

If a photograph is attached, use it only to corroborate or refine what the
substance is. The user's own description of what was spilled outranks it.
"""

_STEP_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "instruction": {
            "type": "string",
            "description": "One step, as a complete sentence in the imperative.",
        },
        "because": {
            "type": "string",
            "nullable": True,
            "description": "Why this step, in one line. Null when self-evident.",
        },
        "temperatureC": {
            "type": "integer",
            "nullable": True,
            "description": "Water temperature this step calls for. Null if it names none.",
        },
        "bleach": {
            "type": "string",
            "nullable": True,
            "enum": ["chlorine", "oxygen"],
            "description": "The bleach this step uses, if any.",
        },
        "isMachineWash": {
            "type": "boolean",
            "description": "Whether this step puts the garment through a machine.",
        },
        "abrades": {
            "type": "boolean",
            "description": "Whether this step rubs, scrubs or works the fabric.",
        },
    },
    "required": ["instruction", "isMachineWash", "abrades"],
}

STAIN_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "identifiedAs": {
            "type": "string",
            "nullable": True,
            "description": "What you believe the stain is, in a few words.",
        },
        "steps": {
            "type": "array",
            "items": _STEP_SCHEMA,
            "description": "The treatment, in the order it should be carried out.",
        },
    },
    "required": ["steps"],
}


def describe(substance: str, fabric: str, color: str | None, care: str, note: str | None) -> str:
    """The garment and the spill, appended to the prompt."""
    lines = [
        STAIN_PROMPT,
        "",
        f"Spilled: {substance}",
        f"Fabric: {fabric}",
    ]
    if color:
        lines.append(f"Color: {color}")
    lines.append(f"Care label says: {care}")
    if note:
        lines.append(f"Also: {note}")
    return "\n".join(lines)
