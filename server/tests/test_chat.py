"""Answering a typed question: the prompt, Gemini's handling, and the route.

The only endpoint here whose *question* is free text from the user, and the
only one whose answer nothing downstream checks. Elsewhere the model names ids
and the core resolves them against a wardrobe it holds; a sentence has no ids
to resolve, so the guardrails live in the prompt and the prompt is what these
tests hold in place.

The one that matters most is the label/guess distinction. The app knows whether
a garment's care came off a sewn-in label or out of the rule table, and it is
the difference between an instruction and an inference. Flattened into one
line, this feature tells somebody their wool jumper is fine in the dryer with
the confidence of a manufacturer, and the jumper does not come back. So the
prompt is asserted to carry that mark on every garment, and to say what it
means.
"""

from __future__ import annotations

from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.schemas.chat import ChatGarment, ChatRequest, ChatTurn
from app.services.ai.base import ProviderError
from app.services.chat.fake import FakeChatAdviser
from app.services.chat.gemini_adviser import GeminiChatAdviser
from app.services.chat.prompts import describe


def _garment(name: str, **extra: Any) -> ChatGarment:
    fields: dict[str, Any] = {"name": name, "type": "Sweater"}
    fields.update(extra)
    return ChatGarment(**fields)


def _request(**overrides: Any) -> ChatRequest:
    fields: dict[str, Any] = {
        "question": "Can I tumble dry the navy jumper?",
        "wardrobe": [
            _garment(
                "navy jumper",
                colors=["navy"],
                fabric="100% Wool",
                care="Hand wash 30°C, do not tumble dry",
            ),
            _garment("grey tee", type="T-shirt", colors=["grey"], fabric="100% Cotton"),
        ],
    }
    fields.update(overrides)
    return ChatRequest(**fields)


class TestThePrompt:
    def test_it_lists_the_wardrobe(self) -> None:
        prompt = describe(_request())

        assert "navy jumper" in prompt
        assert "100% Wool" in prompt
        assert "Hand wash 30°C, do not tumble dry" in prompt

    def test_a_label_reading_is_marked_as_one(self) -> None:
        prompt = describe(_request())

        assert "LABEL: Hand wash 30°C, do not tumble dry" in prompt

    def test_a_guess_is_marked_as_a_guess(self) -> None:
        # The distinction this whole feature turns on. An inference presented
        # as the manufacturer's instruction is how a garment gets ruined by an
        # answer that was technically about the right garment.
        prompt = describe(
            _request(
                wardrobe=[
                    _garment(
                        "navy jumper",
                        fabric="100% Wool",
                        care="Machine 30°C, gentle",
                        care_is_guess=True,
                    )
                ]
            )
        )

        assert "GUESS: Machine 30°C, gentle" in prompt
        assert "LABEL" in prompt, "the prompt must still explain what the marks mean"

    def test_it_says_never_to_pass_a_guess_off_as_a_label(self) -> None:
        assert "Never present a GUESS" in describe(_request())

    def test_the_question_is_included(self) -> None:
        prompt = describe(_request(question="What does the triangle mean?"))

        assert "What does the triangle mean?" in prompt

    def test_earlier_turns_are_included_in_order(self) -> None:
        prompt = describe(
            _request(
                history=[
                    ChatTurn(role="user", text="what about the tee"),
                    ChatTurn(role="assistant", text="cotton, 40 degrees is fine"),
                ]
            )
        )

        assert prompt.index("what about the tee") < prompt.index("cotton, 40 degrees")

    def test_an_empty_wardrobe_is_said_rather_than_left_blank(self) -> None:
        # Otherwise the model sees a heading with nothing under it and is as
        # likely to invent garments as to notice there are none.
        prompt = describe(_request(wardrobe=[]))

        assert "nothing in their wardrobe" in prompt

    def test_a_truncated_wardrobe_says_so(self) -> None:
        # "You do not own a white shirt" is a bad answer when eighty garments
        # did not fit in the prompt.
        prompt = describe(_request(wardrobe_total=120))

        assert "2 of their 120 garments" in prompt
        assert "cannot see all of their wardrobe" in prompt

    def test_a_whole_wardrobe_does_not_claim_to_be_partial(self) -> None:
        assert "did not fit" not in describe(_request(wardrobe_total=2))


class TestTheFake:
    @pytest.mark.anyio
    async def test_it_answers_from_the_garment_named(self) -> None:
        answer = await FakeChatAdviser().answer(_request())

        assert "Hand wash 30°C" in answer.reply

    @pytest.mark.anyio
    async def test_it_distinguishes_a_guess(self) -> None:
        answer = await FakeChatAdviser().answer(
            _request(wardrobe=[_garment("navy jumper", care="Machine 30°C", care_is_guess=True)])
        )

        assert "check the label" in answer.reply

    @pytest.mark.anyio
    async def test_it_reports_a_truncated_wardrobe(self) -> None:
        answer = await FakeChatAdviser().answer(
            _request(question="how much detergent?", wardrobe_total=120)
        )

        assert "2 of your 120 garments" in answer.reply

    @pytest.mark.anyio
    async def test_an_empty_wardrobe_is_not_an_error(self) -> None:
        answer = await FakeChatAdviser().answer(
            _request(question="how much detergent?", wardrobe=[])
        )

        assert answer.reply


