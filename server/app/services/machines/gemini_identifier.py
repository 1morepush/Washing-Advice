"""Identifying a washer or dryer's real programme line-up from Gemini's own
knowledge of the appliance — brand and model in, a profile out, no photograph
anywhere in the exchange.

Structurally the same shape as `GeminiVisionProvider`: one `httpx.AsyncClient`
held for the object's lifetime, a structured-output call retried once on
invalid JSON, and the same care around what an error response is allowed to
say. Kept as its own small class rather than folded into the vision provider
because it answers a different kind of question — reasoning from training
data rather than reading a photograph — and the `VisionProvider` protocol's
three scan methods have no use for two strings and no image.
"""

from __future__ import annotations

import json
from typing import Any

import httpx
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.schemas.care import Agitation, TumbleDryHeat
from app.schemas.machines import (
    DryerOption,
    DryerProfile,
    DrynessControl,
    DryProgram,
    DryProgramKind,
    FabricClass,
    WasherOption,
    WasherProfile,
    WashProgram,
    WashProgramKind,
)
from app.services.ai.base import ProviderError
from app.services.ai.gemini_errors import gemini_error_reason
from app.services.machines.prompts import (
    DRYER_PROMPT,
    DRYER_SCHEMA,
    WASHER_PROMPT,
    WASHER_SCHEMA,
)


class GeminiMachineIdentifier:
    """Calls Gemini with a response schema and validates what comes back."""

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
    def from_settings(cls, settings: Settings | None = None) -> GeminiMachineIdentifier:
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

    # --- Transport ----------------------------------------------------------

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=self._timeout)
        return self._client

    async def aclose(self) -> None:
        """Releases the connection pool.

        Only closes a client this identifier created; an injected one belongs
        to whoever passed it in.
        """
        if self._client is not None and self._injected_client is None:
            await self._client.aclose()
            self._client = None

    async def _generate(self, prompt: str, schema: dict[str, Any]) -> dict[str, Any]:
        """One structured-output call, retried once on invalid JSON.

        No image parts, ever — the entire point of this class is that the
        answer comes from what the model already knows, not from anything it
        is shown.
        """
        body: dict[str, Any] = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": schema,
                # Near-zero temperature: this is recall, not composition, and
                # a creative answer about a machine's real cycle names is a
                # wrong one.
                "temperature": 0.1,
            },
        }

        last_error: str | None = None
        for attempt in range(2):
            if last_error is not None:
                body["contents"][0]["parts"][0] = {
                    "text": (
                        f"{prompt}\n\nYour previous reply could not be parsed: "
                        f"{last_error}\nReturn only JSON matching the schema."
                    )
                }

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

    # --- Identification -------------------------------------------------

    async def identify_washer(self, brand: str, model: str) -> WasherProfile:
        prompt = f"{WASHER_PROMPT}\nBrand: {brand}\nModel: {model}\n"
        data = await self._generate(prompt, WASHER_SCHEMA)
        try:
            return _parse_washer(data, brand=brand, model=model)
        except (ValidationError, ValueError, KeyError) as error:
            raise ProviderError(self.name, f"invalid washer profile: {error}") from error

    async def identify_dryer(self, brand: str, model: str) -> DryerProfile:
        prompt = f"{DRYER_PROMPT}\nBrand: {brand}\nModel: {model}\n"
        data = await self._generate(prompt, DRYER_SCHEMA)
        try:
            return _parse_dryer(data, brand=brand, model=model)
        except (ValidationError, ValueError, KeyError) as error:
            raise ProviderError(self.name, f"invalid dryer profile: {error}") from error


# --- Parsing ------------------------------------------------------------
#
# Free functions rather than methods so they can be tested against recorded
# payloads without constructing an identifier or touching the network — the
# same reasoning `providers/gemini.py`'s `_parse_garment` etc. follow.


class NotIdentifiedError(ProviderError):
    """Gemini declined to guess rather than invent a plausible-sounding one.

    The right outcome, not a failure of this class: a wrong programme list
    gets acted on against a real garment, so refusing is strictly better than
    a confident-sounding fabrication. Raised as a distinct type so the route
    layer can tell "the model said no" apart from every other way this can
    fail, and answer with a message that says so rather than a generic one.
    """


def _require_identified(data: dict[str, Any]) -> None:
    if not data.get("identified") or not data.get("programs"):
        raise NotIdentifiedError("gemini", "no reliable knowledge of this exact make and model")


def _slug(text: str) -> str:
    """A stable identifier fragment from free text the user typed.

    Gemini is never asked for an id — the same reasoning that keeps every
    other scan result's ids assigned server-side, not invented by the model.
    """
    kept = "".join(ch.lower() if ch.isalnum() else "-" for ch in text)
    collapsed = "-".join(part for part in kept.split("-") if part)
    return collapsed or "machine"


def _parse_washer(data: dict[str, Any], *, brand: str, model: str) -> WasherProfile:
    _require_identified(data)
    profile_id = f"ai.washer.{_slug(brand)}.{_slug(model)}"

    programs = [
        WashProgram(
            id=f"{profile_id}.program-{index}",
            display_name=str(raw["displayName"]),
            kind=WashProgramKind(raw["kind"]),
            available_temps_c=[int(t) for t in raw.get("availableTempsC", [])],
            default_temp_c=int(raw["defaultTempC"]),
            agitation=Agitation(raw["agitation"]),
            spin_speeds_rpm=[int(s) for s in raw.get("spinSpeedsRpm", [])],
            suitable_for=[FabricClass(f) for f in raw.get("suitableFor", [])],
            max_load_fraction=float(raw.get("maxLoadFraction") or 1.0),
            typical_duration_minutes=int(raw.get("typicalDurationMinutes") or 90),
        )
        for index, raw in enumerate(data["programs"])
    ]

    return WasherProfile(
        id=profile_id,
        brand=brand,
        model=model,
        capacity_kg=float(data.get("capacityKg") or 8.0),
        programs=programs,
        options=[WasherOption(o) for o in data.get("options", [])],
        is_verified_model=False,
    )


def _parse_dryer(data: dict[str, Any], *, brand: str, model: str) -> DryerProfile:
    _require_identified(data)
    profile_id = f"ai.dryer.{_slug(brand)}.{_slug(model)}"

    programs = [
        DryProgram(
            id=f"{profile_id}.program-{index}",
            display_name=str(raw["displayName"]),
            kind=DryProgramKind(raw["kind"]),
            available_heats=[TumbleDryHeat(h) for h in raw.get("availableHeats", [])],
            default_heat=TumbleDryHeat(raw["defaultHeat"]),
            suitable_for=[FabricClass(f) for f in raw.get("suitableFor", [])],
            control=DrynessControl(raw.get("control") or DrynessControl.SENSOR.value),
            max_load_fraction=float(raw.get("maxLoadFraction") or 1.0),
            typical_duration_minutes=int(raw.get("typicalDurationMinutes") or 60),
        )
        for index, raw in enumerate(data["programs"])
    ]

    return DryerProfile(
        id=profile_id,
        brand=brand,
        model=model,
        capacity_kg=float(data.get("capacityKg") or 8.0),
        programs=programs,
        options=[DryerOption(o) for o in data.get("options", [])],
        is_verified_model=False,
    )
