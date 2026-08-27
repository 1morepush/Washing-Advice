"""Asking a question in words, on the wire.

Every other endpoint here answers a fixed question: what is this garment, what
is on it, what goes with what. This one answers whatever the user typed, which
makes it the only place in the service where the *question* is untrusted input
rather than a field name.

Two things follow from that. The wardrobe is sent as compact facts rather than
photographs, for the reason the stylist does it — the app already holds them
and is surer about them than a fresh glance would be. And the answer comes back
as plain text rather than a schema, because there is nothing structured to
extract: the sentence is the whole product, and forcing it through JSON would
buy validation of a field the app only ever prints.

Nothing here is stateful. The conversation so far arrives with each request,
which keeps the server the same shape as every other endpoint and means a
dropped connection loses nothing the app cannot resend.
"""

from __future__ import annotations

from typing import Literal

from pydantic import Field

from app.schemas.base import WireModel
from app.schemas.scan import ScanDiagnostics


class ChatTurn(WireModel):
    """One thing already said, by either side."""

    role: Literal["user", "assistant"]
    text: str = Field(min_length=1, max_length=4000)


class ChatGarment(WireModel):
    """One garment, as the assistant is told about it.

    Smaller than `StyleCandidate` on purpose and different in what it keeps: a
    stylist needs to know what a garment looks like, and this needs to know how
    it is washed. Both drop the fields the other lives on rather than sharing
    one wide type, because every field sent is tokens spent on every message of
    every conversation.
    """

    name: str
    type: str = Field(description="Garment type, e.g. 'Dress shirt'.")
    colors: list[str] = Field(default_factory=list)
    fabric: str | None = Field(default=None, description="e.g. '100% Cotton'.")
    care: str | None = Field(
        default=None,
        description="How the app says to wash it, e.g. 'Machine 30°C, no tumble dry'.",
    )
    care_is_guess: bool = Field(
        default=False,
        description=(
            "Whether that care line was worked out from the fabric rather than "
            "read off a label. Sent so the answer can say which it is: telling "
            "somebody a rule-table default as though it were the "
            "manufacturer's instruction is the one way this feature can ruin a "
            "garment."
        ),
    )
    state: str | None = Field(
        default=None,
        description="Where it is now, e.g. 'in the basket'.",
    )


class ChatRequest(WireModel):
    """A question, what was said before it, and the wardrobe to answer about."""

    question: str = Field(min_length=1, max_length=2000)
    history: list[ChatTurn] = Field(
        default_factory=list,
        max_length=40,
        description="Oldest first, excluding the question being asked now.",
    )
    wardrobe: list[ChatGarment] = Field(
        default_factory=list,
        max_length=120,
        description=(
            "The garments the assistant may reason about. May be a subset of a "
            "large wardrobe — see wardrobeTotal."
        ),
    )
    wardrobe_total: int | None = Field(
        default=None,
        ge=0,
        description=(
            "How many garments the user actually owns, when more than were "
            "sent. Present so the answer can say it is working from part of "
            "the wardrobe instead of confidently reporting that a garment is "
            "not owned when it simply did not fit."
        ),
    )


class ChatAnswer(WireModel):
    """What the adviser produced, before the route dresses it up."""

    reply: str


class ChatResponse(WireModel):
    """The answer, and what it cost."""

    reply: str
    diagnostics: ScanDiagnostics | None = None
