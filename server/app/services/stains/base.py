"""What it takes to advise on a stain.

Its own Protocol rather than a widening of `VisionProvider`, for the reason
`MachineIdentifier` is its own: the question is different in kind. A scan reads
a photograph and reports what is in it; this reasons from what the model knows
about a substance and a fabric, with the photograph optional and only ever
corroborating.
"""

from __future__ import annotations

from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Protocol, runtime_checkable

from app.schemas.stains import StainAdvice, StainAdviceRequest, TreatmentStep
from app.services.ai.base import ScanImage


@dataclass(frozen=True)
class Identified:
    """What the model believes the stain is.

    Emitted as soon as that field is complete rather than with the rest of the
    answer. It is shown above the steps so a misread is caught *before* anybody
    follows a treatment aimed at the wrong substance, and it is generated first,
    so there is no reason to make the user wait for the last step to learn what
    the advice thinks it is about.
    """

    text: str


@dataclass(frozen=True)
class Proposed:
    """One finished step of the treatment, still unvetted."""

    step: TreatmentStep


StainEvent = Identified | Proposed


@runtime_checkable
class StainAdviser(Protocol):
    @property
    def name(self) -> str: ...

    async def advise(
        self,
        request: StainAdviceRequest,
        image: ScanImage | None = None,
    ) -> StainAdvice: ...

    def stream(
        self,
        request: StainAdviceRequest,
        image: ScanImage | None = None,
    ) -> AsyncIterator[StainEvent]:
        """The same advice, delivered as each step finishes generating.

        Separate from `advise` rather than replacing it because the two fail
        differently. `advise` can retry a reply it could not parse; a stream
        that has already emitted three steps cannot take them back, so it ends
        at the point it broke and reports what it had. Callers that want an
        all-or-nothing answer should keep using `advise`.
        """
        ...
