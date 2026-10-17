"""The web search that prices come from.

Tavily, behind the `WebSearch` seam: a search API with a free monthly allowance
and no card, which is the whole reason it is here. Google's own search grounding
is not free on the models this app can use (docs/adr/0009-selling-on-depop.md),
and the project rule is that AI usage stays free.

Everything in this module is about spending that allowance carefully, and about
never letting the service's trouble become the app's.

**Credits.** A `basic` search costs one credit and an `advanced` one costs two,
so it is always `basic`; `auto_parameters` lets the service pick the depth for
itself and would quietly double the bill, so it is never sent. Two searches a
price lookup is about five hundred lookups a month on the free allowance.

**Failures are statuses, not errors.** A listing can be written without a price
search, so nothing here raises anything but `SearchError`, carrying the status
the endpoint will report: no key is `notConfigured` and no request is made at
all, the service's own allowance and rate-limit codes (432, 433, 429) are
`quotaExceeded`, and everything else — a rejected key, a timeout, a 5xx, a reply
that is not the JSON it should be — is `unavailable`.

**The key** goes in the `Authorization` header and nowhere else. It is never in
the address, never in a message, never in a log line: a rejected key is logged as
"search key rejected" and nothing more.

**Page text is cut to four thousand characters** the moment it arrives, before it
is stored, passed on or put in a prompt. A page is as long as it likes, and what
the price is looked for in, and what a model is shown, should not be.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from app.config import Settings, get_settings
from app.schemas.selling import PriceSearchStatus
from app.services.selling.base import SearchError, SearchHit, SearchRequest

logger = logging.getLogger(__name__)

SEARCH_DEPTH = "basic"
"""One credit a search. `advanced` is two, and is never used."""

MAX_RAW_CONTENT_CHARS = 4_000
"""How much of a page's text is kept. Enough for a listing's price and details."""

_MAX_SNIPPET_CHARS = 2_000
_MAX_TITLE_CHARS = 300

# What the service answers when the free allowance is spent: 432 is the plan's
# limit, 433 the pay-as-you-go limit, and 429 the rate limit. All three are
# "not now", and none of them is the app's fault or something it can fix.
_QUOTA_STATUSES = frozenset({429, 432, 433})

# A key that is missing, wrong or revoked. An operator's problem rather than the
# person's, so it is logged and then reported as the service being unavailable.
_KEY_STATUSES = frozenset({401, 403})


class TavilySearch:
    def __init__(
        self,
        api_key: str | None,
        *,
        base_url: str = "https://api.tavily.com",
        timeout_seconds: float = 20.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._api_key = api_key or None
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds
        self._injected_client = client
        self._client: httpx.AsyncClient | None = client

    @classmethod
    def from_settings(cls, settings: Settings | None = None) -> TavilySearch:
        resolved = settings or get_settings()
        return cls(
            resolved.tavily_api_key,
            base_url=resolved.tavily_base_url,
            timeout_seconds=resolved.tavily_timeout_seconds,
        )

    @property
    def name(self) -> str:
        return "tavily"

    @property
    def configured(self) -> bool:
        return self._api_key is not None

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=self._timeout)
        return self._client

    async def aclose(self) -> None:
        """Releases the connection pool, if this search made it.

        An injected client belongs to whoever passed it in.
        """
        if self._client is not None and self._injected_client is None:
            await self._client.aclose()
            self._client = None

    async def search(self, request: SearchRequest) -> list[SearchHit]:
        if self._api_key is None:
            raise SearchError(PriceSearchStatus.NOT_CONFIGURED, "no search key is configured")

        if not (self._api_key.isascii() and self._api_key.isprintable()):
            # A key pasted with a curly quote or a control character in it
            # cannot be put in a header, and the HTTP client says so with an
            # error that is not one of its own. Caught here, before any request,
            # and said without saying what the key is.
            logger.warning("search key unusable: it has characters a header cannot carry")
            raise SearchError(PriceSearchStatus.UNAVAILABLE, "the search key cannot be sent")

        try:
            response = await self._http().post(
                f"{self._base_url}/search",
                json=_body(request),
                headers={"Authorization": f"Bearer {self._api_key}"},
            )
        except (httpx.HTTPError, httpx.InvalidURL, UnicodeError) as error:
            # The class of failure and nothing else. An exception's message can
            # carry the address it was talking to, and the address is the
            # operator's to keep.
            logger.warning("price search failed: %s", type(error).__name__)
            raise SearchError(
                PriceSearchStatus.UNAVAILABLE,
                f"the search service did not answer ({type(error).__name__})",
            ) from error

        status = response.status_code
        if status in _QUOTA_STATUSES:
            logger.warning("price search allowance used up (HTTP %s)", status)
            raise SearchError(
                PriceSearchStatus.QUOTA_EXCEEDED,
                f"the search service's allowance is used up (HTTP {status})",
            )
        if status in _KEY_STATUSES:
            logger.warning("search key rejected (HTTP %s)", status)
            raise SearchError(
                PriceSearchStatus.UNAVAILABLE,
                f"the search service rejected the key (HTTP {status})",
            )
        if status != 200:
            logger.warning("price search failed: HTTP %s", status)
            raise SearchError(
                PriceSearchStatus.UNAVAILABLE,
                f"the search service answered HTTP {status}",
            )

        return _hits(response)


def _body(request: SearchRequest) -> dict[str, Any]:
    """The request as Tavily takes it.

    Domain lists are sent only when there is something in them: an empty
    `include_domains` is not "anywhere", it is a filter the service may read as
    matching nothing.
    """
    body: dict[str, Any] = {
        "query": request.query,
        "search_depth": SEARCH_DEPTH,
        "max_results": request.max_results,
        "include_raw_content": "text",
        # `country` only applies to the general topic, which is also the
        # default. Said outright so the pair cannot come apart.
        "topic": "general",
        "country": "united states",
    }
    if request.include_domains:
        body["include_domains"] = list(request.include_domains)
    if request.exclude_domains:
        body["exclude_domains"] = list(request.exclude_domains)
    return body


def _hits(response: httpx.Response) -> list[SearchHit]:
    """The results in a reply, each trimmed to the lengths this service keeps."""
    try:
        results = response.json()["results"]
    except (ValueError, KeyError, TypeError) as error:
        logger.warning("price search failed: the reply was not a result list")
        raise SearchError(
            PriceSearchStatus.UNAVAILABLE, "the search service's reply was malformed"
        ) from error

    if not isinstance(results, list):
        logger.warning("price search failed: the reply was not a result list")
        raise SearchError(PriceSearchStatus.UNAVAILABLE, "the search service's reply was malformed")

    hits: list[SearchHit] = []
    for entry in results:
        if not isinstance(entry, dict):
            continue
        url = entry.get("url")
        # A result with no link is one that can never be shown or checked.
        if not isinstance(url, str) or not url.strip():
            continue
        hits.append(
            SearchHit(
                title=_text(entry.get("title"), _MAX_TITLE_CHARS),
                url=url.strip(),
                content=_text(entry.get("content"), _MAX_SNIPPET_CHARS),
                raw_content=_text(entry.get("raw_content"), MAX_RAW_CONTENT_CHARS),
                score=_score(entry.get("score")),
            )
        )
    return hits


def _text(value: object, limit: int) -> str:
    return value[:limit] if isinstance(value, str) else ""


def _score(value: object) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0.0
    return float(value)
