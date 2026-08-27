"""Asking Gemini a question about somebody's wardrobe.

The same shape as `GeminiStylist` — one client held for the object's lifetime,
one POST, the same error translation — with two differences.

There is no response schema and no retry-on-invalid-JSON, because the answer is
prose. There is nothing to parse, so there is nothing that can come back
unparseable; the only bad reply is an empty one, and that is refused rather than
retried, since a second identical request is unlikely to produce a first
sentence where there was none.

And the temperature is low. The stylist runs hot because it is being asked for
taste and the failure there is four safe pairings every time. This is the
opposite: it is being asked what a care symbol means and whether wool goes in a
dryer, and a creative answer to that is a wrong one.
"""

from __future__ import annotations

from typing import Any

import httpx

from app.config import Settings, get_settings
from app.schemas.chat import ChatAnswer, ChatRequest
from app.services.ai.base import ProviderError
from app.services.ai.gemini_errors import gemini_error_reason
from app.services.chat.prompts import describe


class GeminiChatAdviser:
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
    def from_settings(cls, settings: Settings | None = None) -> GeminiChatAdviser:
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

    async def answer(self, request: ChatRequest) -> ChatAnswer:
        reply = (await self._post(self._body(request))).strip()
        if not reply:
            raise ProviderError(self.name, "the model returned an empty answer")
        return ChatAnswer(reply=reply)

    def _body(self, request: ChatRequest) -> dict[str, Any]:
        return {
            "contents": [{"parts": [{"text": describe(request)}]}],
            "generationConfig": {
                # Low, unlike the stylist. See the module docstring.
                "temperature": 0.2,
                # Enough for a considered answer to a real question and not
                # enough for an essay. The prompt asks for one to four
                # sentences; this is what stops a model that ignores it from
                # filling a phone screen.
                "maxOutputTokens": 400,
            },
        }

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
            # Covers the shape a safety block comes back as, which has
            # candidates but no parts. The message names the shape rather than
            # guessing at the cause.
            raise ProviderError(self.name, f"unexpected response shape: {error}") from error
