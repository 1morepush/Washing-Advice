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
from app.services.stains.base import Identified, Proposed
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


def _events(body: str) -> list[dict[str, object]]:
    """The decoded events out of an SSE body."""
    return [
        json.loads(line[len("data:") :].strip())
        for line in body.splitlines()
        if line.startswith("data:")
    ]


class TestTheStreamingRoute:
    def test_each_step_arrives_as_its_own_event(self, client: TestClient) -> None:
        response = client.post(
            "/v1/care/stain/stream",
            data={
                "substance": "red wine",
                "fabric": "100% Cotton",
                "care": "Machine wash, up to 40°C.",
            },
        )

        assert response.status_code == 200
        assert response.headers["content-type"].startswith("text/event-stream")

        events = _events(response.text)
        assert [event["type"] for event in events][-1] == "done"
        assert sum(1 for event in events if event["type"] == "step") >= 2

    def test_what_it_thinks_the_stain_is_comes_before_the_steps(self, client: TestClient) -> None:
        # It is shown above the steps so a misread is caught before anybody
        # acts on advice aimed at the wrong substance. Arriving after the last
        # step would be arriving too late to do that job.
        response = client.post(
            "/v1/care/stain/stream",
            data={
                "substance": "blood",
                "fabric": "100% Cotton",
                "care": "Machine wash, up to 40°C.",
            },
        )

        kinds = [event["type"] for event in _events(response.text)]
        assert kinds.index("identified") < kinds.index("step")

    def test_the_steps_match_the_non_streaming_answer(self, client: TestClient) -> None:
        # The two routes must not drift into two different treatments. This is
        # the check that keeps streaming an delivery detail rather than a
        # second opinion.
        form = {
            "substance": "olive oil",
            "fabric": "100% Cotton",
            "care": "Machine wash, up to 40°C.",
        }
        whole = client.post("/v1/care/stain", data=form).json()["result"]["steps"]
        streamed = [
            event["step"]
            for event in _events(client.post("/v1/care/stain/stream", data=form).text)
            if event["type"] == "step"
        ]

        assert [step["instruction"] for step in streamed] == [step["instruction"] for step in whole]

    def test_the_structured_fields_reach_the_wire_in_camel_case(self, client: TestClient) -> None:
        response = client.post(
            "/v1/care/stain/stream",
            data={
                "substance": "olive oil",
                "fabric": "100% Cotton",
                "care": "Machine wash, up to 40°C.",
            },
        )

        steps = [e["step"] for e in _events(response.text) if e["type"] == "step"]
        assert any("isMachineWash" in step for step in steps)
        assert not any("is_machine_wash" in step for step in steps)

    def test_a_missing_substance_is_still_a_422(self, client: TestClient) -> None:
        # Rejected before the response starts, so it stays an ordinary status
        # code rather than an error smuggled inside a 200.
        response = client.post(
            "/v1/care/stain/stream",
            data={"fabric": "100% Cotton", "care": "Machine wash."},
        )

        assert response.status_code == 422


def _sse_chunks(document: str, size: int) -> list[bytes]:
    """`document` as the API would send it: SSE frames of `size` characters.

    Split on character counts rather than on JSON boundaries on purpose. A real
    chunk ends wherever the generator happened to flush — mid-word, mid-key,
    between a `{` and the field that makes the step safe to read.
    """
    return [
        b"data: "
        + json.dumps(
            {"candidates": [{"content": {"parts": [{"text": document[at : at + size]}]}}]}
        ).encode()
        + b"\n\n"
        for at in range(0, len(document), size)
    ]


_STREAMED = (
    '{"identifiedAs": "red wine", "steps": ['
    '{"instruction": "Blot it with a dry cloth.", "because": "Rubbing spreads it.",'
    ' "isMachineWash": false, "abrades": true},'
    '{"instruction": "Soak in warm water with oxygen bleach.", "temperatureC": 40,'
    ' "bleach": "oxygen", "isMachineWash": false, "abrades": false}'
    "]}"
)


class TestStreamingFromGemini:
    def _adviser(self, chunks: list[bytes], status: int = 200) -> GeminiStainAdviser:
        def handler(request: httpx.Request) -> httpx.Response:
            if status != 200:
                return httpx.Response(status, json={"error": {"message": "overloaded"}})
            return httpx.Response(200, stream=_Stream(chunks))

        return GeminiStainAdviser(
            api_key="k",
            client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
        )

    async def _collect(self, adviser: GeminiStainAdviser) -> list[object]:
        return [event async for event in adviser.stream(_request())]

    async def test_the_steps_survive_arbitrary_chunk_boundaries(self) -> None:
        # The property that matters. Whatever size the fragments arrive in, the
        # same two steps come out with the same fields.
        for size in (1, 5, 40, 4000):
            events = await self._collect(self._adviser(_sse_chunks(_STREAMED, size)))
            steps = [event.step for event in events if isinstance(event, Proposed)]

            assert len(steps) == 2, f"chunk size {size}"
            assert steps[0].abrades is True
            assert steps[1].temperature_c == 40
            assert steps[1].bleach is BleachUse.OXYGEN

    async def test_a_step_is_never_emitted_half_read(self) -> None:
        # A step missing `temperatureC` reads as one that names no temperature,
        # which the safety check treats as harmless. Emitting one early would
        # walk a 40°C soak straight past a 30°C label.
        events = await self._collect(self._adviser(_sse_chunks(_STREAMED, 1)))
        soak = [event.step for event in events if isinstance(event, Proposed)][1]

        assert soak.temperature_c == 40

    async def test_the_name_comes_before_the_first_step(self) -> None:
        events = await self._collect(self._adviser(_sse_chunks(_STREAMED, 3)))

        assert isinstance(events[0], Identified)
        assert events[0].text == "red wine"

    async def test_a_stream_that_says_nothing_is_a_provider_error(self) -> None:
        # Rather than a success carrying no advice, which would draw a heading
        # with nothing under it.
        with pytest.raises(ProviderError):
            await self._collect(self._adviser([b'data: {"candidates": []}\n\n']))

    async def test_a_refused_request_is_a_provider_error(self) -> None:
        with pytest.raises(ProviderError):
            await self._collect(self._adviser([], status=503))

    async def test_the_done_sentinel_is_not_read_as_content(self) -> None:
        chunks = [*_sse_chunks(_STREAMED, 4000), b"data: [DONE]\n\n"]
        events = await self._collect(self._adviser(chunks))

        assert len([e for e in events if isinstance(e, Proposed)]) == 2


class _Stream(httpx.AsyncByteStream):
    """Hands back preset chunks, so a test can choose the split points."""

    def __init__(self, chunks: list[bytes]) -> None:
        self._chunks = chunks

    async def __aiter__(self):  # type: ignore[no-untyped-def]
        for chunk in self._chunks:
            yield chunk
