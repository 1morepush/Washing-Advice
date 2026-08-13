"""Asking Gemini how to treat a stain.

The same shape as `GeminiMachineIdentifier` — one client held for the object's
lifetime, a structured-output call retried once on invalid JSON — with one
difference: a photograph may be attached. It is optional and it is
corroborating only. What was spilled is something the user knows and a close-up
of a mark on fabric is genuinely hard to read, so the description leads and the
picture, when present, only refines it.

Temperature is low for the same reason it is low when identifying a machine:
this is recall of a standard treatment, not composition. A creative answer
about how to get blood out of wool is a wrong one.
"""

from __future__ import annotations

import base64
import json
from typing import Any

import httpx
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.schemas.stains import StainAdvice, StainAdviceRequest, TreatmentStep
from app.services.ai.base import ProviderError, ScanImage
from app.services.ai.gemini_errors import gemini_error_reason
from app.services.stains.prompts import STAIN_SCHEMA, describe


class GeminiStainAdviser:
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
    def from_settings(cls, settings: Settings | None = None) -> GeminiStainAdviser:
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

    async def advise(
        self,
        request: StainAdviceRequest,
        image: ScanImage | None = None,
    ) -> StainAdvice:
        prompt = describe(
            request.substance,
            request.fabric,
            request.color,
            request.care,
            request.note,
        )

        parts: list[dict[str, Any]] = [{"text": prompt}]
        if image is not None:
            parts.append(
                {
                    "inlineData": {
                        "mimeType": image.mime_type,
                        "data": base64.b64encode(image.data).decode("ascii"),
                    }
                }
            )

        data = await self._generate(parts)
        try:
            return _parse(data)
        except (ValidationError, ValueError, KeyError, TypeError) as error:
            raise ProviderError(self.name, f"invalid stain advice: {error}") from error

    async def _generate(self, parts: list[dict[str, Any]]) -> dict[str, Any]:
        body: dict[str, Any] = {
            "contents": [{"parts": parts}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": STAIN_SCHEMA,
                "temperature": 0.1,
            },
        }

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


def _parse(data: dict[str, Any]) -> StainAdvice:
    """Builds the response, refusing one that says nothing.

    An empty step list is not a usable answer — the endpoint would return a
    success carrying no advice, and the app would show a screen with a heading
    and nothing under it. Better to fail here, where it reads as a provider
    problem and the user is offered a retry.
    """
    steps = [TreatmentStep.model_validate(step) for step in data.get("steps", [])]
    if not steps:
        raise ValueError("no steps returned")

    return StainAdvice(steps=steps, identified_as=data.get("identifiedAs"))
