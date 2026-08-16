"""What it takes to propose outfits.

Its own Protocol for the same reason `StainAdviser` is: the question is
different in kind from reading an image. Nothing here sees a photograph — the
wardrobe arrives as structured facts, because it already holds them.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from app.schemas.style import ProposedOutfit, StyleRequest


@runtime_checkable
class Stylist(Protocol):
    @property
    def name(self) -> str: ...

    async def propose(self, request: StyleRequest) -> list[ProposedOutfit]: ...
