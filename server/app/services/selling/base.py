"""What it takes to write and price a listing.

Their own Protocols, as `Stylist` and `ConditionReader` are, and for the same
reason: none of these is a scan. The pipeline orders stages by cost and lets a
remembered answer pre-empt a paid one, and a photograph of *this* jumper is
never a repeat of an earlier question — so a stage in front of the describer
would be dead weight. Behind each interface the fake stands in everywhere the
tests run, with no key and no network.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol, runtime_checkable

from app.schemas.selling import DescribeContext, KnownFacts, ListingFacts
from app.services.ai.base import ScanImage


@dataclass(frozen=True, slots=True)
class DescribeRequest:
    """The photographs of one garment, and what the app already knows about it."""

    images: list[ScanImage]
    context: DescribeContext | None = None

    def __post_init__(self) -> None:
        if not self.images:
            raise ValueError("a listing draft needs at least one image")

    @property
    def known(self) -> KnownFacts | None:
        """What the wardrobe knows, when it knows anything at all."""
        return self.context.known if self.context else None


@runtime_checkable
class ListingDescriber(Protocol):
    """Reads photographs into the facts a listing is written from.

    Whatever it returns has the known facts already applied: a describer that
    leaves that to its caller is one more place a typed brand can be lost.
    """

    @property
    def name(self) -> str: ...

    async def describe(self, request: DescribeRequest) -> ListingFacts: ...
