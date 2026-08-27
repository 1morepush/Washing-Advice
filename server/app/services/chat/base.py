"""What it takes to answer a question.

Its own Protocol, like `Stylist` and `StainAdviser`, and for the sharper
version of the same reason: this one takes free text from the user. Keeping it
behind an interface is what lets the fake — which never reaches a network and
never sees an API key — stand in everywhere the tests run.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from app.schemas.chat import ChatAnswer, ChatRequest


@runtime_checkable
class ChatAdviser(Protocol):
    @property
    def name(self) -> str: ...

    async def answer(self, request: ChatRequest) -> ChatAnswer: ...
