"""What the stylist is asked, and the shape it must answer in.

The opposite instruction from every other prompt in this service. Everywhere
else the model is told to report what it can see and leave the judging alone,
because being wrong ruins a garment. Here the judgement *is* the request: the
rule-based builder already scores colour, wear counts and what has been worn
together, and what it cannot do is look at a pinstripe beside a check and say
that the two fight. So this prompt asks for taste, and spends its length on the
two things taste must not become.

The first is invention. The model may only name ids from the list it was given;
an id it made up would put a garment on somebody's screen that cannot be
opened. The core refuses those anyway, but a refusal is a suggestion lost, and
the prompt is where they stop being generated.

The second is hedging. A reason that says "these colours work well together" is
one the builder could have written, and if that is all the model has to say
there was no point asking it. The reason is shown to the user in full, in the
model's own words, so it has to be worth reading.

`GAPS_PROMPT` asks the other half of the same question — which pieces the
wardrobe is missing — and spends its length on the two ways that goes wrong. It
must not suggest what somebody already owns, which is the fastest way to look
like it never read the list. And it must not turn into shopping: no brands, no
shops, no prices, no products. This is a wardrobe app, and plenty of people use
one to buy less; describing the garment and stopping there leaves what to do
about it where it belongs.
"""

from __future__ import annotations

from typing import Any

from app.schemas.style import StyleCandidate, StyleRequest

STYLE_PROMPT = """You are helping somebody decide what to wear from the clothes
they actually own. Below is their wardrobe, one garment per line, each with an
id.

Propose complete outfits. Every outfit needs something on top and something on
the bottom, or a single garment that covers both (a dress, a jumpsuit). Add
shoes when there are shoes to add, and a layer when the season or the note
calls for one.

RULES YOU MUST NOT BREAK:

- Use only the ids listed below, copied exactly. Never invent an id, never
  guess at one, and never name a garment that is not in the list.
- Never put two garments in the same place on the body: not two tops, not two
  pairs of trousers, not a dress and trousers together. A jacket over a shirt
  is fine — that is layering, not a conflict.
- Never use the same id twice in one outfit.
- Make each outfit different from the others. Five variations on the same two
  garments is one idea, not five.

WHAT THE REASON IS FOR:

Say why these pieces work together, in one or two sentences, as you would to a
friend. The person reading it will see your words exactly as you write them and
is expected to disagree with some of them.

Write about the things a program cannot check: how a pattern sits against
another pattern, whether the proportions balance, how formal the combination
reads, what the texture of one fabric does next to another. "Navy and white go
together" is something their app already worked out on its own; it is asking
you because it cannot tell that the fine stripe and the bold check are
fighting.

Do not hedge, do not caveat, and do not explain that style is subjective. Name
the specific garments in your reason so it is obvious which outfit it belongs
to.
"""

GAPS_PROMPT = """
ALSO NAME WHAT IS MISSING:

Some of their clothes are asking for something they do not own. A light
graphic tee wants a mid-weight indigo denim under it; a linen shirt wants
something that is not black jeans. Name those pieces.

RULES FOR THESE:

- Every piece must go with garments from the list above. Name their ids in
  pairsWith, copied exactly. A piece with nothing of theirs to wear it with is
  a shopping list entry, not advice, and will be thrown away.
- Never name something they already have. Read the list first: if there are
  already dark blue jeans on it, do not suggest dark blue jeans. Suggesting
  what somebody owns is the fastest way to look like you did not look.
- Use the type labels given below, copied exactly, and say the colour in plain
  words — "dark blue", "cream", "olive". Somebody is going to read this while
  looking at their own drawers or a rail in a shop.
- Never name a brand, a shop, a price or a specific product. Describe the
  garment, not where to get it. They may already own the answer, or find it
  second-hand, or decide against it — none of that is yours to steer.
- Two or three at most, and only where one is genuinely wanted. A wardrobe
  with no real gap should return an empty list. Inventing a need is worse than
  saying nothing, because it turns every honest suggestion into noise.

Say why it works against the specific garments it pairs with, the same way you
did for the outfits.
"""

STYLE_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "outfits": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "itemIds": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Ids copied exactly from the wardrobe list.",
                    },
                    "rationale": {
                        "type": "string",
                        "description": "Why these go together, in one or two sentences.",
                    },
                },
                "required": ["itemIds", "rationale"],
            },
        },
        "pieces": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {
                        "type": "string",
                        "description": "A label copied exactly from the allowed types.",
                    },
                    "colors": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Plain colour words, e.g. 'dark blue'.",
                    },
                    "pairsWith": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "Ids of their garments this goes with.",
                    },
                    "rationale": {
                        "type": "string",
                        "description": "Why it works, in one or two sentences.",
                    },
                },
                "required": ["type", "pairsWith", "rationale"],
            },
        },
    },
    "required": ["outfits"],
}


def _line(item: StyleCandidate) -> str:
    """One garment, as one readable line.

    Lines rather than JSON. The model reads a wardrobe better as a list of
    descriptions than as an array of objects, and it costs fewer tokens per
    garment — which matters when the whole wardrobe goes up on every request.
    """
    parts = [item.type]
    if item.fit:
        parts.append(f"{item.fit} fit")
    if item.pattern and item.pattern.lower() not in {"solid", "plain"}:
        parts.append(item.pattern)
    if item.colors:
        parts.append("/".join(item.colors))
    if item.fabric:
        parts.append(item.fabric)
    if item.brand:
        parts.append(item.brand)

    return f"- {item.id}: {item.name} — {', '.join(parts)} [{item.category}]"


def describe(request: StyleRequest) -> str:
    """The prompt with this wardrobe and this occasion appended."""
    lines = [
        STYLE_PROMPT,
        "",
        f"Occasion: {request.occasion}",
    ]
    if request.season:
        lines.append(f"Season: {request.season}")
    if request.note:
        lines.append(f"They added: {request.note}")

    lines.append(f"Propose {request.count} outfits.")
    lines.append("")
    lines.append("Their wardrobe:")
    lines.extend(_line(item) for item in request.wardrobe)

    if request.suggest_gaps:
        lines.append(GAPS_PROMPT)
        if request.stylable_types:
            lines.append("Types you may name, copied exactly:")
            lines.append(", ".join(request.stylable_types))

    return "\n".join(lines)
