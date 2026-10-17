"""Doubles for the selling endpoints: Gemini and Tavily, faked at the transport.

Nothing in the suite reaches the network, and neither service has a key here. Both
are replaced where the code meets them — an `httpx.MockTransport` under the real
client — so the real request is built, sent through the real client and read by the
real parser. A double that stood in for the whole class would test everything
except the part that talks to the service.

Each double records what it was sent. Most of what is worth asserting about a call
to a paid service is on the request side: that it was one credit and not two, that
the key was in the header, that the domains were the ones the policy says.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import datetime
from typing import Any

import httpx
from fastapi.testclient import TestClient

from app.api.v1.dependencies import get_listing_describer, get_price_searcher
from app.main import create_app
from app.services.selling.base import ComparableReader, ListingDescriber
from app.services.selling.cache import PriceCache
from app.services.selling.gemini_describer import GeminiListingDescriber
from app.services.selling.gemini_reader import GeminiComparableReader
from app.services.selling.prices import PriceSearcher
from app.services.selling.regex_reader import RegexComparableReader
from app.services.selling.tavily import TavilySearch

KEY = "tvly-test-key-0123456789"
"""A Tavily key that is easy to search for in a log, and nothing else."""

Reply = httpx.Response | Callable[[httpx.Request], httpx.Response]


def fresh(response: httpx.Response) -> httpx.Response:
    """A copy that has not been read or closed, for the next attempt to receive."""
    return httpx.Response(response.status_code, headers=response.headers, content=response.content)


class Recorder:
    """A transport handler that records requests and plays scripted replies back.

    The last reply repeats, so a script of one answers every attempt.
    """

    def __init__(self, *replies: Reply) -> None:
        self._replies = list(replies)
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        scripted = self._replies[min(len(self.requests), len(self._replies)) - 1]
        return scripted(request) if callable(scripted) else fresh(scripted)

    def bodies(self) -> list[dict[str, Any]]:
        return [json.loads(request.content) for request in self.requests]


# --- Gemini ------------------------------------------------------------------


def reply(payload: Any) -> httpx.Response:
    """A Gemini reply whose text is [payload] as JSON."""
    return httpx.Response(
        200,
        json={"candidates": [{"content": {"parts": [{"text": json.dumps(payload)}]}}]},
    )


class Gemini(Recorder):
    """A mocked Gemini API."""

    def prompts(self) -> list[str]:
        return [body["contents"][0]["parts"][0]["text"] for body in self.bodies()]

    def client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(transport=httpx.MockTransport(self))

    def describer(self, **settings: Any) -> GeminiListingDescriber:
        return GeminiListingDescriber(
            api_key=settings.pop("api_key", "test-key"), client=self.client(), **settings
        )

    def reader(self, **settings: Any) -> GeminiComparableReader:
        return GeminiComparableReader(
            api_key=settings.pop("api_key", "test-key"), client=self.client(), **settings
        )


# --- Tavily ------------------------------------------------------------------


def hit(
    url: str,
    *,
    title: str = "",
    content: str = "",
    raw: str | None = "",
    score: float = 0.5,
) -> dict[str, Any]:
    """One result, as Tavily's JSON has it."""
    return {"title": title, "url": url, "content": content, "raw_content": raw, "score": score}


def answer(*hits: dict[str, Any]) -> httpx.Response:
    """A successful Tavily reply carrying [hits]."""
    return httpx.Response(
        200, json={"query": "q", "results": list(hits), "response_time": 0.8, "request_id": "r"}
    )


def status(code: int, body: Any = None) -> httpx.Response:
    """A Tavily failure with the given HTTP status."""
    return httpx.Response(code, json=body if body is not None else {"detail": {"error": "no"}})


class Tavily:
    """A mocked Tavily API, answering the two searches of one price lookup.

    The two are told apart by what the request filters on, which is also the
    policy under test: the Depop search names a domain to include, and the retail
    search names domains to leave out.
    """

    def __init__(self, depop: Reply | None = None, retail: Reply | None = None) -> None:
        self.depop = Recorder(depop if depop is not None else answer())
        self.retail = Recorder(retail if retail is not None else answer())
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        body = json.loads(request.content)
        which = self.depop if "include_domains" in body else self.retail
        return which(request)

    def bodies(self) -> list[dict[str, Any]]:
        return [json.loads(request.content) for request in self.requests]

    def search(self, key: str | None = KEY, **settings: Any) -> TavilySearch:
        return TavilySearch(
            key,
            client=httpx.AsyncClient(transport=httpx.MockTransport(self)),
            **settings,
        )


# The pages a price lookup for the contract's grey Nike crewneck might find.
DEPOP_SOLD = "https://www.depop.com/products/seller-vintage-nike-grey-crewneck/"
DEPOP_ASKING = "https://www.depop.com/products/seller-nike-crewneck-m/"
DEPOP_SIMILAR = "https://www.depop.com/products/seller-champion-reverse-weave/"
DEPOP_POUNDS = "https://www.depop.com/products/seller-uk-nike-crewneck/"
DEPOP_NO_PRICE = "https://www.depop.com/products/seller-no-price-shown/"
NIKE_SHOP = "https://www.nike.com/t/sportswear-club-fleece-crew-example"


