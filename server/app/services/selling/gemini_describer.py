"""Asking Gemini to read a garment into a draft listing.

One vision call, every photograph sent, with a response schema and the same
low temperature as the other readings: this is composition from evidence, and a
creative title is a wrong one. The transport, the retry and the error mapping
are `GeminiStructured`'s; what lives here is what is sent and how the reply is
turned into `ListingFacts`.

The reply is trimmed to the contract (`repair.py`) and then the seller's known
facts are laid over it (`known.py`), in that order: a known brand is the last
word, so nothing the model wrote can be left standing on top of it.
"""

from __future__ import annotations

import base64
from typing import Any

import httpx

from app.config import Settings
from app.schemas.common import Confident, Provenance
from app.schemas.limits import MAX_BRAND
from app.schemas.selling import ListingFacts, SearchQueries
from app.schemas.wardrobe import ItemType
from app.services.selling import repair
from app.services.selling.base import DescribeRequest
from app.services.selling.gemini_json import GeminiStructured, gemini_arguments
from app.services.selling.known import apply_known
from app.services.selling.prompts import LISTING_SCHEMA, describe

_TEMPERATURE = 0.2

_DEFAULT_BRAND_CONFIDENCE = 0.5
"""What a brand reported with no confidence is taken to be.

Half, not certain: the app asks the seller to confirm anything it is unsure of
and silently trusts the rest, so a missing number must not read as the rest.
"""

_DEFAULT_SIZE_CONFIDENCE = 0.6


class GeminiListingDescriber:
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
    def from_settings(cls, settings: Settings | None = None) -> GeminiListingDescriber:
        return cls(**gemini_arguments(settings))

    @property
    def name(self) -> str:
        return "gemini"

    async def aclose(self) -> None:
        await self._gemini.aclose()

    async def describe(self, request: DescribeRequest) -> ListingFacts:
        facts = await self._gemini.generate(
            self._parts(request),
            LISTING_SCHEMA,
            _parse,
            temperature=_TEMPERATURE,
        )
        return apply_known(facts, request.known)

    def _parts(self, request: DescribeRequest) -> list[dict[str, Any]]:
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


def _parse(data: Any) -> ListingFacts:
    """Builds the facts from the model's reply, trimming what runs over.

    A free function so it can be tested against recorded replies without a
    transport. Raises `ValueError` for a reply that is wrong in kind rather than
    in length, which the transport retries once with the problem fed back.
    """
    if not isinstance(data, dict):
        raise ValueError("the reply must be a JSON object")

    title = repair.text(data.get("title"), 80, minimum=3)
    if title is None:
        raise ValueError("title is missing, or shorter than three characters")

    # Not repaired, whatever it is: an item type outside the closed list is the
    # model failing the task, and "other" is an answer it has to choose.
    raw_type = data.get("itemType")
    if not isinstance(raw_type, str) or raw_type not in {member.value for member in ItemType}:
        raise ValueError(f"itemType must be one of the listed values, got {raw_type!r}")
    item_type = ItemType(raw_type)

    brand = repair.text(data.get("brand"), MAX_BRAND)
    size = repair.text(data.get("sizeOnTag"), 30)

    return ListingFacts(
        title=title,
        item_type=item_type,
        brand=(
            Confident[str](
                value=brand,
                confidence=repair.confidence(
                    data.get("brandConfidence"), _DEFAULT_BRAND_CONFIDENCE
                ),
                source=Provenance.AI_INFERENCE,
            )
            if brand
            else None
        ),
        colors=repair.texts(data.get("colors"), limit=30, count=3),
        material=repair.text(data.get("material"), 120),
        size_on_tag=(
            Confident[str](
                value=size,
                confidence=repair.confidence(data.get("sizeConfidence"), _DEFAULT_SIZE_CONFIDENCE),
                source=Provenance.AI_INFERENCE,
            )
            if size
            else None
        ),
        # The brand has a field of its own, so a style word that is the brand
        # is the same fact twice, in the one place a buyer's search is diluted.
        style_words=repair.texts(
            data.get("styleWords"), limit=30, count=6, exclude=[brand] if brand else []
        ),
        era=repair.text(data.get("era"), 20),
        visible_flaws=repair.texts(data.get("visibleFlaws"), limit=120, count=5, minimum=3),
        search_queries=SearchQueries(
            # A phrase the model left out is the title: brand, item and search
            # words are a sound thing to search for, and better than failing a
            # reading over the field the seller can edit before it is used.
            depop=repair.text(data.get("depopSearch"), 120, minimum=3) or title,
            retail=repair.text(data.get("retailSearch"), 120, minimum=3) or title,
        ),
    )
