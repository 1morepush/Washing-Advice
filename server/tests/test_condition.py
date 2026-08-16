"""Looking a garment over: the fake's branching, the prompt, and the route.

The endpoint whose failure mode is the opposite of every other one here.
Elsewhere a call that returns nothing has failed. Here an empty list is the
commonest correct answer, and a reader that found something on every jumper
would be the whole feature going wrong — people learn to ignore it, and then
they miss the hole.

So the assertions worth having are the negative ones: that nothing is invented,
that a smell is never reported from a photograph, and that the confidence a
model gives survives to the core, which is the only thing standing between a
shadow in the weave and a laundry setting that changes on its own.
"""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.schemas.condition import ObservedWear, WearSeverity, WearType
from app.services.ai.base import ProviderError
from app.services.condition.base import ConditionRequest
from app.services.condition.fake import FakeConditionReader
from app.services.condition.gemini_reader import GeminiConditionReader, _parse
from app.services.condition.prompts import describe
from tests.conftest import png_bytes, scan_image


def _request(seed: int = 0, **overrides: Any) -> ConditionRequest:
    fields: dict[str, Any] = {
        "images": [scan_image(seed)],
        "garment": "Navy wool jumper",
        "fabric": "100% Wool",
    }
    fields.update(overrides)
    return ConditionRequest(**fields)


class TestTheFake:
    async def test_the_same_photograph_always_reads_the_same_way(self) -> None:
        reader = FakeConditionReader()

        first = await reader.read(_request())
        second = await reader.read(_request())

        assert first.model_dump() == second.model_dump()

    async def test_it_branches_on_the_photograph(self) -> None:
        # A fake returning one canned reading would make every screen test look
        # like it passed for the wrong reason.
        reader = FakeConditionReader()

        readings = {
            json.dumps((await reader.read(_request(seed))).model_dump(), default=str)
            for seed in range(40)
        }

        assert len(readings) > 1

    async def test_some_garments_come_back_clean(self) -> None:
        # The commonest real answer, and the state a screen most needs to have
        # been drawn in before it ships.
        reader = FakeConditionReader()

        readings = [await reader.read(_request(seed)) for seed in range(40)]

        assert any(not reading.observed for reading in readings)

    async def test_and_some_come_back_below_the_floor(self) -> None:
        # So the layer that drops unsure findings is exercised by default
        # rather than only where a test remembers to ask.
        reader = FakeConditionReader()

        readings = [await reader.read(_request(seed)) for seed in range(40)]

        assert any(wear.confidence < 0.5 for reading in readings for wear in reading.observed)

    async def test_a_scan_with_no_photograph_is_refused(self) -> None:
        with pytest.raises(ValueError):
            ConditionRequest(images=[], garment="Navy wool jumper")


class TestThePrompt:
    def test_it_says_most_garments_are_fine(self) -> None:
        # The instruction the whole feature rests on. A model asked what is
        # wrong with a garment will answer, because that is what the question
        # invites.
        assert "Most garments are fine" in describe(_request())

    def test_it_forbids_reporting_a_smell(self) -> None:
        prompt = describe(_request())

        assert "cannot smell a photograph" in prompt

    def test_it_forbids_inferring_wear_from_the_fabric(self) -> None:
        # The subtle one. "Wool pills, this is wool, therefore this is pilling"
        # is a plausible chain that never looked at the photograph.
        assert "A wool jumper is not pilling because wool pills" in describe(_request())

    def test_it_asks_for_the_whole_confidence_range(self) -> None:
        # The core drops anything under its floor, which is only useful if the
        # model actually spends the range.
        assert "use the whole range" in describe(_request()).lower()

    def test_the_garment_and_its_fabric_reach_the_model(self) -> None:
        # Pilling on wool and pilling on polyester look different, and a reader
        # told nothing about the fabric is guessing.
        prompt = describe(_request())

        assert "Navy wool jumper" in prompt
        assert "100% Wool" in prompt

    def test_what_is_already_known_is_passed_on(self) -> None:
        # So the model is not asked to re-find what the owner already recorded,
        # and so "worse than last time" is a judgement it can make.
        prompt = describe(_request(known="moderate pilling"))

        assert "moderate pilling" in prompt


class TestParsingGeminisAnswer:
    def test_a_well_formed_reading_survives(self) -> None:
        result = _parse(
            {
                "observed": [
                    {
                        "type": "pilling",
                        "severity": "moderate",
                        "confidence": 0.86,
                        "note": "along the inner sleeve",
                    }
                ]
            }
        )

        assert result.observed[0].type is WearType.PILLING
        assert result.observed[0].severity is WearSeverity.MODERATE
        assert result.observed[0].note == "along the inner sleeve"

    def test_the_confidence_survives_exactly(self) -> None:
        # The number the core's floor is applied to. Rounding or clamping it
        # here would move the floor without anybody deciding to.
        result = _parse({"observed": [{"type": "hole", "severity": "severe", "confidence": 0.42}]})

        assert result.observed[0].confidence == 0.42

    def test_a_clean_garment_is_a_success(self) -> None:
        # Unlike every other endpoint here, where nothing to say means the call
        # did not work.
        assert _parse({"observed": []}).observed == []
        assert _parse({}).observed == []

    def test_a_smell_reported_from_a_photograph_is_dropped(self) -> None:
        # Belt and braces with the prompt and the schema, both of which already
        # exclude it. An app that reported a smell from a picture would be
        # making a claim about the world it cannot possibly have checked.
        result = _parse(
            {
                "observed": [
                    {"type": "odour", "severity": "severe", "confidence": 0.95},
                    {"type": "pilling", "severity": "slight", "confidence": 0.8},
                ]
            }
        )

        assert [wear.type for wear in result.observed] == [WearType.PILLING]

    def test_a_wear_type_this_build_does_not_know_is_refused(self) -> None:
        with pytest.raises(ValueError):
            _parse({"observed": [{"type": "haunted", "severity": "severe", "confidence": 0.9}]})


