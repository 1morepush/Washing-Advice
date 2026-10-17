"""Looking up what a garment sells for.

The sequence behind `POST /v1/sell/prices`, in the order its parts distrust each
other:

1. **Search**, twice at once: Depop listings, and shops selling the thing new.
   This is the only step that spends anything, so it is the one a remembered
   answer skips.
2. **Read**, by whatever the reader is: a model in production, a pattern when
   there is none. It says which results are worth pricing from and what each
   costs. It is a claim, and the least trusted thing in the sequence.
3. **Vet** (`vetting.py`): the claims checked against the pages they came from.
   What survives is what the seller sees; what does not is counted.

Whatever happens, this answers. A listing can be written without a price search,
so a search that was not configured, ran out of allowance or broke is a *status*
on an otherwise ordinary answer (with the phrases echoed and nothing found), never
an error. The app's fallback to links and prices typed by hand is built on that:
it only has to look at one field.

**One lookup at a time per search.** Two requests for the same search that arrive
while the first is still running join it rather than starting their own. The
cache cannot help there, because the answer it would hold does not exist yet, and
the moments it matters are the ordinary ones: a double tap, or a retry after the
phone gave up waiting on a server that was still waking up. Each would otherwise
spend two credits of an allowance shared by every listing there is.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from functools import partial

from app.schemas.selling import (
    ExcludedCounts,
    PriceSearch,
    PriceSearchRequest,
    PriceSearchStatus,
    SearchQueries,
)
from app.services.ai.base import ProviderError
from app.services.selling.base import (
    Candidate,
    ComparableReader,
    Kind,
    ListingItem,
    NumberedResult,
    SearchError,
    SearchHit,
    SearchRequest,
    WebSearch,
)
from app.services.selling.cache import CacheKey, PriceCache, cache_key
from app.services.selling.domains import COMPARABLE_DOMAIN, RESALE_DOMAINS, canonical_url
from app.services.selling.page_text import normalise
from app.services.selling.vetting import vet

logger = logging.getLogger(__name__)

DEPOP_RESULTS = 10
RETAIL_RESULTS = 8
"""How many results each search asks for. Credits are per search, not per result."""


@dataclass(frozen=True, slots=True)
class PriceSearchOutcome:
    """The answer, and how it was arrived at, for the response's diagnostics."""

    result: PriceSearch
    stages_run: list[str]
    stage_answered: str | None
    from_cache: bool = False


def _utcnow() -> datetime:
    return datetime.now(UTC)


