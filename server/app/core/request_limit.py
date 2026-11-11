"""Request limits for the endpoints that spend somebody's free allowance.

The server has no accounts and a public address, and its AI endpoints draw on
the owner's free Gemini and Tavily allowances. Anyone who finds the address
could drain both. This is the simple, honest answer: a per-client limit per
minute and per day, and a global cap per day, all held in this process.

What it is, plainly:

* **In process.** Render's free plan runs one instance with no disk, so there is
  nothing to share state with. A restart or a spin-down forgets every count,
  which only ever lets more through, never less. Two instances would each keep
  their own.
* **Per network address, not per person.** Two people behind one router share a
  quota, and one person on mobile data can change address. That is why the
  message says "from this network".
* **Not a defence against a determined attacker.** Somebody who can rotate
  addresses gets a fresh quota per address; the *global* daily cap is the part
  that still holds, and it holds by refusing everybody, which is the point: it
  protects the allowance, not the service's availability.

Memory is bounded: at most `max_clients` addresses are tracked (least recently
seen is evicted) and each holds at most `per_day` timestamps. An evicted client
starts over with a clean quota, so flooding with many addresses can reset
*other* clients' counts; the global cap is unaffected.

A request answered from a cache (a price search already remembered) spends
nothing but still counts. Knowing that before the handler runs would couple the
limiter to every endpoint, and a limit that is a little strict beats one that
has to be taught about each route.
"""

from __future__ import annotations

import ipaddress
import math
import threading
import time
from collections import OrderedDict, deque
from collections.abc import Callable
from dataclasses import dataclass

from fastapi import Request

from app.config import get_settings
from app.core.errors import RateLimitedError

MINUTE = 60.0
DAY = 24 * 60 * 60.0

UNKNOWN_CLIENT = "unknown"
"""The key when no address can be read at all; such requests share one quota."""


@dataclass(frozen=True)
class Verdict:
    """The outcome of one check. `retry_after` is seconds, set only when refused."""

    allowed: bool
    scope: str | None = None
    """`"client"` or `"global"` when refused: whose limit was hit."""
    retry_after: float = 0.0


_ALLOWED = Verdict(allowed=True)


