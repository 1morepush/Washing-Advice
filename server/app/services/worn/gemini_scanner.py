"""Asking Gemini what a person in a photograph is wearing.

One vision call with a response schema, validated and retried once, on
`settings.gemini_model`. The transport, the retry and the error mapping are
`GeminiStructured`'s, so a rate limit here is reported with its wait exactly as
it is for every other scan; what lives here is what is sent and how the reply
becomes detections.

Two things in the reply are deliberately *not* decided here. Whether a box is
sensible and whether a mask is believable are `cutting`'s to judge, because
both are the model's guesses and the judgement should be one deterministic
piece of code rather than a reply parser's opinion. This parser rejects only a
reply that is wrong in kind (no list, a box that is not four numbers, an
unknown garment type), which the transport retries once with the problem fed
back. A mask that is absent, or is not a string, is simply no mask: Google's
documents disagree on whether the current models can draw one, and the feature
must not depend on the answer.
"""

from __future__ import annotations

import base64
from typing import Any

import httpx

from app.config import Settings
from app.services.ai.base import ScanImage
from app.services.ai.providers.gemini import _clamp, _parse_garment
from app.services.selling.gemini_json import GeminiStructured, gemini_arguments
from app.services.worn.base import RawDetection
from app.services.worn.cutting import NormalisedBox
from app.services.worn.prompts import WORN_PROMPT, WORN_SCHEMA

_TEMPERATURE = 0.1
"""Perception, not composition: a creative reading of where a sleeve ends is a
wrong one."""


class GeminiWornScanner:
    def __init__(
        self,
        api_key: str,
        *,
        model: str = "gemini-3.6-flash",
        base_url: str = "https://generativelanguage.googleapis.com/v1beta",
        timeout_seconds: float = 45.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._gemini = GeminiStructured(
            api_key,
            model=model,
            base_url=base_url,
            timeout_seconds=timeout_seconds,
            client=client,
        )

    @classmethod
    def from_settings(cls, settings: Settings | None = None) -> GeminiWornScanner:
        return cls(**gemini_arguments(settings))

    @property
    def name(self) -> str:
        return "gemini"

    async def aclose(self) -> None:
        await self._gemini.aclose()

    async def read(self, image: ScanImage) -> list[RawDetection]:
        parts: list[dict[str, Any]] = [
            {"text": WORN_PROMPT},
            {
                "inlineData": {
                    "mimeType": image.mime_type,
                    "data": base64.b64encode(image.data).decode("ascii"),
                }
            },
        ]
        return await self._gemini.generate(
            parts,
            WORN_SCHEMA,
            _parse,
            temperature=_TEMPERATURE,
        )


def _parse(data: Any) -> list[RawDetection]:
    """Builds detections from the model's reply.

    A free function so it can be tested against recorded replies without a
    transport. Raises `ValueError` (or the `KeyError` a missing `type` gives) for
    a reply that is wrong in kind, which the transport retries once.
    """
    if not isinstance(data, dict) or not isinstance(data.get("items"), list):
        raise ValueError("the reply must be a JSON object with an 'items' list")

    detections: list[RawDetection] = []
    for index, entry in enumerate(data["items"]):
        if not isinstance(entry, dict):
            raise ValueError(f"items[{index}] must be an object")

        label = entry.get("label")
        named = {
            **entry,
            # The model's own words for a piece are a better name than none,
            # and the only one it gives for something the type list calls `other`.
            "suggestedName": entry.get("suggestedName")
            or (label if isinstance(label, str) else None),
        }

        mask = entry.get("mask")
        detections.append(
            RawDetection(
                scan=_parse_garment(named),
                box=NormalisedBox.from_box_2d(_box_2d(entry.get("box_2d"), index)),
                detection_confidence=_clamp(entry.get("detectionConfidence", 0.5)),
                mask=mask if isinstance(mask, str) and mask.strip() else None,
            )
        )
    return detections


def _box_2d(raw: Any, index: int) -> list[float]:
    """Four numbers, or a `ValueError` saying what was wrong.

    Whether they describe a sensible box is not asked here.
    """
    if not isinstance(raw, list) or len(raw) != 4:
        raise ValueError(f"items[{index}].box_2d must be four numbers [y0, x0, y1, x1]")
    if not all(isinstance(value, (int, float)) and not isinstance(value, bool) for value in raw):
        raise ValueError(f"items[{index}].box_2d must be four numbers [y0, x0, y1, x1]")
    return [float(value) for value in raw]
