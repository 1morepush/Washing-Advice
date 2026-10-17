"""What it takes to write and price a listing.

Their own Protocols, as `Stylist` and `ConditionReader` are, and for the same
reason: none of these is a scan. The pipeline orders stages by cost and lets a
remembered answer pre-empt a paid one, and a photograph of *this* jumper is
never a repeat of an earlier question — so a stage in front of the describer
would be dead weight. Behind each interface the fake stands in everywhere the
tests run, with no key and no network.

The price side is three seams, each for a different reason. `WebSearch` is where
the outside world comes in, and the only place a key is spent. `ComparableReader`
is where the judgement is, and the only place a model's word is taken. Between
them sits the vetting (`vetting.py`), which takes nobody's word.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Protocol, runtime_checkable

from app.schemas.base import WireModel
from app.schemas.selling import (
    DescribeContext,
    KnownFacts,
    ListingFacts,
    PriceSearchStatus,
)
from app.services.ai.base import ScanImage

# --- describe ---------------------------------------------------------------


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


# --- prices: the search ------------------------------------------------------


@dataclass(frozen=True, slots=True)
class SearchRequest:
    """One web search: a phrase, and which sites it may and may not draw from."""

    query: str
    include_domains: tuple[str, ...] = ()
    exclude_domains: tuple[str, ...] = ()
    max_results: int = 10


@dataclass(frozen=True, slots=True)
class SearchHit:
    """One result, as the search service gave it and nothing more.

    The link and the title are the service's, and are what is shown to the
    person later; nothing downstream is allowed to supply its own.
    """

    title: str
    url: str
    content: str = ""
    """The snippet the service extracted for the query."""

    raw_content: str = ""
    """The page's text, already cut to the length the service client allows."""

    score: float = 0.0
    """How relevant the service thought it, for ordering ties between matches."""


class SearchError(Exception):
    """A search that gave no answer, and which of the endpoint's statuses it is.

    Carries the status rather than leaving the caller to infer one, so that what
    the app is told is decided where the failure is understood — a 432 is the
    allowance, a 401 is the key — and not re-derived from a message.
    """

    def __init__(self, status: PriceSearchStatus, message: str) -> None:
        super().__init__(message)
        self.status = status


@runtime_checkable
class WebSearch(Protocol):
    """A web search with a key, and a free allowance behind it."""

    @property
    def name(self) -> str: ...

    @property
    def configured(self) -> bool:
        """Whether there is a key. Without one no search is attempted at all."""
        ...

    async def search(self, request: SearchRequest) -> list[SearchHit]:
        """Raises `SearchError`, and nothing else, when it cannot answer."""
        ...


# --- prices: reading the results ---------------------------------------------

Kind = Literal["listing", "retail"]
"""What a result is: an item for sale second-hand, or a shop selling it new."""


@dataclass(frozen=True, slots=True)
class ListingItem:
    """The garment being priced, as the reader is told about it."""

    title: str
    item_type: str
    brand: str | None = None
    colors: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class NumberedResult:
    """A search result, numbered so a reader can refer to it without quoting it.

    The reader says "result 3", never a link: the link is read from here, which
    is how a model that invents one cannot get it onto a screen.
    """

    index: int
    origin: Kind
    """Which search found it, so a reader has a first guess at what it is."""

    title: str
    url: str
    text: str
    """The page text the reader saw, already normalised."""

    score: float = 0.0

    @property
    def searchable(self) -> str:
        """Everything the price may be found in: what the reader was shown."""
        return f"{self.title} {self.text}"


class Candidate(WireModel):
    """What a reader claims about one result. A claim, until it has been vetted.

    There is deliberately no link and no title here. A reader that includes one
    anyway has it ignored, and a test holds it to that.
    """

    result_index: int
    kind: Kind
    price: float
    currency: str
    """As the page shows it ("USD", "GBP"). Only dollars survive the vetting."""

    sold: bool | None = None
    condition: str | None = None
    match: Literal["same", "similar"]
    why: str | None = None


@runtime_checkable
class ComparableReader(Protocol):
    """Reads search results into claims about what the garment sells for."""

    @property
    def name(self) -> str: ...

    async def read(self, item: ListingItem, results: list[NumberedResult]) -> list[Candidate]: ...