class RequestLimiter:
    """Sliding-window limits per client and overall. 0 turns a limit off.

    Refused requests are not recorded, so hammering a limit does not extend it.
    """

    def __init__(
        self,
        *,
        per_minute: int,
        per_day: int,
        global_per_day: int,
        max_clients: int = 2_000,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._per_minute = max(0, per_minute)
        self._per_day = max(0, per_day)
        self._global_per_day = max(0, global_per_day)
        self._max_clients = max(1, max_clients)
        self._clock = clock
        self._clients: OrderedDict[str, deque[float]] = OrderedDict()
        self._global: deque[float] = deque()
        self._lock = threading.Lock()

    @property
    def enabled(self) -> bool:
        return bool(self._per_minute or self._per_day or self._global_per_day)

    @property
    def tracked_clients(self) -> int:
        return len(self._clients)

    def check(self, client: str) -> Verdict:
        """Records the request and allows it, or refuses it and says for how long."""
        if not self.enabled:
            return _ALLOWED
        with self._lock:
            now = self._clock()
            stamps = self._clients.get(client)
            if stamps is None:
                stamps = deque()
            else:
                self._clients.move_to_end(client)
            self._expire(stamps, now - DAY)
            self._expire(self._global, now - DAY)

            wait = max(
                self._wait(stamps, self._per_minute, MINUTE, now),
                self._wait(stamps, self._per_day, DAY, now),
            )
            if wait > 0:
                self._remember(client, stamps)
                return Verdict(False, "client", wait)

            wait = self._wait(self._global, self._global_per_day, DAY, now)
            if wait > 0:
                self._remember(client, stamps)
                return Verdict(False, "global", wait)

            stamps.append(now)
            self._global.append(now)
            self._remember(client, stamps)
            return _ALLOWED

    def _remember(self, client: str, stamps: deque[float]) -> None:
        # A client with nothing recorded is not worth a slot.
        if stamps:
            self._clients[client] = stamps
            self._clients.move_to_end(client)
        else:
            self._clients.pop(client, None)
        while len(self._clients) > self._max_clients:
            self._clients.popitem(last=False)

    @staticmethod
    def _expire(stamps: deque[float], cutoff: float) -> None:
        while stamps and stamps[0] <= cutoff:
            stamps.popleft()

    @staticmethod
    def _wait(stamps: deque[float], limit: int, window: float, now: float) -> float:
        """Seconds until one more request fits in `window`, or 0 if it fits now."""
        if limit <= 0:
            return 0.0
        recent = [t for t in stamps if t > now - window]
        if len(recent) < limit:
            return 0.0
        # The limit-th most recent request is the one whose leaving frees a slot.
        return max(0.0, recent[-limit] + window - now)


# --- Who is asking ----------------------------------------------------------


def parse_forwarded_for(header: str | None) -> str | None:
    """The first address in an `X-Forwarded-For` value, normalised, or None.

    Accepts a bare IPv4 or IPv6, an IPv4 with a port, and a bracketed IPv6 with
    or without a port. Anything else, including an empty first entry, is None:
    a garbage value is never used as a key, because the caller would be
    handing the client a way to choose its own bucket name.
    """
    if not header:
        return None
    first = header.split(",", 1)[0].strip()
    return _normalise(first)


def _normalise(text: str) -> str | None:
    if not text:
        return None
    if text.startswith("["):
        end = text.find("]")
        if end < 0:
            return None
        text = text[1:end]
    elif text.count(":") == 1:
        text = text.split(":", 1)[0]  # IPv4:port
    try:
        address = ipaddress.ip_address(text)
    except ValueError:
        return None
    if isinstance(address, ipaddress.IPv6Address):
        if address.ipv4_mapped is not None:
            return str(address.ipv4_mapped)
        # A household or phone is handed a whole /64, so a client can rotate
        # through 2**64 addresses. Keyed by the prefix, they share one quota.
        return str(ipaddress.ip_network(f"{address}/64", strict=False))
    return str(address)


def client_key(request: Request, *, trust_forwarded_for: bool) -> str:
    """Who this request is from.

    Trust assumption, stated plainly: `X-Forwarded-For` is an ordinary header
    that a client can write. It is only meaningful when a proxy we control sets
    it. On Render the proxy does, so the first address is the caller's. Run
    this server directly on the internet and anyone can claim any address by
    sending the header, so set `RATE_LIMIT_TRUST_FORWARDED_FOR=false` there.
    """
    if trust_forwarded_for:
        forwarded = parse_forwarded_for(request.headers.get("x-forwarded-for"))
        if forwarded:
            return forwarded
    peer = request.client.host if request.client else None
    if not peer:
        return UNKNOWN_CLIENT
    return _normalise(peer) or peer


# --- The route dependency ---------------------------------------------------


def limiter_from_settings() -> RequestLimiter:
    settings = get_settings()
    return RequestLimiter(
        per_minute=settings.rate_limit_per_minute,
        per_day=settings.rate_limit_per_day,
        global_per_day=settings.rate_limit_global_per_day,
        max_clients=settings.rate_limit_max_clients,
    )


async def enforce_request_limit(request: Request) -> None:
    """Dependency for a whole router, so no endpoint body knows about it.

    Raises [RateLimitedError], which the error handler renders as a 429 in the
    usual envelope with `Retry-After`. The app shows `detail` and appends the
    wait itself, so the detail carries no number; the hint repeats it for any
    other client.
    """
    limiter: RequestLimiter | None = getattr(request.app.state, "request_limiter", None)
    if limiter is None:
        return
    key = client_key(request, trust_forwarded_for=get_settings().rate_limit_trust_forwarded_for)
    verdict = limiter.check(key)
    if verdict.allowed:
        return
    seconds = max(1, math.ceil(verdict.retry_after))
    if verdict.scope == "global":
        raise RateLimitedError(
            "The service has reached its daily limit.",
            retry_after=verdict.retry_after,
            hint=f"Try again in about {seconds} seconds.",
        )
    raise RateLimitedError(
        "Too many requests from this network.",
        retry_after=verdict.retry_after,
        hint=f"Try again in about {seconds} seconds.",
    )
