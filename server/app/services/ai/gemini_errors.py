"""Turning a failed Gemini response into something an operator can act on.

Shared by every caller of the Gemini API in this service — first the vision
provider, now the machine identifier too — because a bare HTTP status code is
never diagnosable on its own: a 404 means "no such model for this API
version" and only Google's own reply says *which* model, which is the entire
difference between an operator correcting one environment variable and
guessing at it.
"""

from __future__ import annotations

import httpx


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
