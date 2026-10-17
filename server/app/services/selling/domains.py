"""Which sites a price may come from.

The two searches are told where to look (`include_domains`, `exclude_domains`)
and the vetting is told where a result must be, from the same constants. Written
twice they would drift, and the day they did a resale listing would be shown as
what a shop charges new.

Hosts are taken apart with a URL parser and compared as whole labels. A check
that looked for "depop.com" anywhere in the string would pass
`https://depop.com.evil.example/` and `https://evil.example/?u=depop.com`, and
the whole point of the vetting is that the link on the screen goes where it says.
"""

from __future__ import annotations

import re
from urllib.parse import urlsplit

COMPARABLE_DOMAIN = "depop.com"
"""Where a comparable must be: a listing on Depop, and nowhere else."""

RESALE_DOMAINS: tuple[str, ...] = (
    "depop.com",
    "ebay.com",
    "poshmark.com",
    "mercari.com",
    "grailed.com",
    "vinted.com",
    "thredup.com",
    "therealreal.com",
    "vestiairecollective.com",
    "etsy.com",
    "facebook.com",
)
"""Where a price new must not come from.

A used price offered as the price new would put a used-and-worn asking price in
the slot a used item is capped by. Sent to the search as `exclude_domains`, and
checked again on every result that comes back, because a search that is asked to
exclude something is not thereby guaranteed to have done so.
"""

MAX_URL_CHARS = 2048
"""The longest link the contract carries."""

# The name a resale site goes by, without its suffix: "ebay" for ebay.com, and
# so for ebay.co.uk and ebay.com.au, which are the same marketplace in another
# country and which no list of exact domains will ever be long enough to hold.
_RESALE_NAMES = frozenset(domain.split(".")[0] for domain in RESALE_DOMAINS)

_TRACKING_PARAMETER = re.compile(r"^(?:utm_.*|fbclid|gclid|mc_.*|ref|ref_.*)$", re.IGNORECASE)


def host_of(url: str) -> str | None:
    """The host of an https link, lower-cased, or None for anything else.

    None for a link that is not https, has no host, is longer than the contract
    allows, or has in it anything a browser and a URL parser can read
    differently: whitespace or control characters, a backslash, or a user name
    in front of the host. A link the person is going to tap has to open where it
    says, and the parser here is not the one that opens it. `https://evil.example\\@depop.com/`
    is the host `depop.com` to this parser (a user name, then a host) and
    `evil.example` to a browser (a host, then a path), because a browser reads a
    backslash as a slash. A genuine product link has none of these.
    """
    link = url.strip()
    if not link or len(link) > MAX_URL_CHARS:
        return None
    if "\\" in link or any(character.isspace() or ord(character) < 32 for character in link):
        return None

    try:
        parts = urlsplit(link)
        host = parts.hostname
    except ValueError:
        return None

    if parts.scheme.lower() != "https" or not host or "@" in parts.netloc:
        return None
    return host.rstrip(".") or None


def is_on(host: str, domain: str) -> bool:
    """Whether [host] is [domain] or a subdomain of it, and not merely similar."""
    return host == domain or host.endswith(f".{domain}")


def is_resale(host: str) -> bool:
    """Whether [host] is a second-hand marketplace, in any country."""
    # Every label but the last, so the suffix is never mistaken for a name.
    return any(label in _RESALE_NAMES for label in host.split(".")[:-1])


def shop_name(host: str) -> str:
    """A shop as its domain, the way the contract's `seller` says it: 'nike.com'."""
    return host.removeprefix("www.")


def canonical_url(url: str) -> str:
    """A key under which two links to one page are equal.

    Without the scheme, a leading `www.`, a trailing slash, the fragment, or the
    parameters that only say where a click came from. Two search results for one
    listing arrive under both spellings, and showing it twice would count one
    sale as two.
    """
    link = url.strip()
    try:
        parts = urlsplit(link)
        host = (parts.hostname or "").lower().removeprefix("www.")
    except ValueError:
        return link.lower()

    path = parts.path.rstrip("/") or "/"
    pairs = [
        pair
        for pair in parts.query.split("&")
        if pair and not _TRACKING_PARAMETER.match(pair.split("=", 1)[0])
    ]
    query = f"?{'&'.join(sorted(pairs))}" if pairs else ""
    return f"{host}{path}{query}"
