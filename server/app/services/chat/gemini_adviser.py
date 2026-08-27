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

`maxOutputTokens` is deliberately generous, which is the opposite of what it
looks like it should be. On these models the limit is a *combined* budget for
the model's thinking and its answer, so a tight cap does not produce a short
reply — the thinking spends it and the answer stops mid-sentence. Brevity is
the prompt's job. This number exists only so that a model which starts thinking
in circles stops rather than hanging, and an answer that does hit it is refused
rather than shown.
"""

from __future__ import annotations

from typing import Any

import httpx

from app.config import Settings, get_settings
from app.schemas.chat import ChatAnswer, ChatRequest
from app.services.ai.base import ProviderError
from app.services.ai.gemini_errors import gemini_error_reason
from app.services.chat.prompts import describe

MAX_OUTPUT_TOKENS = 2048
"""The ceiling on thinking *plus* answer.

Not a brevity control, though it reads like one. Set to 400 it produced
half-sentences: the model's reasoning consumed the budget and generation
stopped partway through the reply. The prompt asks for one to four sentences
and that is what keeps answers short; this is a stop on a runaway, since
omitting the field entirely lets a model think without bound.
"""


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
                "maxOutputTokens": MAX_OUTPUT_TOKENS,
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

        return self._answer_in(response.json())

    def _answer_in(self, payload: dict[str, Any]) -> str:
        """Pulls the answer out of a reply, refusing one that was cut off.

        Its own method so the shapes below can be tested without a network:
        every one of them was a live failure before it was a test.
        """
        try:
            candidate = payload["candidates"][0]
        except (KeyError, IndexError, TypeError) as error:
            raise ProviderError(self.name, f"unexpected response shape: {error}") from error

        # Checked before the text is read, not after. A truncated reply still
        # carries text, and that text is the dangerous kind: "a plain triangle
        # means you can" is a complete-looking sentence whose next word decides
        # whether somebody bleaches a garment. Half an answer about laundry is
        # worse than no answer, so this is an error rather than a shorter reply.
        if candidate.get("finishReason") == "MAX_TOKENS":
            raise ProviderError(
                self.name,
                "the answer was cut off before it finished",
            )

        try:
            parts = candidate["content"]["parts"]
        except (KeyError, TypeError) as error:
            # The shape a safety block comes back as: a candidate with a
            # finishReason and no content at all.
            raise ProviderError(self.name, f"unexpected response shape: {error}") from error

        # Every text part, not the first. A thinking model may put its
        # reasoning in one part and the answer in the next, and `parts[0]`
        # would then show the user the model working out what to say.
        text = "".join(
            part["text"]
            for part in parts
            if isinstance(part, dict) and not part.get("thought") and "text" in part
        )
        if not text.strip():
            raise ProviderError(self.name, "the model returned an empty answer")
        return text
