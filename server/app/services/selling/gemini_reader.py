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

from typing import Any

import httpx
from pydantic import ValidationError

from app.config import Settings
from app.schemas.base import validation_problems
from app.services.selling.base import Candidate, ListingItem, NumberedResult
from app.services.selling.gemini_json import GeminiStructured, gemini_arguments
from app.services.selling.reader_prompts import READER_SCHEMA, read_prompt

_TEMPERATURE = 0.1


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

        return await self._gemini.generate(
            [{"text": read_prompt(item, results)}],
            READER_SCHEMA,
            _parse,
            temperature=_TEMPERATURE,
        )


def _parse(data: Any) -> list[Candidate]:
    """The claims in a reply, keeping the usable ones if some are not.

    A reply that is not a list of claims at all, or whose every claim is
    unusable, is the model failing the task, and the caller retries it once with
    the problem fed back. A reply with eight good claims and one malformed one is
    not worth a retry or the loss of the eight: the malformed one is dropped, and
    the result it was about is counted as not comparable like any other the
    reader did not put forward. The same spirit as the vetting, which counts
    nonsense and carries on.

    A link or a title in a claim is not an error. `Candidate` has nowhere to put
    either, so they are ignored.
    """
    entries = data.get("results") if isinstance(data, dict) else None
    if not isinstance(entries, list):
        raise ValueError("the reply must be a JSON object with a list called 'results'")

    claims: list[Candidate] = []
    problems: list[str] = []
    for position, entry in enumerate(entries):
        try:
            claims.append(Candidate.model_validate(entry))
        except ValidationError as error:
            problems.extend(validation_problems(error, under=f"results.{position}"))

    if problems and not claims:
        raise ValueError("; ".join(problems))
    return claims