class TestTheGeminiCall:
    def _reader(self, handler: Any) -> GeminiConditionReader:
        return GeminiConditionReader(
            api_key="test-key",
            client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        )

    def _answer(self, request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"parts": [{"text": json.dumps({"observed": []})}]}}]},
        )

    async def test_every_photograph_is_sent(self) -> None:
        # Wear is not evenly distributed — cuffs, underarms, the seat — and a
        # reader given only the front shot reports a jumper as fine because the
        # pilling is under the arms.
        sent: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            sent.update(json.loads(request.content))
            return self._answer(request)

        await self._reader(handler).read(
            _request(images=[scan_image(1), scan_image(2), scan_image(3)])
        )

        parts = sent["contents"][0]["parts"]
        assert len([p for p in parts if "inlineData" in p]) == 3

    async def test_it_runs_cold(self) -> None:
        # Perception, not taste. The stylist deliberately runs hot; this must
        # not, because the risk here is a model inventing findings.
        sent: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            sent.update(json.loads(request.content))
            return self._answer(request)

        await self._reader(handler).read(_request())

        assert sent["generationConfig"]["temperature"] <= 0.2

    async def test_an_http_failure_is_a_provider_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(429, json={"error": {"message": "quota exceeded"}})

        with pytest.raises(ProviderError, match="quota"):
            await self._reader(handler).read(_request())


class TestTheRoute:
    def _post(self, client: TestClient, seed: int = 1, **fields: str) -> Any:
        data = {"garment": "Navy wool jumper", "fabric": "100% Wool"}
        data.update(fields)
        return client.post(
            "/v1/care/condition",
            files=[("images", ("front.png", png_bytes(seed), "image/png"))],
            data=data,
        )

    def test_it_reads_a_garment(self, client: TestClient) -> None:
        response = self._post(client)

        assert response.status_code == 200
        assert "observed" in response.json()["result"]

    def test_a_clean_garment_is_still_a_200(self, client: TestClient) -> None:
        # Every seed the fake answers for, clean or not. None of them is an
        # error, and a screen that treated an empty list as a failure would
        # tell people something was wrong on the commonest outcome.
        for seed in range(8):
            assert self._post(client, seed=seed).status_code == 200

    def test_it_reports_which_reader_answered(self, client: TestClient) -> None:
        assert self._post(client).json()["diagnostics"]["stageAnswered"] == "fake"

    def test_the_garment_is_required(self, client: TestClient) -> None:
        # A reader told nothing about what it is looking at is guessing.
        response = client.post(
            "/v1/care/condition",
            files=[("images", ("front.png", png_bytes(1), "image/png"))],
        )

        assert response.status_code == 422

    def test_a_photograph_is_required(self, client: TestClient) -> None:
        response = client.post("/v1/care/condition", data={"garment": "Navy wool jumper"})

        assert response.status_code == 422

    def test_something_that_is_not_an_image_is_refused(self, client: TestClient) -> None:
        # Declared as text and unsniffable, which is what actually gets
        # rejected. Bytes declared `image/png` are *trusted* when they cannot
        # be sniffed — deliberate, and shared with every other upload here,
        # because clients routinely mislabel a camera capture.
        response = client.post(
            "/v1/care/condition",
            files=[("images", ("notes.txt", b"not a picture", "text/plain"))],
            data={"garment": "Navy wool jumper"},
        )

        assert response.status_code == 415


def test_the_wire_names_match_the_core_exactly() -> None:
    """The Dart side decodes these with `values.byName`.

    A mismatch is not a build error in either language — it is an observation
    silently dropped on somebody's phone. Checked against the identifiers in
    `packages/wardrobe_core/lib/src/wardrobe/model/condition.dart` rather than
    against this module's own members, which would be tautological.
    """
    assert {wear.value for wear in WearType} == {
        "fading",
        "pilling",
        "hole",
        "tear",
        "stain",
        "stretchedOut",
        "shrunk",
        "looseSeam",
        "brokenFastener",
        "odour",
    }
    assert {level.value for level in WearSeverity} == {
        "slight",
        "moderate",
        "severe",
    }
    # And the one thing that can only come from a person.
    assert (
        ObservedWear(type=WearType.STAIN, severity=WearSeverity.SLIGHT, confidence=0.9).note is None
    )
