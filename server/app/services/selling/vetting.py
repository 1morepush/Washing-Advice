"""Deciding which of a reader's claims reach the screen.

The heart of `POST /v1/sell/prices`, and written to be the part that does not
need trusting. A reader — a model, in production — looks at a handful of search
results and says which are worth showing and what they cost. The seller is going
to price a garment from what comes out of here, so a result that is wrong costs
real money, and the reader is exactly the component that can be wrong: it can
number a result that does not exist, put a price on the wrong item, copy a pound
as a dollar, or call a listing sold that is not.

So nothing it says is taken as given. For every claim:

* The result it refers to must exist. The link and the title come from *that
  search result*, never from the reader, who is not asked for either: a link a
  model invents cannot get onto a screen, because it never gets the chance to
  write one.
* The result must be where its kind says. A comparable is a Depop listing, on
  `depop.com` or a subdomain of it. A retail price is not from a resale site.
  Anything else is not comparable, whatever the reader thought.
* The price must be in dollars: not reported as another currency, and not stated
  on the page next to a `£` or an `A$`.
* The price must be *on the page*, in the text the reader was shown.

Then the claims that are not about the price are brought down to what the page
supports: `sold` stays only if the page says the item has sold (not merely that
its seller has sold fifty others), a condition only if it appears verbatim, and
"same item" only if the page names the brand. These do not drop a result; they
refuse to repeat more than the page says. A sale that never happened would
outweigh every asking price beside it in the arithmetic that follows, so that is
the claim worth a check of its own.

Every result ends up in exactly one place — shown, or counted under the reason it
was not — so the numbers the app displays ("2 not in US dollars") add up to what
was looked at.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from enum import Enum
from typing import Literal, TypeVar

from pydantic import ValidationError

from app.schemas.selling import Comparable, ExcludedCounts, RetailReference
from app.services.selling import repair
from app.services.selling.base import Candidate, NumberedResult
from app.services.selling.brands import mentions_brand
from app.services.selling.domains import (
    COMPARABLE_DOMAIN,
    canonical_url,
    host_of,
    is_on,
    is_resale,
    shop_name,
)
from app.services.selling.page_text import PriceCheck, check_price, says_sold

MAX_COMPARABLES = 12
MAX_RETAIL = 6
"""How many of each are shown. The contract's bounds, and enough to price from."""

MAX_PRICE = 100_000
"""The contract's ceiling on a price. Anything above it is not a price here."""

_USD = frozenset({"USD", "US$", "USD$", "$", "US DOLLAR", "US DOLLARS"})
"""How a reader may say "dollars". Compared upper-case."""

_Shown = TypeVar("_Shown", Comparable, RetailReference)


class _Reason(Enum):
    NOT_USD = "not_usd"
    UNVERIFIED_PRICE = "unverified_price"
    NOT_COMPARABLE = "not_comparable"


@dataclass(frozen=True, slots=True)
class Vetted:
    """What survived, in the order to show it, and what did not and why."""

    comparables: list[Comparable]
    retail: list[RetailReference]
    excluded: ExcludedCounts


def vet(
    candidates: Sequence[Candidate],
    results: Sequence[NumberedResult],
    *,
    brand: str | None = None,
) -> Vetted:
    """The claims in [candidates] that [results] bear out.

    [brand] is the garment's brand when it has one, and is what a "same item"
    claim is held to. Never raises for a bad claim, whatever it says: a reader
    that sends nonsense gets its nonsense counted, and the price lookup still
    answers.
    """
    by_index = {result.index: result for result in results}

    # One claim per result: the first. A reader that lists the same page twice
    # (a sale price and a 'was' price, say) has not found two comparables.
    claims: dict[int, Candidate] = {}
    for candidate in candidates:
        # An index that is not a result is not counted anywhere. It is not
        # something the search found; counting it would make the excluded
        # numbers add up to more than was looked at.
        if candidate.result_index in by_index:
            claims.setdefault(candidate.result_index, candidate)

    tally = dict.fromkeys(_Reason, 0)
    comparables: list[tuple[Comparable, float]] = []
    retail: list[tuple[RetailReference, float]] = []
    shown: set[str] = set()

    for result in results:
        claim = claims.get(result.index)
        if claim is None:
            # The reader did not put it forward, which is how it says "not
            # comparable". Most of what any search returns lands here.
            tally[_Reason.NOT_COMPARABLE] += 1
            continue

        reason = _refusal(claim, result)
        if reason is not None:
            tally[reason] += 1
            continue

        # The same page found twice is one page. Checked after the refusals so
        # a duplicate of something that was refused does not hide a good one.
        # The searcher also drops repeats before the reader is shown them, which
        # saves the reader the same page twice; this check does not depend on
        # whoever calls, because it is what keeps one sale from counting as two.
        link = canonical_url(result.url)
        if link in shown:
            continue

        try:
            if claim.kind == "listing":
                comparables.append((_comparable(claim, result, brand), result.score))
            else:
                retail.append((_retail_reference(claim, result, brand), result.score))
        except ValidationError:
            # Reached only if a field the checks above guarantee still does not
            # fit the contract. Counted, because a result that cannot be shown
            # is not comparable, and never raised, because the price lookup
            # answers regardless.
            tally[_Reason.NOT_COMPARABLE] += 1
            continue
        shown.add(link)

    return Vetted(
        comparables=_best(comparables, MAX_COMPARABLES),
        retail=_best(retail, MAX_RETAIL),
        excluded=ExcludedCounts(
            not_usd=tally[_Reason.NOT_USD],
            unverified_price=tally[_Reason.UNVERIFIED_PRICE],
            not_comparable=tally[_Reason.NOT_COMPARABLE],
        ),
    )


