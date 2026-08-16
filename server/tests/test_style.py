"""Proposing outfits: the fake's structure, Gemini's parsing, and the route.

The endpoint that deliberately asks for an opinion rather than a fact, which
changes what is worth testing. Nothing here checks that an outfit is *good* —
that is the part being delegated, and asserting it would either be tautological
or would be this file quietly re-implementing taste.

What is worth protecting is everything around the opinion. The ids must be
copied rather than invented, because the core refuses ones it cannot resolve
and every refusal is an idea lost. The reason must survive intact, because it
is shown to the user in the model's own words and is the only thing this
endpoint has that the rule-based builder does not. And an answer carrying no
outfits must fail rather than succeed emptily, since the app would otherwise
draw a heading with nothing under it.
"""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.schemas.style import StyleCandidate, StyleRequest
from app.services.ai.base import ProviderError
from app.services.style.fake import FakeStylist
from app.services.style.gemini_stylist import GeminiStylist, _parse
from app.services.style.prompts import describe


def _candidate(
    ident: str,
    name: str,
    kind: str,
    category: str,
    **extra: Any,
) -> StyleCandidate:
    return StyleCandidate(id=ident, name=name, type=kind, category=category, **extra)


def _wardrobe() -> list[StyleCandidate]:
    return [
        _candidate("shirt", "Oxford shirt", "Dress shirt", "Tops", colors=["white"]),
        _candidate("tee", "Grey tee", "T-shirt", "Tops", colors=["grey"]),
        _candidate("chinos", "Stone chinos", "Chinos", "Bottoms", colors=["stone"]),
        _candidate("jeans", "Blue jeans", "Jeans", "Bottoms", colors=["indigo"]),
        _candidate("shoes", "White sneakers", "Sneakers", "Footwear", colors=["white"]),
    ]


def _request(**overrides: Any) -> StyleRequest:
    fields: dict[str, Any] = {
        "occasion": "Everyday",
        "wardrobe": _wardrobe(),
    }
    fields.update(overrides)
    return StyleRequest(**fields)


class TestTheFake:
    async def test_the_same_wardrobe_always_answers_the_same_way(self) -> None:
        stylist = FakeStylist()

        first = await stylist.propose(_request())
        second = await stylist.propose(_request())

        assert [o.model_dump() for o in first] == [o.model_dump() for o in second]

    async def test_it_pairs_real_garments_rather_than_returning_a_canned_answer(
        self,
    ) -> None:
        # A fake returning one hard-coded outfit would make every downstream
        # test look like it passed for the wrong reason.
        outfits = await FakeStylist().propose(_request())

        ids = {ident for outfit in outfits for ident in outfit.item_ids}
        assert ids <= {item.id for item in _wardrobe()}
        assert {"shirt", "chinos"} <= ids

    async def test_it_proposes_one_impossible_outfit_on_purpose(self) -> None:
        # So the layer that refuses structural nonsense is exercised by default
        # rather than only where a test remembers to ask for it.
        outfits = await FakeStylist().propose(_request())

        assert any(
            len([i for i in outfit.item_ids if i in {"shirt", "tee"}]) == 2 for outfit in outfits
        )

    async def test_it_respects_how_many_were_asked_for(self) -> None:
        outfits = await FakeStylist().propose(_request(count=1))

        # The deliberate bad one is extra; the good ones are capped.
        assert len([o for o in outfits if len(o.item_ids) <= 3]) <= 2

    async def test_a_wardrobe_with_no_bottoms_proposes_nothing(self) -> None:
        outfits = await FakeStylist().propose(
            _request(
                wardrobe=[
                    _candidate("tee", "Grey tee", "T-shirt", "Tops"),
                    _candidate("scarf", "Wool scarf", "Scarf", "Accessories"),
                ]
            )
        )

        assert outfits == []


class TestThePrompt:
    def test_every_garment_reaches_the_model_with_its_id(self) -> None:
        # The ids are the whole contract. A wardrobe described without them
        # would leave the model no way to name anything it picked.
        prompt = describe(_request())

        for item in _wardrobe():
            assert f"- {item.id}:" in prompt

    def test_it_says_what_a_garment_looks_like(self) -> None:
        prompt = describe(
            _request(
                wardrobe=[
                    _candidate(
                        "shirt",
                        "Oxford shirt",
                        "Dress shirt",
                        "Tops",
                        colors=["white", "blue"],
                        fabric="100% Cotton",
                        pattern="Striped",
                        fit="Slim",
                        brand="Uniqlo",
                    )
                ]
            )
        )

        assert "white/blue" in prompt
        assert "100% Cotton" in prompt
        assert "Striped" in prompt
        assert "Slim fit" in prompt
        assert "Uniqlo" in prompt

    def test_a_plain_garment_is_not_described_as_patterned(self) -> None:
        # "Solid" is the absence of a pattern, and listing it would spend tokens
        # on every garment to say nothing.
        prompt = describe(
            _request(wardrobe=[_candidate("tee", "Grey tee", "T-shirt", "Tops", pattern="Solid")])
        )

        assert "Solid" not in prompt

    def test_the_occasion_the_season_and_the_note_all_arrive(self) -> None:
        prompt = describe(_request(occasion="Work", season="Winter", note="it will be cold"))

        assert "Work" in prompt
        assert "Winter" in prompt
        assert "it will be cold" in prompt

    def test_it_forbids_inventing_an_id(self) -> None:
        # The core refuses proposals naming garments that do not exist, but a
        # refusal is an idea lost. This is where they stop being generated.
        assert "Never invent an id" in describe(_request())


