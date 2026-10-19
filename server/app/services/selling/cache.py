"""Remembering a price search, so opening a listing again does not search again.

Every search spends credits from a free allowance that is shared with every other
listing, and a listing is opened far more often than the market for a grey
sweatshirt moves: the seller looks, goes away to photograph a flaw, comes back.
Two searches a visit, repeated, is the allowance gone by the second week.

An in-process cache, bounded and expiring, and honest about what it holds:

* **Keyed by what was searched, not by who asked.** The two search phrases, the
  item type and the brand, normalised so that "Nike Hoodie" and "nike  hoodie"
  are one search. The title and the colours are left out on purpose: they
  decide nothing about what the search finds, and a seller who corrects a typo
  in the title should not pay again for it.
* **Only answers.** A search that found something, or found nothing, is a fact
  about the market worth six hours. A search that failed is a fact about the last
  thirty seconds, and caching it would keep a listing without prices for six
  hours after the service came back.
* **Its own time.** What a hit returns keeps the `searchedAt` it was stored
  with, so a price checked this morning says this morning.

One instance holds all of this. A process that restarts forgets, which only
costs a search, and a second process would keep its own; the cache sits behind
the searcher and not in front of the endpoint, so a shared one is a change in
one place when the service is run as more than one.
"""

from __future__ import annotations

import time
import unicodedata
from collections import OrderedDict
from collections.abc import Callable
from dataclasses import dataclass

from app.schemas.selling import PriceSearch, PriceSearchRequest, PriceSearchStatus

CacheKey = tuple[str, str, str, str]


def cache_key(request: PriceSearchRequest) -> CacheKey:
    """The search a request amounts to: its two phrases, its type and its brand."""
    return (
        _fold(request.queries.depop),
        _fold(request.queries.retail),
        request.item_type.value,
        _fold(request.brand or ""),
    )


def _fold(text: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", text).casefold().split())


@dataclass(frozen=True, slots=True)
class _Entry:
    stored_at: float
    value: PriceSearch


class PriceCache:
    """A bounded, expiring, least-recently-used cache of answered searches."""

    def __init__(
        self,
        *,
        ttl_seconds: float,
        max_entries: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._ttl = ttl_seconds
        self._max_entries = max_entries
        # Injected so a test can move time without sleeping through it.
        self._clock = clock
        self._entries: OrderedDict[CacheKey, _Entry] = OrderedDict()

    @property
    def enabled(self) -> bool:
        """Whether anything is ever kept. A lifetime or a size of zero turns it off."""
        return self._ttl > 0 and self._max_entries > 0

    def get(self, key: CacheKey) -> PriceSearch | None:
        entry = self._entries.get(key)
        if entry is None:
            return None
        if self._expired(entry):
            del self._entries[key]
            return None
        self._entries.move_to_end(key)
        return entry.value

    def put(self, key: CacheKey, value: PriceSearch) -> None:
        # Refused here as well as by the caller: a failure kept for six hours is
        # a listing without prices for six hours after the service recovered,
        # and this is the one place that cannot be forgotten.
        if not self.enabled or value.status is not PriceSearchStatus.OK:
            return

        self._drop_expired()
        self._entries[key] = _Entry(self._clock(), value)
        self._entries.move_to_end(key)
        while len(self._entries) > self._max_entries:
            self._entries.popitem(last=False)

    def __len__(self) -> int:
        return len(self._entries)

    def _expired(self, entry: _Entry) -> bool:
        return self._clock() - entry.stored_at >= self._ttl

    def _drop_expired(self) -> None:
        # Cheap, because the cache is small by construction, and it keeps a
        # long-running process from holding answers nobody can be served.
        for key in [key for key, entry in self._entries.items() if self._expired(entry)]:
            del self._entries[key]