def _refusal(claim: Candidate, result: NumberedResult) -> _Reason | None:
    """Why this claim is not shown, or None if the page bears it out.

    In the order that tells the person the most true thing. A page on the wrong
    site is "not comparable" even if it is also in pounds, because it was never
    a candidate; a Depop page in pounds is "not in US dollars", because it was.
    """
    host = host_of(result.url)
    if host is None:
        return _Reason.NOT_COMPARABLE

    if claim.kind == "listing":
        if not is_on(host, COMPARABLE_DOMAIN):
            return _Reason.NOT_COMPARABLE
    elif is_resale(host):
        return _Reason.NOT_COMPARABLE

    if _reported_other_currency(claim.currency):
        return _Reason.NOT_USD

    price = claim.price
    if not math.isfinite(price) or not 0 < price <= MAX_PRICE:
        return _Reason.UNVERIFIED_PRICE

    found = check_price(price, result.searchable)
    if found is PriceCheck.NOT_USD:
        return _Reason.NOT_USD
    if found is PriceCheck.NOT_FOUND:
        return _Reason.UNVERIFIED_PRICE
    return None


def _reported_other_currency(currency: str) -> bool:
    """Whether the reader said the price is in something other than dollars.

    An empty currency says nothing either way, and is left to the page: the
    price still has to be found there next to a dollar sign.
    """
    stated = currency.strip().upper()
    return bool(stated) and stated not in _USD


def _comparable(claim: Candidate, result: NumberedResult, brand: str | None) -> Comparable:
    host = host_of(result.url) or ""

    # Only a sale the page says. A comparable marked sold is weighed above every
    # asking price beside it, so a page still for sale ("52 sold" is its seller's
    # tally) cannot be allowed to carry one on a model's say-so.
    sold = claim.sold
    if sold is True and not says_sold(result.searchable):
        sold = None

    return Comparable(
        title=_title(result, host),
        url=result.url.strip(),
        price=round(claim.price, 2),
        sold=sold,
        condition=_verbatim_condition(claim.condition, result.searchable),
        match=_match(claim, result, brand),
        why=repair.text(claim.why, 160),
    )


def _retail_reference(
    claim: Candidate, result: NumberedResult, brand: str | None
) -> RetailReference:
    host = host_of(result.url) or ""
    seller = shop_name(host)

    return RetailReference(
        title=_title(result, host),
        url=result.url.strip(),
        price=round(claim.price, 2),
        seller=seller if len(seller) <= 80 else None,
        match=_match(claim, result, brand),
    )


def _title(result: NumberedResult, host: str) -> str:
    """The search result's own title, tidied to the contract, or its site if it had none."""
    return repair.text(result.title, 200) or shop_name(host)


def _match(
    claim: Candidate, result: NumberedResult, brand: str | None
) -> Literal["same", "similar"]:
    """The reader's "same" or "similar", with "same" held to the brand.

    Two same-item sales are enough, in the arithmetic that follows, to price
    above every asking price, so "same" has to mean something a pattern can see:
    the page names the garment's brand. Where the garment has no brand to name,
    there is nothing to hold it to and the reader's word stands.
    """
    if claim.match == "same" and brand and not mentions_brand(result.searchable, brand):
        return "similar"
    return claim.match


def _verbatim_condition(condition: str | None, text: str) -> str | None:
    """The condition, if the page says it in those words; otherwise nothing.

    The contract calls it "as that listing states it, verbatim", and a reader
    paraphrasing "Used - Excellent" into "excellent shape" is not stating it.
    """
    stated = " ".join(condition.split()) if condition else ""
    if not stated or len(stated) > 40:
        return None
    return stated if stated.casefold() in text.casefold() else None


def _best(kept: list[tuple[_Shown, float]], cap: int) -> list[_Shown]:
    """The [cap] best, 'same' before 'similar' and then by how relevant the search thought.

    Stable, so results the search ranked equally stay in the order it gave them.
    """
    ordered = sorted(kept, key=lambda item: (item[0].match != "same", -item[1]))
    return [item for item, _ in ordered[:cap]]
