"""What it takes to advise on a stain.

Its own Protocol rather than a widening of `VisionProvider`, for the reason
`MachineIdentifier` is its own: the question is different in kind. A scan reads
a photograph and reports what is in it; this reasons from what the model knows
about a substance and a fabric, with the photograph optional and only ever
corroborating.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from app.schemas.stains import StainAdvice, StainAdviceRequest
from app.services.ai.base import ScanImage


@runtime_checkable
class StainAdviser(Protocol):
    @property
    def name(self) -> str: ...

    async def advise(
        self,
        request: StainAdviceRequest,
        image: ScanImage | None = None,
    ) -> StainAdvice: ...
