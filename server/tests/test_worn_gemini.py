"""The Gemini worn-photo reader, against a mocked transport.

Nothing here reaches the network. What is pinned is what is *sent* (the schema,
the model, the key's place in a header, the picture) and what is made of what
comes back, including the replies a model really gives: no mask, a bad box, a
rate limit.
"""

from __future__ import annotations

import base64
import json
from typing import Any

import httpx
import pytest

from app.config import Settings
from app.schemas.wardrobe import ItemType
from app.services.ai.base import ProviderError
from app.services.worn.cutting import NormalisedBox
from app.services.worn.gemini_scanner import GeminiWornScanner
from tests.conftest import scan_image


def entry(**overrides: Any) -> dict[str, Any]:
    base: dict[str, Any] = {
        "type": "jacket",
        "typeConfidence": 0.9,
        "label": "navy bomber jacket",
        "box_2d": [100, 200, 600, 800],
        "mask": "data:image/png;base64,AAAA",
        "detectionConfidence": 0.88,
    }
    base.update(overrides)
    return base


def reply(items: list[dict[str, Any]]) -> httpx.Response:
    return httpx.Response(
        200,
        json={"candidates": [{"content": {"parts": [{"text": json.dumps({"items": items})}]}}]},
    )


def scanner(handler: Any) -> GeminiWornScanner:
    return GeminiWornScanner(
        api_key="test-key",
        client=httpx.AsyncClient(transport=httpx.MockTransport(handler)),
    )


class TestWhatIsSent:
    async def test_asks_for_structured_output_with_the_box_and_the_mask(self) -> None:
        seen: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["body"] = json.loads(request.content)
            return reply([entry()])

        await scanner(handler).read(scan_image(1))

        config = seen["body"]["generationConfig"]
        assert config["responseMimeType"] == "application/json"
        properties = config["responseSchema"]["properties"]["items"]["items"]["properties"]
        assert properties["box_2d"]["minItems"] == 4 and properties["box_2d"]["maxItems"] == 4
        assert "mask" in properties
        assert "type" in properties and "detectionConfidence" in properties
        required = config["responseSchema"]["properties"]["items"]["items"]["required"]
        assert "mask" not in required, "a mask must stay optional"
        assert config["temperature"] <= 0.2

    async def test_sends_the_picture_and_a_prompt_about_what_is_worn(self) -> None:
        seen: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["parts"] = json.loads(request.content)["contents"][0]["parts"]
            return reply([])

        image = scan_image(7)
        await scanner(handler).read(image)

        text, picture = seen["parts"]
        assert "wearing" in text["text"] and "box_2d" in text["text"]
        assert picture["inlineData"]["mimeType"] == "image/png"
        assert base64.b64decode(picture["inlineData"]["data"]) == image.data

    async def test_uses_the_configured_model_and_keeps_the_key_out_of_the_url(self) -> None:
        seen: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["url"] = str(request.url)
            seen["key"] = request.headers.get("x-goog-api-key")
            return reply([])

        settings = Settings(gemini_api_key="sekrit", gemini_model="gemini-test-9")
        built = GeminiWornScanner.from_settings(settings)
        built._gemini._client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        await built.read(scan_image())

        assert "models/gemini-test-9:generateContent" in seen["url"]
        assert seen["key"] == "sekrit"
        assert "sekrit" not in seen["url"]

    def test_refuses_to_be_built_without_a_key(self) -> None:
        with pytest.raises(ProviderError):
            GeminiWornScanner.from_settings(Settings(gemini_api_key=None))