def depop_hits() -> list[dict[str, Any]]:
    return [
        hit(
            DEPOP_SOLD,
            title="Vintage Nike grey crewneck sweatshirt embroidered swoosh",
            content="Vintage Nike grey crewneck sweatshirt",
            raw="Vintage Nike grey crewneck sweatshirt embroidered swoosh. $32.00 Sold. "
            "Size M. Condition Used - Excellent. Shipping from $5.49.",
            score=0.9,
        ),
        hit(
            DEPOP_ASKING,
            title="Nike crewneck sweatshirt grey size M",
            raw="Nike crewneck sweatshirt grey size M. $28.00. Buy now. Used - Good.",
            score=0.8,
        ),
        hit(
            DEPOP_SIMILAR,
            title="Champion reverse weave crewneck grey",
            raw="Champion reverse weave crewneck grey, heavyweight. $35.00",
            score=0.6,
        ),
        hit(
            DEPOP_POUNDS,
            title="Nike crewneck grey UK seller",
            raw="Nike crewneck grey. Price £24.00. Ships from London.",
            score=0.5,
        ),
        hit(
            DEPOP_NO_PRICE,
            title="Nike crewneck sweatshirt",
            raw="Nike crewneck sweatshirt in grey. Message me for details.",
            score=0.4,
        ),
    ]


def retail_hits() -> list[dict[str, Any]]:
    return [
        hit(
            NIKE_SHOP,
            title="Nike Sportswear Club Fleece Crew",
            raw="Nike Sportswear Club Fleece Crew. $60.00. Free shipping on orders over $50.",
            score=0.9,
        )
    ]


def standard_tavily() -> Tavily:
    return Tavily(answer(*depop_hits()), answer(*retail_hits()))


# --- A search that ignored its filters, and a reader that lies ---------------

EBAY_LISTING = "https://www.ebay.com/itm/1234567890"
EBAY_RETAIL = "https://www.ebay.com/itm/9876543210"
POSHMARK_RETAIL = "https://poshmark.com/listing/nike-club-fleece-crew-5f3a"


def hostile_tavily() -> Tavily:
    """A search that ignored its own filters: eBay in the Depop results, and in the shops'.

    Numbered the way the service numbers them: the six Depop-search results are
    0 to 5 (the last is the eBay listing), and the three shop results are 6 to 8.
    """
    return Tavily(
        answer(
            *depop_hits(),
            hit(EBAY_LISTING, title="Nike crewneck grey - eBay", raw="Nike crewneck grey. $30.00"),
        ),
        answer(
            *retail_hits(),
            hit(EBAY_RETAIL, title="Nike Club Fleece crew - eBay", raw="Nike crew. $50.00"),
            hit(POSHMARK_RETAIL, title="Nike Club Fleece crew | Poshmark", raw="Nike crew. $55.00"),
        ),
    )


def claim_json(index: int, kind: str, price: float, currency: str = "USD", **extra: Any) -> Any:
    """One result the reader puts forward, as the reader's JSON has it."""
    return {
        "resultIndex": index,
        "kind": kind,
        "price": price,
        "currency": currency,
        "match": extra.pop("match", "same"),
        **extra,
    }


def lying_reader_says() -> dict[str, Any]:
    """What a model that is wrong in every way a model can be wrong might say.

    Against `hostile_tavily`: two good Depop listings and a similar one, one in
    pounds, one with a price the page does not show, an eBay listing called a
    comparable, a good shop, two resale sites called shops, a result that does
    not exist, and a link and a title nobody asked for.
    """
    return {
        "results": [
            claim_json(
                0,
                "listing",
                32,
                sold=True,
                condition="Used - Excellent",
                why="Same 90s Nike crewneck, also grey",
                url="https://www.depop.com/products/made-up-by-the-model/",
                title="A title the model made up",
            ),
            claim_json(1, "listing", 28, sold=False, why="Nike crewneck in grey, listed not sold"),
            claim_json(2, "listing", 35, match="similar", why="Comparable heavyweight crewneck"),
            claim_json(3, "listing", 24, currency="GBP"),
            claim_json(4, "listing", 40),
            claim_json(5, "listing", 30),
            claim_json(6, "retail", 60),
            claim_json(7, "retail", 50),
            claim_json(8, "retail", 55),
            claim_json(99, "listing", 10),
        ]
    }


# --- Wiring ------------------------------------------------------------------


def searcher_for(
    tavily: Tavily,
    reader: ComparableReader | None = None,
    cache: PriceCache | None = None,
    key: str | None = KEY,
    now: Callable[[], datetime] | None = None,
    **settings: Any,
) -> PriceSearcher:
    """A price searcher over mocked Tavily, with the pattern reader unless told otherwise."""
    extra: dict[str, Any] = {} if now is None else {"now": now}
    return PriceSearcher(
        tavily.search(key, **settings),
        reader or RegexComparableReader(),
        cache if cache is not None else PriceCache(ttl_seconds=3600, max_entries=50),
        **extra,
    )


@contextmanager
def serving(
    *,
    searcher: PriceSearcher | None = None,
    describer: ListingDescriber | None = None,
) -> Iterator[TestClient]:
    """A client for an app whose selling dependencies are the ones given."""
    app = create_app()
    if searcher is not None:
        app.dependency_overrides[get_price_searcher] = lambda: searcher
    if describer is not None:
        app.dependency_overrides[get_listing_describer] = lambda: describer
    with TestClient(app) as client:
        yield client


def price_request(**overrides: Any) -> dict[str, Any]:
    """The contract's example price search, with any key replaced."""
    body: dict[str, Any] = {
        "queries": {
            "depop": "Nike vintage crewneck sweatshirt grey",
            "retail": "Nike Club Fleece crew sweatshirt grey",
        },
        "itemType": "sweatshirt",
        "title": "Nike vintage crewneck sweatshirt grey",
        "brand": "Nike",
        "colors": ["Grey"],
    }
    body.update(overrides)
    return body
