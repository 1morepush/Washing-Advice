"""Recognising a brand in a line of text.

Two jobs need the same answer. Describing: a brand the seller typed has to be in
the title, whatever the photographs made the model write. Pricing: a listing is
only "the same item" if it names the same brand. Both are asked by comparing a
brand with some text, so the rule is written once.

Compared as words, ignoring case and the punctuation a brand is written with
differently in different places — the apostrophe in "Levi's", the dot in
"J.Crew" — and not as a substring: "Ed" is not in "Red hoodie".
"""

from __future__ import annotations

import re

# The straight and the curly apostrophe (a phone keyboard types the second),
# and the backtick some keyboards offer instead. Spelt by code point so the
# curly one is not a character in the source that looks like the straight one.
_APOSTROPHES = "'" + chr(0x2019) + "`"
_DROPPED = re.compile(f"[{re.escape(_APOSTROPHES)}.]")


def plain(text: str) -> str:
    """The text as a brand is compared: folded, without apostrophes or dots."""
    return _DROPPED.sub("", text).casefold()


def mentions_brand(text: str, brand: str) -> bool:
    """Whether [text] names [brand] as a word or words of its own."""
    wanted = plain(brand).strip()
    if not wanted:
        return False
    return re.search(rf"(?<!\w){re.escape(wanted)}(?!\w)", plain(text)) is not None


def replace_brand(text: str, old: str, new: str) -> str | None:
    """[text] with the first mention of [old] replaced by [new], or None if it has none.

    For a title when the model read one brand and the seller said another. The
    replacement is made in the original text, so the rest keeps its capitals
    and punctuation. Matched literally and as whole words: a brand the model
    spelt one way is in its own title spelt the same way.
    """
    wanted = old.strip()
    if not wanted:
        return None
    replaced, count = re.subn(
        rf"(?<!\w){re.escape(wanted)}(?!\w)",
        lambda _: new,
        text,
        count=1,
        flags=re.IGNORECASE,
    )
    return replaced if count else None