class TestWhatIsMadeOfTheReply:
    async def test_reads_a_detection(self) -> None:
        found = await scanner(lambda r: reply([entry()])).read(scan_image())

        assert len(found) == 1
        detection = found[0]
        assert detection.scan.type.value is ItemType.JACKET
        assert detection.scan.type.confidence == 0.9
        # [y0, x0, y1, x1] out of a thousand, y first.
        assert detection.box == NormalisedBox(left=0.2, top=0.1, right=0.8, bottom=0.6)
        assert detection.detection_confidence == 0.88
        assert detection.mask == "data:image/png;base64,AAAA"

    async def test_the_models_label_names_a_piece_with_no_name(self) -> None:
        found = await scanner(lambda r: reply([entry()])).read(scan_image())
        assert found[0].scan.suggested_name == "navy bomber jacket"

        named = await scanner(lambda r: reply([entry(suggestedName="Bomber")])).read(scan_image())
        assert named[0].scan.suggested_name == "Bomber"

    @pytest.mark.parametrize("mask", [None, "", "   ", 7, ["x"], {"a": 1}])
    async def test_a_missing_or_unusable_mask_is_just_no_mask(self, mask: Any) -> None:
        item = entry()
        item["mask"] = mask

        found = await scanner(lambda r: reply([item])).read(scan_image())

        assert len(found) == 1 and found[0].mask is None

    async def test_a_reply_with_no_mask_key_at_all_is_fine(self) -> None:
        item = entry()
        del item["mask"]

        calls = {"n": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            calls["n"] += 1
            return reply([item])

        found = await scanner(handler).read(scan_image())

        assert calls["n"] == 1, "a missing mask is not a reason to ask again"
        assert found[0].mask is None

    async def test_nothing_worn_is_an_answer_not_a_failure(self) -> None:
        calls = {"n": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            calls["n"] += 1
            return reply([])

        assert await scanner(handler).read(scan_image()) == []
        assert calls["n"] == 1

    async def test_a_silly_box_is_passed_on_for_the_cutting_to_judge(self) -> None:
        # Zero area, off the photograph: not this reader's call.
        found = await scanner(lambda r: reply([entry(box_2d=[500, 500, 500, 500])])).read(
            scan_image()
        )
        assert len(found) == 1

    async def test_confidence_is_clamped(self) -> None:
        found = await scanner(lambda r: reply([entry(detectionConfidence=7)])).read(scan_image())
        assert found[0].detection_confidence == 1.0


class TestARepliesThatIsWrongInKindIsAskedAgainOnce:
    @pytest.mark.parametrize(
        "bad",
        [
            entry(box_2d=[1, 2, 3]),
            entry(box_2d="100,200,600,800"),
            entry(box_2d=[1, 2, "x", 4]),
            entry(box_2d=[True, 2, 3, 4]),
            entry(box_2d=None),
            entry(type="spacesuit"),
            {"typeConfidence": 0.9, "box_2d": [1, 2, 3, 4]},
        ],
    )
    async def test_retries_with_the_problem_fed_back(self, bad: dict[str, Any]) -> None:
        bodies: list[dict[str, Any]] = []

        def handler(request: httpx.Request) -> httpx.Response:
            bodies.append(json.loads(request.content))
            return reply([bad]) if len(bodies) == 1 else reply([entry()])

        found = await scanner(handler).read(scan_image())

        assert len(bodies) == 2
        assert len(found) == 1
        retry_prompt = bodies[1]["contents"][0]["parts"][0]["text"]
        assert "previous reply could not be used" in retry_prompt
        # The photograph goes again, untouched.
        assert bodies[1]["contents"][0]["parts"][1] == bodies[0]["contents"][0]["parts"][1]

    async def test_a_reply_that_is_not_a_list_of_items_is_retried(self) -> None:
        calls = {"n": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            calls["n"] += 1
            if calls["n"] == 1:
                return httpx.Response(
                    200, json={"candidates": [{"content": {"parts": [{"text": "[1, 2]"}]}}]}
                )
            return reply([entry()])

        assert len(await scanner(handler).read(scan_image())) == 1
        assert calls["n"] == 2

    async def test_prose_instead_of_json_is_retried(self) -> None:
        calls = {"n": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            calls["n"] += 1
            if calls["n"] == 1:
                return httpx.Response(
                    200, json={"candidates": [{"content": {"parts": [{"text": "sorry!"}]}}]}
                )
            return reply([entry()])

        assert len(await scanner(handler).read(scan_image())) == 1

    async def test_gives_up_after_the_second_bad_reply(self) -> None:
        calls = {"n": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            calls["n"] += 1
            return reply([entry(box_2d=[1, 2])])

        with pytest.raises(ProviderError) as raised:
            await scanner(handler).read(scan_image())

        assert calls["n"] == 2
        assert raised.value.retry_after is None
        assert "box_2d" in str(raised.value)


class TestErrorsAreMappedLikeEveryOtherGeminiCall:
    async def test_a_rate_limit_carries_its_wait(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(
                429, headers={"Retry-After": "7"}, json={"error": {"message": "Quota exceeded"}}
            )

        with pytest.raises(ProviderError) as raised:
            await scanner(handler).read(scan_image())

        assert raised.value.retry_after == 7.0
        assert "rate limited" in str(raised.value) and "Quota exceeded" in str(raised.value)

    async def test_a_rate_limit_without_a_header_still_says_how_long(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(429, json={})

        with pytest.raises(ProviderError) as raised:
            await scanner(handler).read(scan_image())

        assert raised.value.retry_after == 30.0

    async def test_a_rate_limit_is_not_retried(self) -> None:
        calls = {"n": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            calls["n"] += 1
            return httpx.Response(429, headers={"Retry-After": "3"}, json={})

        with pytest.raises(ProviderError):
            await scanner(handler).read(scan_image())

        assert calls["n"] == 1, "the next request is what makes a rate limit worse"

    async def test_another_failure_has_no_wait_and_leaks_no_body(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(500, text="echoed: " + "SECRETPIXELS" * 5)

        with pytest.raises(ProviderError) as raised:
            await scanner(handler).read(scan_image())

        assert raised.value.retry_after is None
        assert "HTTP 500" in str(raised.value)
        assert "SECRETPIXELS" not in str(raised.value)

    async def test_googles_own_explanation_is_included(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(404, json={"error": {"message": "models/gemini-9 is not found"}})

        with pytest.raises(ProviderError, match="models/gemini-9 is not found"):
            await scanner(handler).read(scan_image())

    async def test_a_transport_failure_is_a_provider_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError("no route")

        with pytest.raises(ProviderError, match="request failed"):
            await scanner(handler).read(scan_image())

    async def test_a_blocked_reply_with_no_content_is_a_provider_error(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json={"candidates": [{"finishReason": "SAFETY"}]})

        with pytest.raises(ProviderError, match="unexpected response shape"):
            await scanner(handler).read(scan_image())
