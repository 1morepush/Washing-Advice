"""A reader that needs no model, for tests and for running without a key.

It takes the first dollar price on each page and calls the result "similar". That
is crude on purpose and nothing more is claimed for it: the first `$` on a page
is the item's price often enough to exercise the endpoint end to end, and wrong
often enough that the vetting still has something to refuse. It never claims
"same" (that needs a judgement about a product, which a pattern cannot make),
never claims a listing is *not* sold (only a model can know that), and gives no
reason.

It reads what a model would be shown and says what a model would say, so
everything after it — the vetting, the caps, the cache, the response — runs for
real. With `VISION_PROVIDER=fake` and a search key it will price a garment from
live results, badly; that is a configuration nobody should be in, and a
reasonable one to be in while finding out whether the search itself works.
"""

from __future__ import annotations

from app.services.selling.base import Candidate, ListingItem, NumberedResult
from app.services.selling.page_text import first_dollar_price, says_sold


class RegexComparableReader:
    @property
    def name(self) -> str:
        return "regex"

    async def read(self, item: ListingItem, results: list[NumberedResult]) -> list[Candidate]:
        candidates: list[Candidate] = []
        for result in results:
            price = first_dollar_price(result.searchable)
            if price is None:
                continue

            # Only ever "sold" or silence: a page that does not say so is not
            # thereby still for sale. And only a listing can have sold.
            sold = result.origin == "listing" and says_sold(result.searchable)

            candidates.append(
                Candidate(
                    result_index=result.index,
                    kind=result.origin,
                    price=price,
                    currency="USD",
                    sold=True if sold else None,
                    match="similar",
                )
            )
        return candidates