class PriceSearcher:
    def __init__(
        self,
        search: WebSearch,
        reader: ComparableReader,
        cache: PriceCache | None = None,
        *,
        now: Callable[[], datetime] = _utcnow,
    ) -> None:
        self._search = search
        self._reader = reader
        self._cache = cache
        # Injected so a test can say when the search ran.
        self._now = now
        self._running: dict[CacheKey, asyncio.Task[PriceSearchOutcome]] = {}

    async def aclose(self) -> None:
        # What is still running is stopped before what it is using is closed.
        running = list(self._running.values())
        for task in running:
            task.cancel()
        if running:
            await asyncio.gather(*running, return_exceptions=True)

        for part in (self._search, self._reader):
            closer = getattr(part, "aclose", None)
            if closer is not None:
                await closer()

    async def search(self, request: PriceSearchRequest) -> PriceSearchOutcome:
        if not self._search.configured:
            # No key, so no call: the app falls back to links and typed prices.
            return self._unanswered(request, PriceSearchStatus.NOT_CONFIGURED, stages=[])

        key = cache_key(request)
        remembered = self._cache.get(key) if self._cache is not None else None
        if remembered is not None:
            return PriceSearchOutcome(
                result=_as_asked(remembered, request),
                stages_run=["cache"],
                stage_answered="cache",
                from_cache=True,
            )

        outcome = await self._joined(key, request)
        return replace(outcome, result=_as_asked(outcome.result, request))

    async def _joined(self, key: CacheKey, request: PriceSearchRequest) -> PriceSearchOutcome:
        """The lookup for this search, started if nothing is running it, joined if it is."""
        loop = asyncio.get_running_loop()
        task = self._running.get(key)
        # Only a lookup on this event loop can be waited for from it.
        if task is None or task.get_loop() is not loop:
            task = loop.create_task(self._look_up(request))
            self._running[key] = task
            task.add_done_callback(partial(self._finished, key))

        # Shielded, so a caller that gives up (the phone went away) leaves the
        # lookup to finish. It has already spent the credits, and its answer is
        # what the retry will be handed from the cache.
        return await asyncio.shield(task)

    def _finished(self, key: CacheKey, task: asyncio.Task[PriceSearchOutcome]) -> None:
        if self._running.get(key) is task:
            del self._running[key]
        if not task.cancelled():
            # Looked at, so an error nobody was left waiting for is not also
            # reported as one nobody ever looked at.
            task.exception()

    async def _look_up(self, request: PriceSearchRequest) -> PriceSearchOutcome:
        listings, shops = await asyncio.gather(
            self._attempt(_depop_search(request.queries)),
            self._attempt(_retail_search(request.queries)),
        )

        stages = [self._search.name]
        if isinstance(listings, SearchError) and isinstance(shops, SearchError):
            # Both searches failed: nothing was found, so say why. Out of
            # allowance outranks the rest, because it is the one the person can
            # wait out and the one worth telling them is not a fault.
            statuses = {listings.status, shops.status}
            status = (
                PriceSearchStatus.QUOTA_EXCEEDED
                if PriceSearchStatus.QUOTA_EXCEEDED in statuses
                else PriceSearchStatus.UNAVAILABLE
            )
            return self._unanswered(request, status, stages=stages)

        # One search failing and the other answering still prices from what
        # answered: half the market is more use than none. But it is half an
        # answer, and is not kept (see `_answered`).
        complete = not isinstance(listings, SearchError) and not isinstance(shops, SearchError)
        results = _number(
            [] if isinstance(listings, SearchError) else listings,
            [] if isinstance(shops, SearchError) else shops,
        )
        if not results:
            return self._answered(
                request, results, [], stages, stage_answered=stages[0], keep=complete
            )

        try:
            claims = await self._reader.read(_item(request), results)
        except ProviderError as error:
            # The reader is a model on a free tier, and it can be rate-limited
            # or down. That is the lookup failing, not the request being wrong:
            # the searches are spent, and the answer is that there are no
            # prices this time. Not kept, so asking again tries again.
            logger.warning("price reader failed: %s", error)
            return self._unanswered(
                request, PriceSearchStatus.UNAVAILABLE, stages=[*stages, self._reader.name]
            )

        return self._answered(
            request,
            results,
            claims,
            [*stages, self._reader.name],
            stage_answered=self._reader.name,
            keep=complete,
        )

    async def _attempt(self, search: SearchRequest) -> list[SearchHit] | SearchError:
        try:
            hits = await self._search.search(search)
        except SearchError as error:
            return error
        # No more than were asked for. A service that sends extra is not thereby
        # owed a place in the prompt, and a prompt is sized by what is in it.
        return hits[: search.max_results]

    def _answered(
        self,
        request: PriceSearchRequest,
        results: list[NumberedResult],
        claims: list[Candidate],
        stages: list[str],
        *,
        stage_answered: str,
        keep: bool,
    ) -> PriceSearchOutcome:
        """An answer, remembered unless [keep] says it is only part of one.

        An answer that found nothing is still an answer worth keeping: it is a
        fact about the market. Half of one is a fact about the last few seconds
        and the service's health, and keeping it for six hours would hold a
        listing without comparables long after the search that failed recovered.
        """
        vetted = vet(claims, results, brand=request.brand)
        found = PriceSearch(
            status=PriceSearchStatus.OK,
            # Whole seconds: the time a person reads, not a timestamp to the
            # microsecond that a client has to be able to parse.
            searched_at=self._now().replace(microsecond=0),
            provider=self._search.name,
            queries=request.queries,
            comparables=vetted.comparables,
            retail=vetted.retail,
            excluded=vetted.excluded,
        )
        logger.info(
            "price search read %d results: %d comparables, %d retail",
            len(results),
            len(vetted.comparables),
            len(vetted.retail),
        )
        if keep and self._cache is not None:
            self._cache.put(cache_key(request), found)
        return PriceSearchOutcome(result=found, stages_run=stages, stage_answered=stage_answered)

    def _unanswered(
        self,
        request: PriceSearchRequest,
        status: PriceSearchStatus,
        *,
        stages: list[str],
    ) -> PriceSearchOutcome:
        """An answer with nothing in it, and the reason. Never cached."""
        return PriceSearchOutcome(
            result=PriceSearch(
                status=status,
                queries=request.queries,
                comparables=[],
                retail=[],
                excluded=ExcludedCounts.zero(),
            ),
            stages_run=stages,
            stage_answered=None,
        )


