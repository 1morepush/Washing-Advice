"""Bounds on the free text a model is allowed to put in the wardrobe.

Every other field a scan produces is checked by its own shape: an enum rejects
a value that is not one of its members, a confidence outside 0 to 1 fails
validation, a colour is three numbers. The free-text fields have no such shape,
so whatever the model writes is what reaches the app, is drawn on a screen and
is written to somebody's database.

That is fine until a generation degenerates, which they do. Reported from a real
scan, a garment came back named:

    Black t-shirt with Koshi no Kanbai pocket print & petals graphic design
    pattern context details sample color code analysis complete output
    formatting standard strict mode syntax structure layout parsing clear
    summary validation success check finished payload result object format
    output payload JSON structure complete string result correctly formatted
    JSON string structure validate output string result strictly JSON …

— the real name, and then the model talking to itself about JSON until it ran
out of tokens. It filled the review screen and pushed every other reading off
the bottom.

**Truncation rather than rejection**, because of where the damage sits. The
answer degenerates at the *tail*: the first clause of that name is not merely
salvageable, it is the correct name. Refusing the whole reading would throw
away a good garment identification over a bad string, and cost the user the
scan. Cutting at a word boundary keeps "Black t-shirt with Koshi no Kanbai
pocket print & petals graphic" and drops the rest, which is what they would
have typed anyway.

The limits are set by what the field is *for* rather than by what looks safe.
A garment name somebody would write is three or four words; sixty-four
characters is already generous. The slogan on a t-shirt can run longer. None of
them is a paragraph, and a field arriving as one is not a long answer, it is a
broken one.
"""

from __future__ import annotations

MAX_NAME = 64
"""A suggested garment name. 'Grey Nike hoodie' is sixteen characters."""

MAX_BRAND = 48
"""A brand. The longest real ones are well inside this."""

MAX_PRINTED_TEXT = 200
"""Words printed on a garment. A band name is short; a tour list is not."""

MAX_COUNTRY = 56
"""A country as printed on a label. The longest UN member name is 56."""

MAX_RAW_TEXT = 2000
"""Everything legible on a care label, transcribed.

Much larger than the rest because a real label genuinely is a paragraph, in
three languages. Still bounded: this is stored per garment.
"""


def clamp(value: str | None, limit: int) -> str | None:
    """Trims [value] to [limit], preferring a word boundary.

    Returns None for what was only whitespace, so an empty string never reaches
    the app as though the model had said something.

    No ellipsis is appended. The result is a name somebody will see in a text
    field and may keep as it stands; "Black tee…" is not a name, and a trailing
    character that has to be deleted before the field is usable would be this
    function making its own mess to clean up.
    """
    if value is None:
        return None

    trimmed = value.strip()
    if not trimmed:
        return None
    if len(trimmed) <= limit:
        return trimmed

    cut = trimmed[:limit]
    # Back up to the last space, unless that would leave almost nothing — a
    # single unbroken run of characters has no boundary to find, and half of
    # the limit is the point where honouring the boundary costs more than it
    # buys.
    boundary = cut.rfind(" ")
    if boundary > limit // 2:
        cut = cut[:boundary]
    return cut.rstrip(" ,.;:-—") or trimmed[:limit]
