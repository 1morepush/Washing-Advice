"""A deterministic adviser, for tests and for running without a key.

Not a stub returning one canned sentence. It reads the request the way the real
one is asked to — it notices whether a garment was named, whether that garment's
care came off a label or out of the rule table, and whether the conversation has
history — so a test can assert that the *request* was assembled correctly
without a network call or a key.

That is the whole reason it is more than three lines: the thing most likely to
break in this feature is the app sending the wrong context, and a fake that
ignored its input could not catch it.
"""

from __future__ import annotations

from app.schemas.chat import ChatAnswer, ChatGarment, ChatRequest


def _named_in(question: str, wardrobe: list[ChatGarment]) -> ChatGarment | None:
    """The first garment the question mentions by name, if any.

    Case-insensitive substring, which is crude and is meant to be: this exists
    to prove the wardrobe reached the adviser, not to be a matcher.
    """
    asked = question.lower()
    for garment in wardrobe:
        if garment.name and garment.name.lower() in asked:
            return garment
    return None


class FakeChatAdviser:
    """Answers from the request alone, and always the same way."""

    @property
    def name(self) -> str:
        return "fake"

    async def answer(self, request: ChatRequest) -> ChatAnswer:
        garment = _named_in(request.question, request.wardrobe)

        if garment is not None and garment.care:
            source = (
                "the app worked that out from the fabric, so check the label"
                if garment.care_is_guess
                else "that is what its care label says"
            )
            return ChatAnswer(reply=f"{garment.name}: {garment.care} — {source}.")

        if garment is not None:
            return ChatAnswer(
                reply=f"{garment.name} is in your wardrobe, but nothing is "
                "recorded about how to wash it yet."
            )

        if not request.wardrobe:
            return ChatAnswer(
                reply="There is nothing in your wardrobe yet, so I can only answer in general."
            )

        # Echoes the shape of the context rather than the question, so a test
        # can tell a truncated wardrobe from a whole one.
        seen = len(request.wardrobe)
        total = request.wardrobe_total
        scope = f"{seen} of your {total} garments" if total and total > seen else f"{seen} garments"
        turns = len(request.history)
        carried = f", carrying {turns} earlier message{'s' if turns != 1 else ''}" if turns else ""
        return ChatAnswer(reply=f"I can see {scope}{carried}.")
