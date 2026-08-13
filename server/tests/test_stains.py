"""Stain advice: the fake's branching, Gemini's parsing, and the route.

The contract this file is really protecting is the *structured* half of a step.
The app refuses steps its garment's care forbids, and it can only do that from
`temperatureC`, `bleach`, `isMachineWash` and `abrades`. A model that returned
beautiful prose with those fields empty would pass every schema check here and
hand a wool jumper a 60°C bleach soak, so the parsing tests assert the fields
survive rather than only that the call succeeds.
"""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.schemas.stains import BleachUse, StainAdviceRequest
from app.services.ai.base import ProviderError
from app.services.stains.fake import FakeStainAdviser
from app.services.stains.gemini_adviser import GeminiStainAdviser, _parse


def _request(substance: str = "red wine") -> StainAdviceRequest:
    return StainAdviceRequest(
        substance=substance,
        fabric="100% Cotton",
        color="White",
        care="Machine wash, up to 40°C. Non-chlorine bleach only.",
    )


class TestTheFake:
    async def test_the_same_spill_always_answers_the_same_way(self) -> None:
        adviser = FakeStainAdviser()

        first = await adviser.advise(_request())
        second = await adviser.advise(_request())

        assert first.model_dump() == second.model_dump()

    async def test_it_branches_on_the_substance(self) -> None:
        # A fake that returned one canned answer would make every downstream
        # test look like it passed for the wrong reason.
        adviser = FakeStainAdviser()

        wine = await adviser.advise(_request("red wine"))
        oil = await adviser.advise(_request("olive oil"))

        assert wine.steps != oil.steps

    async def test_a_protein_stain_is_kept_cold(self) -> None:
        # The one piece of stain lore that is counterintuitive enough to be
        # worth a test: hot water cooks blood into the fibre.
        adviser = FakeStainAdviser()

        advice = await adviser.advise(_request("blood"))

        assert all(step.temperature_c is None or step.temperature_c <= 20 for step in advice.steps)

    async def test_it_will_propose_something_unsafe(self) -> None:
        # Deliberate. The whole vetting layer downstream is only exercised if
        # something reaches it that a delicate garment cannot take.
        adviser = FakeStainAdviser()

        advice = await adviser.advise(_request("ink"))

        assert any(step.bleach is BleachUse.CHLORINE for step in advice.steps)
        assert any(
            step.temperature_c is not None and step.temperature_c >= 60 for step in advice.steps
        )


class TestParsingWhatTheModelSent:
    def test_the_checkable_fields_survive(self) -> None:
        advice = _parse(
            {
                "identifiedAs": "red wine",
                "steps": [
                    {
                        "instruction": "Soak in warm water with oxygen bleach.",
                        "because": "It breaks the colour down.",
                        "temperatureC": 40,
                        "bleach": "oxygen",
                        "isMachineWash": False,
                        "abrades": False,
                    }
                ],
            }
        )

        step = advice.steps[0]
        assert step.temperature_c == 40
        assert step.bleach is BleachUse.OXYGEN
        assert advice.identified_as == "red wine"

    def test_an_answer_with_no_steps_is_a_failure(self) -> None:
        # Otherwise the endpoint returns a success carrying no advice, and the
        # app shows a heading with nothing under it.
        with pytest.raises(ValueError):
            _parse({"steps": []})

    def test_a_bleach_it_does_not_recognise_is_rejected(self) -> None:
        # Better a provider error than a step whose bleach silently reads as
        # "none" and sails past the check that exists to catch it.
        with pytest.raises(ValidationError):
            _parse(
                {
                    "steps": [
                        {
                            "instruction": "Use something.",
                            "bleach": "sodium-percarbonate",
                            "isMachineWash": False,
                            "abrades": False,
                        }
                    ]
                }
            )


class TestTheGeminiAdviser:
    async def test_it_sends_the_photo_when_there_is_one(self) -> None:
        captured: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            captured.update(json.loads(request.content))
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
                                                "steps": [
                                                    {
                                                        "instruction": "Blot it.",
                                                        "isMachineWash": False,
                                                        "abrades": True,
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

        from app.services.ai.base import ScanImage

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        adviser = GeminiStainAdviser(api_key="k", client=client)

        await adviser.advise(_request(), ScanImage(data=b"\xff\xd8\xff", mime_type="image/jpeg"))

        parts = captured["contents"][0]["parts"]
        assert any("inlineData" in part for part in parts)

    async def test_no_photo_means_no_image_part(self) -> None:
        captured: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            captured.update(json.loads(request.content))
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
                                                "steps": [
                                                    {
                                                        "instruction": "Blot it.",
                                                        "isMachineWash": False,
                                                        "abrades": False,
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

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        adviser = GeminiStainAdviser(api_key="k", client=client)

        await adviser.advise(_request())

        parts = captured["contents"][0]["parts"]
        assert all("inlineData" not in part for part in parts)

    async def test_an_unreachable_model_is_a_provider_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(503, json={"error": {"message": "overloaded"}})

        client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        adviser = GeminiStainAdviser(api_key="k", client=client)

        with pytest.raises(ProviderError):
            await adviser.advise(_request())


class TestTheRoute:
    def test_it_answers_with_steps(self, client: TestClient) -> None:
        response = client.post(
            "/v1/care/stain",
            data={
                "substance": "red wine",
                "fabric": "100% Cotton",
                "care": "Machine wash, up to 40°C.",
                "color": "White",
            },
        )

        assert response.status_code == 200
        body = response.json()
        assert body["result"]["steps"]
        assert "instruction" in body["result"]["steps"][0]

    def test_the_structured_fields_reach_the_wire_in_camel_case(self, client: TestClient) -> None:
        # The Dart side decodes these by name. A snake_case key here is a field
        # the app silently never sees, and the check it feeds never runs.
        response = client.post(
            "/v1/care/stain",
            data={
                "substance": "olive oil",
                "fabric": "100% Cotton",
                "care": "Machine wash, up to 40°C.",
            },
        )

        steps = response.json()["result"]["steps"]
        assert any("isMachineWash" in step for step in steps)
        assert not any("is_machine_wash" in step for step in steps)

    def test_a_missing_substance_is_rejected(self, client: TestClient) -> None:
        response = client.post(
            "/v1/care/stain",
            data={"fabric": "100% Cotton", "care": "Machine wash."},
        )

        assert response.status_code == 422

    def test_an_empty_photo_part_is_not_a_failure(self, client: TestClient) -> None:
        # What a multipart client sends for "no file chosen".
        response = client.post(
            "/v1/care/stain",
            data={
                "substance": "coffee",
                "fabric": "100% Cotton",
                "care": "Machine wash, up to 40°C.",
            },
            files={"photo": ("", b"", "application/octet-stream")},
        )

        assert response.status_code == 200
