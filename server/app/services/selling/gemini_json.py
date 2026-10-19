"""One structured-output call to Gemini, validated and retried once.

Both Gemini calls in the selling feature — the describer, which sends
photographs, and the comparable reader, which sends search results as text —
make the same call and differ only in what goes in and what is accepted back.
Written twice they would be two copies of the transport and of the error
mapping, and the second copy is where a rate limit stops being reported as one.
So the call is made here, and each caller supplies its prompt, its response
schema and a function that turns the reply into its own result.

The contract with the caller is the one the vision provider keeps. A response
schema is sent with the request, and the reply is parsed and then *validated*:
a model that returns prose where an enum was required is a bug to surface, not
to paper over, so a reply that does not parse or does not validate is retried
once with the problem fed back and then raises. The vision provider retries on
invalid JSON only; here the caller's own validation counts too, because for both
callers a well-formed reply that breaks the contract is the likelier failure.

Failures are reported the way every other Gemini call here reports them: a rate
limit carries how long to wait, and nothing else leaks the body of a response,
which can echo the request back — here, someone's photographs or a page of text.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any, TypeVar

import httpx
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.schemas.base import validation_problems
from app.services.ai.base import ProviderError
from app.services.ai.gemini_errors import gemini_error_reason, retry_after_seconds

T = TypeVar("T")

_MAX_PROBLEM_CHARS = 600
"""How much of what was wrong with a reply is fed back to the model.

Enough to name the field and the rule. Not unbounded, because the problem is
built from the reply, and a degenerate reply is exactly the one that is long.
"""


def gemini_arguments(settings: Settings | None = None) -> dict[str, Any]:
    """The constructor arguments the settings describe, for `from_settings`.

    Every Gemini caller here builds itself from the same four settings and
    refuses to be built without the key, so that is written once.
    """
    resolved = settings or get_settings()
    if not resolved.gemini_api_key:
        raise ProviderError(
            "gemini",
            "GEMINI_API_KEY is not set; select the 'fake' provider or supply a key",
        )
    return {
        "api_key": resolved.gemini_api_key,
        "model": resolved.gemini_model,
        "base_url": resolved.gemini_base_url,
        "timeout_seconds": resolved.gemini_timeout_seconds,
    }


class GeminiStructured:
    """Calls Gemini with a response schema and hands back a validated result."""

    def __init__(
        self,
        api_key: str,
        *,
        model: str = "gemini-3.6-flash",
        base_url: str = "https://generativelanguage.googleapis.com/v1beta",
        timeout_seconds: float = 45.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        if not api_key:
            raise ProviderError("gemini", "no API key configured")
        self._api_key = api_key
        self._model = model
        self._base_url = base_url.rstrip("/")
        self._timeout = timeout_seconds
        self._injected_client = client
        self._client: httpx.AsyncClient | None = client

    @property
    def name(self) -> str:
        return "gemini"

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=self._timeout)
        return self._client

    async def aclose(self) -> None:
        """Releases the connection pool, if this call made it.

        An injected client belongs to whoever passed it in.
        """
        if self._client is not None and self._injected_client is None:
            await self._client.aclose()
            self._client = None

    async def generate(
        self,
        parts: list[dict[str, Any]],
        schema: dict[str, Any],
        parse: Callable[[Any], T],
        *,
        temperature: float,
    ) -> T:
        """Sends [parts] and returns what [parse] makes of the reply.

        [parse] gets the decoded JSON and must raise `ValueError`, `KeyError`,
        `TypeError` or a Pydantic `ValidationError` for a reply it cannot use.
        The first part is the prompt, and is the one the problem is appended to
        on the retry; the rest (photographs, usually) are sent again untouched.
        """
        body: dict[str, Any] = {
            "contents": [{"parts": parts}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": schema,
                # Extraction and composition from evidence, not taste. A
                # creative reading of a size label is a wrong one.
                "temperature": temperature,
            },
        }

        problem: str | None = None
        for attempt in range(2):
            if problem is not None:
                retry = dict(parts[0])
                retry["text"] = (
                    f"{parts[0]['text']}\n\nYour previous reply could not be used: "
                    f"{problem}\nReturn only JSON matching the schema."
                )
                body["contents"][0]["parts"] = [retry, *parts[1:]]

            raw = await self._post(body)
            try:
                return parse(json.loads(raw))
            except json.JSONDecodeError as error:
                problem = f"it was not valid JSON ({error})"
            except (ValidationError, ValueError, KeyError, TypeError) as error:
                problem = _summarise(error)

            if attempt == 1:
                raise ProviderError(self.name, f"the reply could not be used: {problem}")

        raise ProviderError(self.name, "exhausted retries")

    async def _post(self, body: dict[str, Any]) -> str:
        url = f"{self._base_url}/models/{self._model}:generateContent"
        # The key goes in a header, not the query string: URLs are logged by
        # proxies and error trackers as a matter of course.
        headers = {"x-goog-api-key": self._api_key}

        try:
            response = await self._http().post(url, json=body, headers=headers)
        except (httpx.HTTPError, UnicodeError) as error:
            # UnicodeError because a key pasted with a curly quote in it fails
            # as the client builds the header, with an error that is not one of
            # the client's own, and which would otherwise come out as a 400.
            raise ProviderError(self.name, f"request failed: {error}") from error

        if response.status_code == 429:
            # The free tier's ordinary failure, and a temporary one. Said as
            # such, with the wait, so the client holds off rather than retrying
            # straight back into the limit.
            raise ProviderError(
                self.name,
                f"rate limited by the Gemini API{gemini_error_reason(response)}",
                retry_after=retry_after_seconds(response),
            )

        if response.status_code != 200:
            raise ProviderError(
                self.name,
                f"HTTP {response.status_code} from the Gemini API{gemini_error_reason(response)}",
            )

        try:
            payload = response.json()
        except ValueError as error:
            raise ProviderError(self.name, f"unexpected response shape: {error}") from error
        return _text_of(payload)


def _text_of(payload: Any) -> str:
    """The reply's text, from every part that is not the model thinking aloud.

    A thinking model may put its reasoning in one part and the answer in the
    next, and taking the first part would hand the reasoning to the JSON parser.
    A candidate with no content at all is what a safety block looks like.
    """
    try:
        parts = payload["candidates"][0]["content"]["parts"]
        text = "".join(
            part["text"]
            for part in parts
            if isinstance(part, dict) and not part.get("thought") and "text" in part
        )
    except (KeyError, IndexError, TypeError) as error:
        raise ProviderError("gemini", f"unexpected response shape: {error}") from error

    if not text.strip():
        raise ProviderError("gemini", "unexpected response shape: the reply had no text")
    return text


def _summarise(error: Exception) -> str:
    """What was wrong with a reply, short enough to put back in a prompt.

    A Pydantic error's `str()` quotes the offending input, which here may be a
    page of web text; the field and the rule are what the model can act on.
    """
    if isinstance(error, ValidationError):
        summary = "; ".join(validation_problems(error))
    else:
        summary = str(error) or type(error).__name__
    return summary[:_MAX_PROBLEM_CHARS]
