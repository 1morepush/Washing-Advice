"""Who a synced wardrobe belongs to.

## A capability token, not an account system

There is no signup, no password and no email. The client generates a long
random token, keeps it, and sends it as a bearer credential; the server stores
data under the token's SHA-256 and never sees or stores the token itself.
Whoever holds the token owns that wardrobe.

This is a real design — the same shape as a capability URL — and it is chosen
because the alternative is an identity system with password hashing, recovery
flows and email delivery, none of which a personal wardrobe relay needs to be
useful. It is not chosen because it is equivalent. The limits, stated plainly
so nobody has to infer them:

* **No recovery.** Lose the token and the data is unreachable. It is the only
  credential.
* **No revocation.** A leaked token cannot be invalidated; the remedy is to
  generate a new one and re-sync, abandoning the old bucket.
* **No sharing or multi-user.** One token is one wardrobe.
* **Transport is the only confidentiality.** The token is a bearer credential,
  so it must travel over TLS. The service refuses to accept sync over plain
  HTTP unless explicitly configured otherwise for local development.

Hashing before storage means a dump of the database does not hand an attacker
working credentials — they would still have to invert SHA-256. It does not make
a weak token safe, which is why the length is enforced rather than suggested.
"""

from __future__ import annotations

import hashlib

# 32 hex characters is 128 bits, which is past any brute-force worth modelling.
# Enforced rather than recommended: this token is the only thing standing
# between a wardrobe and anyone who guesses it, and a client that shipped a
# four-character default would fail silently and forever.
MIN_TOKEN_LENGTH = 32


class InvalidTokenError(ValueError):
    """The presented token cannot identify an account."""


def account_for(token: str) -> str:
    """The storage key for a token.

    SHA-256 rather than a password hash: this is a high-entropy random secret,
    not a human-chosen password, so there is no dictionary to slow down and a
    deliberately slow KDF would only add latency to every request.
    """
    cleaned = token.strip()
    if len(cleaned) < MIN_TOKEN_LENGTH:
        raise InvalidTokenError(f"a sync token must be at least {MIN_TOKEN_LENGTH} characters")
    return hashlib.sha256(cleaned.encode("utf-8")).hexdigest()
