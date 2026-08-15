"""The Gemini vision provider.

Every call uses **structured output**: a response schema is sent with the
request, and the reply is parsed and validated against Pydantic models. A model
that returns prose where an enum was required is a bug to surface, not to paper
over with a regex, so a validation failure is retried once with the error fed
back and then raises.

Two prompt details carry real weight, both learned from the domain model rather
than from the API:

* A care label states only *some* things. The prompt insists that a symbol which
  is absent, creased or illegible must be **omitted**, never guessed — because
  in the core, absent means "the rule table fills this" while a guessed value
  means "the manufacturer said so".
* A wash tub with no bars means normal agitation. That is a stated fact under
  ISO 3758, and the prompt says so explicitly, because a model left to itself
  reports nothing and every ordinary garment then inherits a gentle cycle.
"""

from __future__ import annotations

import base64
import json
from typing import Any

import httpx
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.schemas.care import CareConstraint
from app.schemas.common import BoundingBox, Confident, Provenance
from app.schemas.scan import (
    CareTagScanResult,
    DetectedItem,
    GarmentScanResult,
    PileScanResult,
)
from app.schemas.wardrobe import (
    ColorPalette,
    FabricComposition,
    Fiber,
    Fit,
    ItemColor,
    ItemType,
    Pattern,
    Season,
    SleeveLength,
    StyleCut,
)
from app.services.ai.base import ProviderError, ScanImage
from app.services.ai.color import hex_to_lab
from app.services.ai.gemini_errors import gemini_error_reason
from app.services.ai.prompts import (
    CARE_TAG_PROMPT,
    CARE_TAG_SCHEMA,
    GARMENT_PROMPT,
    GARMENT_SCHEMA,
    PILE_PROMPT,
    PILE_SCHEMA,
)