def _as_asked(found: PriceSearch, request: PriceSearchRequest) -> PriceSearch:
    """The answer with the phrases as this request wrote them.

    A remembered or shared answer was found for a request that spelt the same
    search differently ("NIKE hoodie" and "nike hoodie"). The lists, the counts
    and the time are the search's own, and the phrases are the asker's.
    """
    return found.model_copy(update={"queries": request.queries})


def _depop_search(queries: SearchQueries) -> SearchRequest:
    """Listings on Depop, and nowhere else."""
    return SearchRequest(
        query=_one_line(queries.depop),
        include_domains=(COMPARABLE_DOMAIN,),
        max_results=DEPOP_RESULTS,
    )


def _retail_search(queries: SearchQueries) -> SearchRequest:
    """What the thing costs new: the product name and the word "price", off resale sites."""
    phrase = _one_line(queries.retail)
    # "price" steers the search toward a product page rather than a review or a
    # lookbook, and a phrase that already says it should not say it twice.
    if "price" not in phrase.lower().split():
        phrase = f"{phrase} price"
    return SearchRequest(
        query=phrase,
        exclude_domains=RESALE_DOMAINS,
        max_results=RETAIL_RESULTS,
    )


def _one_line(text: str) -> str:
    return " ".join(text.split())


def _item(request: PriceSearchRequest) -> ListingItem:
    return ListingItem(
        title=request.title,
        item_type=request.item_type.value,
        brand=request.brand,
        colors=tuple(request.colors or ()),
    )


def _number(listings: list[SearchHit], shops: list[SearchHit]) -> list[NumberedResult]:
    """The results of both searches as one numbered list, each page once.

    Depop first, then the shops. A page that came back twice — in both searches,
    or twice in one, under two spellings of its link — is read once, so it cannot
    count twice and the reader is not shown the same page under two numbers.
    """
    numbered: list[NumberedResult] = []
    seen: set[str] = set()
    found: tuple[tuple[Kind, list[SearchHit]], ...] = (("listing", listings), ("retail", shops))
    for origin, hits in found:
        for hit in hits:
            link = canonical_url(hit.url)
            if link in seen:
                continue
            seen.add(link)
            numbered.append(
                NumberedResult(
                    index=len(numbered),
                    origin=origin,
                    title=normalise(hit.title),
                    url=hit.url,
                    text=_page_text(hit),
                    score=hit.score,
                )
            )
    return numbered


def _page_text(hit: SearchHit) -> str:
    """Everything the page told us, as one normalised text.

    The snippet is what the search extracted for the query and the page text is
    what it fetched; a price may be in either, and the snippet is usually part of
    the page, so it is only added when it is not.
    """
    snippet = normalise(hit.content)
    page = normalise(hit.raw_content)
    if snippet and snippet not in page:
        return f"{snippet} {page}".strip()
    return page or snippet