class TestParsingGeminisAnswer:
    def test_a_well_formed_answer_becomes_proposals(self) -> None:
        outfits = _parse(
            {
                "outfits": [
                    {
                        "itemIds": ["shirt", "chinos", "shoes"],
                        "rationale": "The stone softens the shirt's formality.",
                    }
                ]
            }
        )

        assert outfits[0].item_ids == ["shirt", "chinos", "shoes"]

    def test_the_reason_survives_word_for_word(self) -> None:
        # Shown to the user unedited. Anything that normalised, truncated or
        # tidied it would be summarising the one thing worth asking for.
        reason = (
            "The fine stripe and the bold check would fight, so the plain "
            "chinos are doing the work here."
        )
        outfits = _parse({"outfits": [{"itemIds": ["a", "b"], "rationale": reason}]})

        assert outfits[0].rationale == reason

    def test_an_answer_with_no_outfits_is_refused(self) -> None:
        # A success carrying no ideas would draw a heading with nothing under
        # it. Failing offers the user a retry, which on this endpoint genuinely
        # is a second attempt — the temperature is high.
        with pytest.raises(ValueError):
            _parse({"outfits": []})

    def test_a_missing_key_is_refused_too(self) -> None:
        with pytest.raises(ValueError):
            _parse({})


class TestTheGeminiCall:
    def _stylist(self, handler: Any) -> GeminiStylist:
        return GeminiStylist(
            api_key="test-key",
            client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        )

    async def test_it_asks_for_taste_rather_than_recall(self) -> None:
        # The only call in this service that runs hot, and deliberately. A
        # stylist at 0.1 returns the same four safe pairings every time, which
        # makes "ask again" pointless and the whole feature thin.
        sent: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            sent.update(json.loads(request.content))
            return httpx.Response(
                200,
                json={
                    "candidates": [
                        {
                            "content": {
                                "parts": [
                                    {
                                        "text": json.dumps(
                                            {
                                                "outfits": [
                                                    {
                                                        "itemIds": ["shirt", "chinos"],
                                                        "rationale": "Works.",
                                                    }
                                                ]
                                            }
                                        )
                                    }
                                ]
                            }
                        }
                    ]
                },
            )

        await self._stylist(handler).propose(_request())

        assert sent["generationConfig"]["temperature"] >= 0.7

    async def test_no_photographs_are_sent(self) -> None:
        # The wardrobe goes up as text because the app already holds these
        # facts. Uploading forty pictures to re-derive them would cost a
        # multiple of the time for worse answers.
        sent: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            sent.update(json.loads(request.content))
            return httpx.Response(
                200,
                json={
                    "candidates": [
                        {
                            "content": {
                                "parts": [
                                    {
                                        "text": json.dumps(
                                            {
                                                "outfits": [
                                                    {
                                                        "itemIds": ["shirt", "chinos"],
                                                        "rationale": "Works.",
                                                    }
                                                ]
                                            }
                                        )
                                    }
                                ]
                            }
                        }
                    ]
                },
            )

        await self._stylist(handler).propose(_request())

        parts = sent["contents"][0]["parts"]
        assert all("inlineData" not in part for part in parts)

    async def test_an_empty_wardrobe_never_leaves_the_process(self) -> None:
        called = False

        def handler(request: httpx.Request) -> httpx.Response:
            nonlocal called
            called = True
            return httpx.Response(200, json={})

        with pytest.raises(ProviderError):
            await self._stylist(handler).propose(_request(wardrobe=[]))

        assert not called

    async def test_an_http_failure_is_a_provider_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(429, json={"error": {"message": "quota exceeded"}})

        with pytest.raises(ProviderError, match="quota"):
            await self._stylist(handler).propose(_request())


class TestTheRoute:
    def test_it_proposes_outfits(self, client: TestClient) -> None:
        response = client.post(
            "/v1/style/outfits",
            json={
                "occasion": "Everyday",
                "wardrobe": [item.model_dump(by_alias=True) for item in _wardrobe()],
            },
        )

        assert response.status_code == 200
        body = response.json()
        assert body["result"]
        assert body["result"][0]["itemIds"]
        assert body["result"][0]["rationale"]

    def test_the_answer_is_a_list_under_result(self, client: TestClient) -> None:
        # The one endpoint here whose `result` is an array rather than an
        # object. The Dart client unwraps `result` as a map everywhere else, so
        # this shape is worth stating rather than leaving to be discovered.
        response = client.post(
            "/v1/style/outfits",
            json={
                "occasion": "Everyday",
                "wardrobe": [item.model_dump(by_alias=True) for item in _wardrobe()],
            },
        )

        assert isinstance(response.json()["result"], list)

    def test_it_reports_which_stylist_answered(self, client: TestClient) -> None:
        response = client.post(
            "/v1/style/outfits",
            json={
                "occasion": "Everyday",
                "wardrobe": [item.model_dump(by_alias=True) for item in _wardrobe()],
            },
        )

        assert response.json()["diagnostics"]["stageAnswered"] == "fake"

    def test_a_wardrobe_is_required(self, client: TestClient) -> None:
        response = client.post("/v1/style/outfits", json={"occasion": "Everyday"})

        assert response.status_code == 422

    def test_an_absurd_count_is_refused(self, client: TestClient) -> None:
        # Bounded on the server rather than trusted from the client: a request
        # for four hundred outfits is a bill, not a feature.
        response = client.post(
            "/v1/style/outfits",
            json={
                "occasion": "Everyday",
                "count": 400,
                "wardrobe": [item.model_dump(by_alias=True) for item in _wardrobe()],
            },
        )

        assert response.status_code == 422