class GeminiVisionProvider:
    """Calls Gemini with a response schema and validates what comes back."""

    def __init__(
        self,
        api_key: str,
        *,
        # Kept in step with `Settings.gemini_model`'s default; `from_settings`
        # always passes one explicitly, so this is reached only by a direct
        # construction, e.g. in a test.
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
    def from_settings(cls, settings: Settings | None = None) -> GeminiVisionProvider:
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
        """The client for this provider's lifetime.

        Created once and kept. Building a fresh `AsyncClient` per request — as
        this did originally — throws away the connection pool, so every scan
        pays a new TCP connection and TLS handshake before it can start
        uploading a multi-megabyte image. On a service whose whole job is
        round-tripping images to a model, that is latency added to every single
        call for nothing.
        """
        if self._client is None:
            self._client = httpx.AsyncClient(timeout=self._timeout)
        return self._client

    async def aclose(self) -> None:
        """Releases the connection pool.

        Only closes a client this provider created; an injected one belongs to
        whoever passed it in, and closing it here would break a caller sharing
        one client across providers.
        """
        if self._client is not None and self._injected_client is None:
            await self._client.aclose()
            self._client = None

    async def _generate(
        self,
        prompt: str,
        images: list[ScanImage],
        schema: dict[str, Any],
    ) -> dict[str, Any]:
        """One structured-output call, retried once on invalid JSON."""
        parts: list[dict[str, Any]] = [{"text": prompt}]
        for image in images:
            parts.append(
                {
                    "inline_data": {
                        "mime_type": image.mime_type,
                        "data": base64.b64encode(image.data).decode("ascii"),
                    }
                }
            )

        body: dict[str, Any] = {
            "contents": [{"parts": parts}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": schema,
                # Near-zero temperature: this is extraction, not composition,
                # and a creative reading of a care label is a wrong one.
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
        # The key goes in a header, not the query string: URLs are logged by
        # proxies and error trackers as a matter of course.
        headers = {"x-goog-api-key": self._api_key}

        try:
            response = await self._http().post(url, json=body, headers=headers)
        except httpx.HTTPError as error:
            raise ProviderError(self.name, f"request failed: {error}") from error

        if response.status_code != 200:
            # Never the body verbatim — an error body can echo the request back
            # including image data. But the status code alone is not diagnosable:
            # a 404 means "no such model for this API version" and says which,
            # and without that an operator is left guessing at the model name.
            # Google's error envelope puts that explanation in a single string
            # field, so exactly that field is taken and nothing else.
            raise ProviderError(
                self.name,
                f"HTTP {response.status_code} from the Gemini API{gemini_error_reason(response)}",
            )

        payload = response.json()
        try:
            return str(payload["candidates"][0]["content"]["parts"][0]["text"])
        except (KeyError, IndexError, TypeError) as error:
            raise ProviderError(self.name, f"unexpected response shape: {error}") from error

    # --- Scans --------------------------------------------------------------

    async def scan_garment(self, images: list[ScanImage]) -> GarmentScanResult:
        data = await self._generate(GARMENT_PROMPT, images, GARMENT_SCHEMA)
        try:
            return _parse_garment(data)
        except (ValidationError, ValueError, KeyError) as error:
            raise ProviderError(self.name, f"invalid garment scan: {error}") from error

    async def scan_care_tag(self, images: list[ScanImage]) -> CareTagScanResult:
        data = await self._generate(CARE_TAG_PROMPT, images, CARE_TAG_SCHEMA)
        try:
            return _parse_care_tag(data)
        except (ValidationError, ValueError, KeyError) as error:
            raise ProviderError(self.name, f"invalid care tag scan: {error}") from error

    async def scan_pile(self, image: ScanImage) -> PileScanResult:
        data = await self._generate(PILE_PROMPT, [image], PILE_SCHEMA)
        try:
            return _parse_pile(data)
        except (ValidationError, ValueError, KeyError) as error:
            raise ProviderError(self.name, f"invalid pile scan: {error}") from error


# --- Parsing ----------------------------------------------------------------
#
# Free functions rather than methods so they can be tested against recorded
# payloads without constructing a provider or touching the network.


def _confident(value: Any, confidence: Any, source: Provenance) -> Confident[Any]:
    return Confident[Any](value=value, confidence=_clamp(confidence), source=source)


def _clamp(value: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return 0.0
    return min(1.0, max(0.0, number))


def _palette(entries: list[dict[str, Any]] | None) -> ColorPalette | None:
    if not entries:
        return None
    colors: list[ItemColor] = []
    for entry in entries:
        lightness, a, b = hex_to_lab(str(entry["hex"]))
        colors.append(
            ItemColor(
                l=lightness,
                a=a,
                b=b,
                coverage=_clamp(entry.get("coverage", 1.0)),
                name=entry.get("name"),
            )
        )
    return ColorPalette(colors)


def _composition(entries: list[dict[str, Any]] | None) -> FabricComposition | None:
    if not entries:
        return None
    percentages: dict[Fiber, int] = {}
    for entry in entries:
        fiber = Fiber(entry["fiber"])
        percentages[fiber] = percentages.get(fiber, 0) + int(entry["percent"])
    return FabricComposition(percentages)


def _parse_garment(data: dict[str, Any]) -> GarmentScanResult:
    palette = _palette(data.get("colors"))
    composition = _composition(data.get("composition"))

    return GarmentScanResult(
        type=_confident(
            ItemType(data["type"]),
            data.get("typeConfidence", 0.5),
            Provenance.AI_INFERENCE,
        ),
        colors=(
            _confident(palette, data.get("colorConfidence", 0.7), Provenance.AI_INFERENCE)
            if palette is not None
            else None
        ),
        composition=(
            _confident(
                composition,
                data.get("compositionConfidence", 0.4),
                Provenance.AI_INFERENCE,
            )
            if composition is not None
            else None
        ),
        brand=(
            _confident(
                str(data["brand"]),
                data.get("brandConfidence", 0.5),
                Provenance.AI_INFERENCE,
            )
            if data.get("brand")
            else None
        ),
        pattern=(
            _confident(
                Pattern(data["pattern"]),
                data.get("patternConfidence", 0.6),
                Provenance.AI_INFERENCE,
            )
            if data.get("pattern")
            else None
        ),
        sleeve_length=(
            _confident(SleeveLength(data["sleeveLength"]), 0.8, Provenance.AI_INFERENCE)
            if data.get("sleeveLength")
            else None
        ),
        fit=(
            _confident(Fit(data["fit"]), 0.6, Provenance.AI_INFERENCE) if data.get("fit") else None
        ),
        style_cut=(
            _confident(StyleCut(data["styleCut"]), 0.55, Provenance.AI_INFERENCE)
            if data.get("styleCut")
            else None
        ),
        seasons=[Season(s) for s in data.get("seasons", [])],
        suggested_name=data.get("suggestedName"),
        distinguishing_text=data.get("distinguishingText"),
    )


def _parse_care_tag(data: dict[str, Any]) -> CareTagScanResult:
    stated = data.get("instructions") or {}
    # Passed straight through: keys the model omitted stay absent, which is
    # precisely the "not stated" signal the core relies on. Filling defaults
    # here would destroy the distinction the whole design rests on.
    instructions = CareConstraint.model_validate(stated)

    composition = _composition(data.get("composition"))

    return CareTagScanResult(
        instructions=instructions,
        confidence=_clamp(data.get("confidence", 0.5)),
        composition=(
            _confident(
                composition,
                data.get("compositionConfidence", 0.9),
                Provenance.TAG_SCAN,
            )
            if composition is not None
            else None
        ),
        symbols_found=[str(s) for s in data.get("symbolsFound", [])],
        unreadable_symbol_count=int(data.get("unreadableSymbolCount", 0)),
        raw_text=data.get("rawText"),
        language=_language(data.get("language")),
    )


def _language(raw: Any) -> str | None:
    """An ISO 639-1 code, or nothing.

    Normalised rather than trusted: models answer "en", "EN", "eng" and
    "English" to the same question. Only a two-letter code survives, because
    that is what the app matches against to decide whether to mention the
    language at all — and a value it cannot match is worse than none, since it
    would put "read in English" on the screen for an English label.
    """
    if not isinstance(raw, str):
        return None
    code = raw.strip().lower()
    return code if len(code) == 2 and code.isalpha() else None


def _parse_pile(data: dict[str, Any]) -> PileScanResult:
    items: list[DetectedItem] = []
    for entry in data.get("items", []):
        box = entry["boundingBox"]
        items.append(
            DetectedItem(
                scan=_parse_garment(entry),
                bounding_box=BoundingBox(
                    left=float(box["left"]),
                    top=float(box["top"]),
                    width=float(box["width"]),
                    height=float(box["height"]),
                ),
                detection_confidence=_clamp(entry.get("detectionConfidence", 0.5)),
            )
        )

    return PileScanResult(
        items=items,
        partially_obscured_count=int(data.get("partiallyObscuredCount", 0)),
    )
