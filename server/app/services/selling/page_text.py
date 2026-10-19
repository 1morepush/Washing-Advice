"""Reading a price off a page.

A model is asked what an item costs, and the page is asked to bear it out. The
second half is this module: whether the number the model gave is a number the
page shows, and in what currency. It is deterministic and knows nothing about
models, which is what makes it worth trusting — a price that is not in the text
is not a price this service will repeat, however sure the model sounded.

Everything is compared in cents, as integers. `28.56` is `2856` however either
side came to write it, and `$1,250.00` is `125000` whether or not the page put
a comma in.

A price is only ever *seen* next to something that says what currency it is: a
symbol (`$`, `£`, `€`), a prefix such as `A$` or `US$`, or a code (`USD`, `GBP`)
on either side. A bare `25` is a size, a quantity or a measurement as often as a
price, and is not counted.
"""

from __future__ import annotations

import html
import re
import unicodedata
from dataclasses import dataclass
from enum import Enum

# The codes the text is searched for. USD is here so that "25.00 USD" counts as
# a dollar price; the rest are the currencies a Depop page shown to a seller in
# another country is likely to be in. Not every currency in the world: the
# symbols below catch the rest of the common ones, and a price in a currency
# listed nowhere here is one the reader would have had to report, too.
_OTHER_CODES = "GBP|EUR|AUD|CAD|NZD|CHF|JPY|SEK|NOK|DKK|PLN|CNY|HKD|SGD|INR|MXN|BRL|ZAR|KRW"
_CODES = f"USD|{_OTHER_CODES}"

_AMOUNT = r"(?P<whole>\d{1,3}(?:,\d{3})+|\d+)(?:\.(?P<cents>\d{1,2}))?(?!\d)(?!\.\d)"

_PREFIXED = re.compile(
    rf"""
    (?:
        # US$  A$  AU$  C$  CA$  NZ$  HK$: a dollar sign says whose dollars.
        (?<![A-Za-z])(?P<country>[A-Za-z]{{1,3}})\$
        # A bare $ is dollars; the rest are never dollars.
      | (?P<symbol>[$£€¥₹₩])
        # USD 25  GBP 25
      | (?<![A-Za-z])(?P<code>{_CODES})(?![A-Za-z])
    )
    \s?
    {_AMOUNT}
    """,
    re.VERBOSE | re.IGNORECASE,
)

_SUFFIXED = re.compile(
    rf"(?<![\d.,]){_AMOUNT}\s?(?P<code>{_CODES})(?![A-Za-z])",
    re.IGNORECASE,
)

# A dollar sign with these in front is dollars of the United States.
_US_PREFIXES = frozenset({"US", "USD"})

# What is stripped before looking: the characters that sit between a symbol and
# its digits on a page without being visible, and break a naive match.
_INVISIBLE = {
    ord(character): None
    for character in (
        "\N{ZERO WIDTH SPACE}",
        "\N{ZERO WIDTH NON-JOINER}",
        "\N{ZERO WIDTH JOINER}",
        "\N{WORD JOINER}",
        "\N{ZERO WIDTH NO-BREAK SPACE}",
        "\N{SOFT HYPHEN}",
    )
}

_SPACES = re.compile(r"\s+")

# The word "sold", on its own: not "unsold", not "sold-out-style", not part of a
# longer word.
_SOLD_WORD = re.compile(r"(?<![\w-])sold(?![\w-])", re.IGNORECASE)

# "Sold" in the senses that are not about this item: a seller's tally ("52
# sold") and a shop's boilerplate ("sold by"). The first is a whole number on
# its own just before the word; a price just before it ("$32 Sold", "32.00
# Sold") is the opposite, the commonest way a page marks a sale.
_TALLY_BEFORE = re.compile(r"(?:^|[\s(])\d[\d,]*\s$")
_SOLD_BY = re.compile(r"\s+by\b", re.IGNORECASE)

