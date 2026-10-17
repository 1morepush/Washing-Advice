"""Asking Gemini which search results are worth pricing from.

A text-only structured-output call: no photographs, because the garment is
described in words by now and the question is about web pages. The transport,
the retry and the error mapping are `GeminiStructured`'s.

The reply is validated as a list of claims (`Candidate`) and handed back as
claims. Nothing here decides whether any of them is true: that is
`vetting.vet`, which takes the claims and the search results and trusts neither
the reader's numbers nor its words.

Run cold. This is reading a price off a page, and a creative reading of a price
is a wrong one.
"""

from __future__ import annotations

import httpx

from app.config import Settings
from app.schemas.base import WireModel
from app.services.selling.base import Candidate, ListingItem, NumberedResult
from app.services.selling.gemini_json import GeminiStructured, gemini_arguments
from app.services.selling.reader_prompts import READER_SCHEMA, read_prompt

_TEMPERATURE = 0.1


class ReaderAnswer(WireModel):
    """The reply: the results the reader put forward, and nothing else.

    Keys the reader adds beyond the schema (a link, a title) are ignored by
    omission: this model has nowhere to put them.
    """

    results: list[Candidate]


class GeminiComparableReader:
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
    def from_settings(cls, settings: Settings | None = None) -> GeminiComparableReader:
        return cls(**gemini_arguments(settings))

    @property
    def name(self) -> str:
        return "gemini"

    async def aclose(self) -> None:
        await self._gemini.aclose()

    async def read(self, item: ListingItem, results: list[NumberedResult]) -> list[Candidate]:
        # Nothing to read is nothing to ask, and the model is not paid to answer
        # an empty list.
        if not results:
            return []

        answer = await self._gemini.generate(
            [{"text": read_prompt(item, results)}],
            READER_SCHEMA,
            ReaderAnswer.model_validate,
            temperature=_TEMPERATURE,
        )
        return answer.results
