"""Asking Gemini what goes with what.

The same shape as `GeminiStainAdviser` — one client held for the object's
lifetime, a structured-output call retried once on invalid JSON — with one
difference that matters: the temperature is high.

Everywhere else in this service it is 0.1, because those calls are recall. The
standard treatment for blood on wool is a fact, and a creative answer about it
is a wrong one. This call is the exception: it is asking for taste, and a
stylist that returns the same four safe pairings every time is one nobody asks
twice. Asking for five ideas and getting five variations on navy-and-white is
the failure mode here, and low temperature is how you get it.

No photographs are sent. The wardrobe arrives as text because the app already
holds these facts, and re-deriving them from forty pictures would cost a
multiple of the time for answers it is surer about than a fresh glance.
"""

from __future__ import annotations

import json
from typing import Any

import httpx
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.schemas.style import ProposedOutfit, StyleRequest
from app.services.ai.base import ProviderError
from app.services.ai.gemini_errors import gemini_error_reason
from app.services.style.prompts import STYLE_SCHEMA, describe


class GeminiStylist:
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

    @classmethod
    def from_settings(cls, settings: Settings | None = None) -> GeminiStylist:
        resolved = settings or get_settings()
        if not resolved.gemini_api_key:
            raise ProviderError(
                "gemini",
                "GEMINI_API_KEY is not set; select the 'fake' provider or supply a key",
            )
        return cls(
            api_key=resolved.gemini_api_key,
            model=resolved.gemini_model,
            base_url=resolved.gemini_base_url,
            timeout_seconds=resolved.gemini_timeout_seconds,
        )

    @property
    def name(self) -> str:
        return "gemini"

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=self._timeout)
        return self._client

    async def aclose(self) -> None:
        if self._client is not None and self._injected_client is None:
            await self._client.aclose()
            self._client = None

    async def propose(self, request: StyleRequest) -> list[ProposedOutfit]:
        if not request.wardrobe:
            raise ProviderError(self.name, "no wardrobe to choose from")

        data = await self._generate([{"text": describe(request)}])
        try:
            return _parse(data)
        except (ValidationError, ValueError, KeyError, TypeError) as error:
            raise ProviderError(self.name, f"invalid outfits: {error}") from error

    def _body(self, parts: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "contents": [{"parts": parts}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": STYLE_SCHEMA,
                # Deliberately high, and the only call in this service that is.
                # See the module docstring: taste asked for at 0.1 comes back as
                # the same four safe pairings every time.
                "temperature": 0.9,
            },
        }

    async def _generate(self, parts: list[dict[str, Any]]) -> dict[str, Any]:
        body = self._body(parts)

        last_error: str | None = None
        for attempt in range(2):
            if last_error is not None:
                retry = dict(parts[0])
                retry["text"] = (
                    f"{parts[0]['text']}\n\nYour previous reply could not be "
                    f"parsed: {last_error}\nReturn only JSON matching the schema."
                )
                body["contents"][0]["parts"] = [retry, *parts[1:]]

            raw = await self._post(body)
            try:
                return json.loads(raw)  # type: ignore[no-any-return]
            except json.JSONDecodeError as error:
                last_error = str(error)
                if attempt == 1:
                    raise ProviderError(
                        self.name, f"model did not return valid JSON: {error}"
                    ) from error

        raise ProviderError(self.name, "exhausted retries")

    async def _post(self, body: dict[str, Any]) -> str:
        url = f"{self._base_url}/models/{self._model}:generateContent"
        headers = {"x-goog-api-key": self._api_key}

        try:
            response = await self._http().post(url, json=body, headers=headers)
        except httpx.HTTPError as error:
            raise ProviderError(self.name, f"request failed: {error}") from error

        if response.status_code != 200:
            raise ProviderError(
                self.name,
                f"HTTP {response.status_code} from the Gemini API{gemini_error_reason(response)}",
            )

        payload = response.json()
        try:
            return str(payload["candidates"][0]["content"]["parts"][0]["text"])
        except (KeyError, IndexError, TypeError) as error:
            raise ProviderError(self.name, f"unexpected response shape: {error}") from error


def _parse(data: dict[str, Any]) -> list[ProposedOutfit]:
    """Builds the response, refusing one that proposes nothing.

    An empty list is not a usable answer: the endpoint would return a success
    carrying no ideas, and the app would draw a heading with nothing under it.
    Failing here reads as a provider problem and offers the user a retry, which
    on this endpoint often works — the temperature is high enough that the same
    request twice is genuinely a second attempt.
    """
    outfits = [ProposedOutfit.model_validate(outfit) for outfit in data.get("outfits", [])]
    if not outfits:
        raise ValueError("no outfits returned")

    return outfits
