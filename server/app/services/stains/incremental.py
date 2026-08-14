"""Pulling finished steps out of a JSON document that is still arriving.

Gemini streams a structured answer as a sequence of text fragments, and a
fragment is not a step — it is however much of the JSON happened to be
generated when the chunk was flushed, which lands mid-word as often as not.
Something has to decide when enough has arrived to be worth showing.

Doing it by *closing brace* rather than by chunk is the whole idea. A step is
shown the moment its own object is complete and never before, so the user
either sees a whole instruction with its temperature and its bleach field, or
sees nothing yet. A half-parsed step with `temperatureC` still missing would
sail through the safety check that exists to catch exactly that, because a null
temperature means "this step names none" — so a partial step is not merely ugly
here, it is dangerous.

Kept as pure string functions with no I/O so the awkward cases — a brace inside
a quoted instruction, an escaped quote before it, a chunk boundary mid-token —
are testable without a network or a model.
"""

from __future__ import annotations

import json
import re
from typing import Any

# Matches `"identifiedAs": "…"` only once its closing quote has arrived.
# Deliberately not a general JSON string pattern: it exists to answer "can this
# be shown yet", and a half-received value must answer no.
_IDENTIFIED_AS = re.compile(r'"identifiedAs"\s*:\s*"((?:[^"\\]|\\.)*)"')


def identified_as(buffer: str) -> str | None:
    """What the model thinks the stain is, once that field has fully arrived.

    Worth extracting early rather than waiting for the end of the document.
    It is shown above the steps precisely so a misread is caught *before*
    anybody follows a treatment aimed at the wrong substance, and advice that
    names its subject only after the last step has been read is advice that
    names it too late.
    """
    found = _IDENTIFIED_AS.search(buffer)
    if found is None:
        return None
    try:
        return str(json.loads(f'"{found.group(1)}"'))
    except json.JSONDecodeError:
        return None


def complete_steps(buffer: str) -> list[dict[str, Any]]:
    """Every step object in `buffer` whose closing brace has arrived.

    Returns them from the start each time rather than tracking a cursor. The
    buffer is a few kilobytes and the caller already knows how many it has
    emitted, so a position to keep in sync would be state bought for nothing.
    """
    start = _steps_array_start(buffer)
    if start is None:
        return []

    steps: list[dict[str, Any]] = []
    depth = 0
    object_start: int | None = None
    in_string = False
    escaped = False

    for index in range(start, len(buffer)):
        char = buffer[index]

        # Braces inside a quoted instruction are text, not structure. "Rub a
        # {small} amount in" is unlikely; an apostrophe or a quoted brand name
        # is not, and the escape handling is the same code either way.
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "{":
            if depth == 0:
                object_start = index
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0 and object_start is not None:
                steps.append(json.loads(buffer[object_start : index + 1]))
                object_start = None
        elif char == "]" and depth == 0:
            break  # The array closed; anything after it is another field.

    return steps


def _steps_array_start(buffer: str) -> int | None:
    """Where the `steps` array opens, or None if it has not opened yet."""
    key = buffer.find('"steps"')
    if key == -1:
        return None
    opening = buffer.find("[", key)
    return None if opening == -1 else opening + 1
