"""Turning a failed Gemini response into something an operator can act on.

Shared by every caller of the Gemini API in this service — first the vision
provider, now the machine identifier too — because a bare HTTP status code is
never diagnosable on its own: a 404 means "no such model for this API
version" and only Google's own reply says *which* model, which is the entire
difference between an operator correcting one environment variable and
guessing at it.
"""

from __future__ import annotations

from datetime import UTC, datetime
from email.utils import parsedate_to_datetime

import httpx

# What a 429 with no `Retry-After` is taken to mean. The free tier's limits
# are per minute, so a minute is the longest a bare 429 can be asking for;
# half of it is the usual wait, and a client that waits it and is still
# refused will be told again.
DEFAULT_RETRY_AFTER_SECONDS = 30.0


def gemini_error_reason(response: httpx.Response) -> str:
    """Google's own explanation for a failed call, if it gave one.

    Reads only `error.message` from the documented error envelope — a short
    diagnostic string such as "models/gemini-9 is not found for API version
    v1beta". Anything else in the body is ignored rather than trusted, so a
    response that is not that envelope contributes nothing. The body is never
    included verbatim: an error body can echo the request back, including
    image data.
    """
    try:
        error = response.json().get("error")
    except (ValueError, AttributeError):
        return ""

    if not isinstance(error, dict):
        return ""

    message = error.get("message")
    if not isinstance(message, str) or not message.strip():
        return ""

    return f": {message.strip()[:300]}"


def retry_after_seconds(response: httpx.Response) -> float:
    """How long a 429 asked to be left alone for, in seconds.

    From `Retry-After`, which the standard allows as either a number of seconds
    or an HTTP date. Absent or unreadable, the default above — never nothing,
    because a rate limit with no wait attached is a retry into the same wall.
    """
    header = response.headers.get("retry-after", "").strip()
    if not header:
        return DEFAULT_RETRY_AFTER_SECONDS
    if header.isdigit():
        return float(header)
    try:
        at = parsedate_to_datetime(header)
    except (TypeError, ValueError):
        return DEFAULT_RETRY_AFTER_SECONDS
    if at.tzinfo is None:
        at = at.replace(tzinfo=UTC)
    return max(0.0, (at - datetime.now(UTC)).total_seconds())
