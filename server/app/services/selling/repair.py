"""Making what a model wrote fit what the contract allows.

The same position `schemas/limits.py` takes about free text, applied to the
listing's fields: an answer that degenerates does so at its tail and is right at
its head, so a value that runs over is cut at a word boundary rather than
refused, and an entry that says nothing is dropped. Refusing a whole reading
because one flaw ran to four hundred characters would cost the seller the draft
over a string they would have shortened themselves.

What is deliberately *not* repaired is anything the model got wrong in kind
rather than in length: an item type outside the closed list, a title that is
nothing once trimmed. Those are the model failing the task, and the caller
retries them once with the problem fed back instead of papering over it.
"""

from __future__ import annotations

import re
from collections.abc import Iterable

from app.schemas.limits import clamp

_NOT_A_WORD = re.compile(r"[\W_]+")


def text(value: object, limit: int, *, minimum: int = 1) -> str | None:
    """A single line of at most [limit] characters, or None if there is nothing usable.

    Not a string, blank, or shorter than [minimum] once trimmed all come back as
    None: the field is then absent rather than present and empty, which the
    contract reads as "the photographs did not show it".
    """
    if not isinstance(value, str):
        return None
    # One line: a newline in a title or a flaw is the model formatting its
    # answer, not something to show a buyer.
    trimmed = clamp(" ".join(value.split()), limit)
    if trimmed is None or len(trimmed) < minimum:
        return None
    return trimmed


def texts(
    values: object,
    *,
    limit: int,
    count: int,
    minimum: int = 1,
    exclude: Iterable[str] = (),
) -> list[str]:
    """The first [count] distinct usable entries of a list, each trimmed to [limit].

    Distinct ignoring case and punctuation, so "Grey" and "grey" are one colour.
    [exclude] names entries that must not appear whatever the model said — the
    brand, from the style words, since it has a field of its own.
    """
    if not isinstance(values, list):
        return []

    seen = {_key(entry) for entry in exclude}
    kept: list[str] = []
    for value in values:
        entry = text(value, limit, minimum=minimum)
        if entry is None:
            continue
        # An entry with no letter or digit in it ("-", "...") says nothing.
        key = _key(entry)
        if not key or key in seen:
            continue
        seen.add(key)
        kept.append(entry)
        if len(kept) == count:
            break
    return kept


def confidence(value: object, default: float) -> float:
    """A confidence in 0 to 1, whatever the model sent.

    A model occasionally reports 1.2, or a percentage, or nothing. Clamped
    rather than refused, like the scans, and a missing one takes [default]
    rather than being read as certainty.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return default
    return min(1.0, max(0.0, float(value)))


def _key(entry: str) -> str:
    return _NOT_A_WORD.sub("", entry).casefold()