class TestGemini:
    def _adviser(self, handler: Any) -> GeminiChatAdviser:
        return GeminiChatAdviser(
            api_key="test-key",
            client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        )

    def _reply(self, text: str) -> httpx.Response:
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"parts": [{"text": text}]}}]},
        )

    @pytest.mark.anyio
    async def test_it_returns_the_text(self) -> None:
        adviser = self._adviser(lambda _: self._reply("No — it says do not tumble dry."))

        answer = await adviser.answer(_request())

        assert answer.reply == "No — it says do not tumble dry."

    @pytest.mark.anyio
    async def test_surrounding_whitespace_is_trimmed(self) -> None:
        adviser = self._adviser(lambda _: self._reply("\n\nCold wash.\n"))

        assert (await adviser.answer(_request())).reply == "Cold wash."

    @pytest.mark.anyio
    async def test_an_empty_answer_is_refused(self) -> None:
        # A blank bubble is worse than an error: it looks like the app worked
        # and had nothing to say.
        adviser = self._adviser(lambda _: self._reply("   "))

        with pytest.raises(ProviderError, match="empty"):
            await adviser.answer(_request())

    @pytest.mark.anyio
    async def test_no_response_schema_is_sent(self) -> None:
        # The answer is prose. Asking for JSON would buy validation of a field
        # the app only ever prints, and would let a model that formatted its
        # reply slightly wrong fail a question it had answered correctly.
        seen: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            import json

            seen.update(json.loads(request.content))
            return self._reply("Cold wash.")

        await self._adviser(handler).answer(_request())

        assert "responseSchema" not in seen["generationConfig"]

    @pytest.mark.anyio
    async def test_the_temperature_is_low(self) -> None:
        # Unlike the stylist, which runs hot because it is asked for taste.
        # This is asked what a symbol means, and a creative answer is a wrong
        # one.
        seen: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            import json

            seen.update(json.loads(request.content))
            return self._reply("Cold wash.")

        await self._adviser(handler).answer(_request())

        assert seen["generationConfig"]["temperature"] <= 0.3

    @pytest.mark.anyio
    async def test_an_http_error_becomes_a_provider_error(self) -> None:
        def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(429, json={"error": {"message": "quota exceeded"}})

        with pytest.raises(ProviderError, match="quota"):
            await self._adviser(handler).answer(_request())

    @pytest.mark.anyio
    async def test_a_blocked_reply_becomes_a_provider_error(self) -> None:
        # Safety blocks come back with candidates but no parts, which would
        # otherwise be an IndexError surfacing as a 500.
        def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json={"candidates": [{"finishReason": "SAFETY"}]})

        with pytest.raises(ProviderError, match="unexpected response shape"):
            await self._adviser(handler).answer(_request())

    def test_it_refuses_to_be_built_without_a_key(self) -> None:
        with pytest.raises(ProviderError):
            GeminiChatAdviser(api_key="")


class TestTheRoute:
    def test_it_answers(self, client: TestClient) -> None:
        response = client.post(
            "/v1/chat/ask",
            json={"question": "how much detergent?", "wardrobe": []},
        )

        assert response.status_code == 200
        assert response.json()["reply"]

    def test_it_reports_which_adviser_answered(self, client: TestClient) -> None:
        response = client.post("/v1/chat/ask", json={"question": "hello"})

        assert response.json()["diagnostics"]["stageAnswered"] == "fake"

    def test_the_wardrobe_reaches_the_adviser(self, client: TestClient) -> None:
        response = client.post(
            "/v1/chat/ask",
            json={
                "question": "can I tumble dry the navy jumper?",
                "wardrobe": [
                    {
                        "name": "navy jumper",
                        "type": "Sweater",
                        "care": "Do not tumble dry",
                    }
                ],
            },
        )

        assert "Do not tumble dry" in response.json()["reply"]

    def test_a_question_is_required(self, client: TestClient) -> None:
        assert client.post("/v1/chat/ask", json={"wardrobe": []}).status_code == 422

    def test_an_empty_question_is_refused(self, client: TestClient) -> None:
        # Otherwise a stray tap sends a request that costs money to answer
        # with nothing.
        assert client.post("/v1/chat/ask", json={"question": ""}).status_code == 422

    def test_a_wardrobe_is_not_required(self, client: TestClient) -> None:
        # Plenty of questions are not about the user's clothes at all.
        assert (
            client.post("/v1/chat/ask", json={"question": "what is a delicate cycle?"}).status_code
            == 200
        )

    def test_an_oversized_wardrobe_is_refused(self, client: TestClient) -> None:
        # The cap is what stops one request carrying a whole wardrobe into a
        # prompt and being charged for it.
        response = client.post(
            "/v1/chat/ask",
            json={
                "question": "hello",
                "wardrobe": [{"name": f"tee {i}", "type": "T-shirt"} for i in range(200)],
            },
        )

        assert response.status_code == 422
