"""Asking Gemini to look a garment over.

The same shape as `GeminiStainAdviser` — one client held for the object's
lifetime, a structured-output call retried once on invalid JSON — and the same
low temperature, for the same reason. This is perception, not taste. A creative
answer about whether a jumper is pilling is a wrong one, and the whole risk
here is a model inventing findings rather than missing them.

Every photograph the caller has is sent. A garment's wear is not evenly
distributed — cuffs, underarms, the seat — and a reader given only the front
shot would report a jumper as fine because the pilling is under the arms.
"""

from __future__ import annotations

import base64
import json
from typing import Any

import httpx
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.schemas.condition import ConditionScanResult, ObservedWear, WearType
from app.services.ai.base import ProviderError
from app.services.ai.gemini_errors import gemini_error_reason
from app.services.condition.base import ConditionRequest
from app.services.condition.prompts import CONDITION_SCHEMA, describe


class GeminiConditionReader:
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
    def from_settings(cls, settings: Settings | None = None) -> GeminiConditionReader:
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

    async def read(self, request: ConditionRequest) -> ConditionScanResult:
        data = await self._generate(self._parts(request))
        try:
            return _parse(data)
        except (ValidationError, ValueError, KeyError, TypeError) as error:
            raise ProviderError(self.name, f"invalid condition reading: {error}") from error

    def _parts(self, request: ConditionRequest) -> list[dict[str, Any]]:
        parts: list[dict[str, Any]] = [{"text": describe(request)}]
        for image in request.images:
            parts.append(
                {
                    "inlineData": {
                        "mimeType": image.mime_type,
                        "data": base64.b64encode(image.data).decode("ascii"),
                    }
                }
            )
        return parts

    def _body(self, parts: list[dict[str, Any]]) -> dict[str, Any]:
        return {
            "contents": [{"parts": parts}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": CONDITION_SCHEMA,
                # Perception, not taste. The stylist runs hot; this must not.
                "temperature": 0.1,
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


def _parse(data: dict[str, Any]) -> ConditionScanResult:
    """Builds the reading, dropping what a photograph cannot support.

    An empty list is a success here rather than a failure — unlike every other
    endpoint in this service, where nothing to say means the call did not work.
    Most garments are fine, and a reader that had to find something would be
    the exact failure the prompt spends its length preventing.
    """
    observed = [ObservedWear.model_validate(entry) for entry in data.get("observed", [])]

    # Belt and braces with the prompt and the schema, both of which already
    # exclude it. A smell is not visible, and an app that reported one from a
    # photograph would be making a claim about the physical world it cannot
    # possibly have checked.
    return ConditionScanResult(
        observed=[wear for wear in observed if wear.type is not WearType.ODOUR]
    )