# How much of the text before the word is looked at for a tally. A count is a
# handful of characters, and slicing keeps the search from rescanning the page.
_TALLY_WINDOW = 14


def normalise(text: str) -> str:
    """The text as prices are looked for in it.

    Entities decoded (`&#36;25` is `$25`, `&pound;25` is `£25`), width and
    compatibility forms folded (a full-width dollar sign and digits become the
    ordinary ones), zero-width characters removed, a markdown-escaped `\\$`
    unescaped, and every run of whitespace made a single space. A page is not
    written for a regex, and a price that was on it should not be lost to how
    the page was extracted.
    """
    decoded = unicodedata.normalize("NFKC", html.unescape(text))
    unescaped = decoded.translate(_INVISIBLE).replace("\\$", "$")
    return _SPACES.sub(" ", unescaped).strip()


@dataclass(frozen=True, slots=True)
class PriceMention:
    """One amount of money the text states, and whether it states it in dollars."""

    cents: int
    usd: bool
    start: int
    """Where it begins, so "the first price on the page" means the first."""


class PriceCheck(Enum):
    VERIFIED = "verified"
    """The text states this price, in dollars."""

    NOT_USD = "not_usd"
    """The text states this amount, and in another currency."""

    NOT_FOUND = "not_found"
    """The text does not state this price at all."""


def price_mentions(text: str) -> list[PriceMention]:
    """Every priced amount in [text] (already normalised), in page order."""
    mentions: list[PriceMention] = []

    for found in _PREFIXED.finditer(text):
        if found["country"] is not None:
            usd = found["country"].upper() in _US_PREFIXES
        elif found["symbol"] is not None:
            usd = found["symbol"] == "$"
        else:
            usd = found["code"].upper() == "USD"
        mentions.append(PriceMention(_cents(found), usd, found.start()))

    for found in _SUFFIXED.finditer(text):
        mentions.append(PriceMention(_cents(found), found["code"].upper() == "USD", found.start()))

    return sorted(mentions, key=lambda mention: mention.start)


def check_price(price: float, text: str) -> PriceCheck:
    """Whether [text] (already normalised) states [price], and in dollars.

    Every place the page states that amount is looked at, and if *any* of them
    gives it in another currency the answer is `NOT_USD`, even where another
    gives it in dollars. A page that says `$25` in one place and `£25` in another
    is not one this service can say the price of, and "anything not in US
    dollars is dropped rather than converted" would be a promise it could
    not keep if a dollar sign elsewhere on the page could outvote a pound.
    """
    cents = round(price * 100)
    stated = [mention for mention in price_mentions(text) if mention.cents == cents]
    if not stated:
        return PriceCheck.NOT_FOUND
    if any(not mention.usd for mention in stated):
        return PriceCheck.NOT_USD
    return PriceCheck.VERIFIED


def first_dollar_price(text: str) -> float | None:
    """The first amount in dollars on the page, as dollars, or None."""
    for mention in price_mentions(text):
        if mention.usd:
            return mention.cents / 100
    return None


def says_sold(text: str) -> bool:
    """Whether the page says, as far as a pattern can tell, that this item has sold.

    Crude, and meant to be. It is what the fallback reader uses when no model is
    reading, and what a model's claim of a sale is checked against: it excludes
    the two commonest ways the word appears without meaning that, a seller's
    total ("52 sold") and a shop's "sold by". Those are on exactly the pages
    that are still for sale, so a check that let them through would let a
    hallucinated sale through on the pages it matters for.
    """
    for found in _SOLD_WORD.finditer(text):
        before = text[max(0, found.start() - _TALLY_WINDOW) : found.start()]
        if _TALLY_BEFORE.search(before) or _SOLD_BY.match(text, found.end()):
            continue
        return True
    return False


def _cents(found: re.Match[str]) -> int:
    whole = int(found["whole"].replace(",", ""))
    fraction = int((found["cents"] or "0").ljust(2, "0"))
    return whole * 100 + fraction
