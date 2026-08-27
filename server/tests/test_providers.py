"""Providers: the fake's determinism, and Gemini's parsing.

Gemini is exercised through its parsing functions against recorded response
shapes and through a stubbed transport. No network call is made, and no API key
is needed — but the code that turns a model's JSON into domain objects is the
part most likely to break silently, so it is covered properly.
"""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest

from app.schemas.care import Agitation, WashMethod
from app.schemas.common import Provenance
from app.schemas.wardrobe import Fiber, ItemType
from app.services.ai.base import ProviderError, ScanImage
from app.services.ai.color import hex_to_lab, rgb_to_lab
from app.services.ai.providers.fake import FakeVisionProvider
from app.services.ai.providers.gemini import (
    GeminiVisionProvider,
    _parse_care_tag,
    _parse_garment,
    _parse_pile,
)
from app.services.ai.registry import ProviderRegistry
from tests.conftest import scan_image


class TestFakeProvider:
    async def test_is_deterministic(self) -> None:
        """The same image must always give the same answer.

        Otherwise cache behaviour and pipeline ordering cannot be tested at all.
        """
        provider = FakeVisionProvider()
        image = scan_image(3)

        first = await provider.scan_garment([image])
        second = await provider.scan_garment([image])

        assert first == second

    async def test_different_images_give_different_answers(self) -> None:
        provider = FakeVisionProvider()

        results = {
            (await provider.scan_garment([scan_image(seed)])).type.value for seed in range(12)
        }
        assert len(results) > 1, "a fake that always says the same thing tests nothing"

    async def test_reports_a_bar_less_tub_as_normal_agitation(self) -> None:
        result = await FakeVisionProvider().scan_care_tag([scan_image(1)])
        assert result.instructions.agitation is Agitation.NORMAL

    async def test_an_unreadable_symbol_leaves_the_field_unstated(self) -> None:
        provider = FakeVisionProvider()

        incomplete = [
            result
            for seed in range(20)
            if not (result := await provider.scan_care_tag([scan_image(seed)])).is_complete
        ]

        assert incomplete, "the fake must exercise the incomplete-label path"
        for result in incomplete:
            assert result.instructions.tumble_dry_allowed is None
            assert "tumbleDryAllowed" not in result.instructions.to_wire()

    async def test_pile_boxes_are_normalised(self) -> None:
        result = await FakeVisionProvider().scan_pile(scan_image(4))

        assert result.items
        for item in result.items:
            box = item.bounding_box
            assert 0.0 <= box.left <= 1.0
            assert 0.0 <= box.top <= 1.0
            assert 0.0 < box.width <= 1.0
            assert 0.0 < box.height <= 1.0


class TestColorConversion:
    @pytest.mark.parametrize(
        ("hex_value", "expected"),
        [
            ("#FFFFFF", (100.0, 0.0, 0.0)),
            ("#000000", (0.0, 0.0, 0.0)),
            ("#FF0000", (53.24, 80.09, 67.20)),
            ("#0000FF", (32.30, 79.19, -107.86)),
        ],
    )
    def test_matches_published_values(
        self, hex_value: str, expected: tuple[float, float, float]
    ) -> None:
        """These are the same values the Dart core produces.

        Both sides must agree, or the app and the server would disagree about
        what colour a garment is.
        """
        lightness, a, b = hex_to_lab(hex_value)
        assert lightness == pytest.approx(expected[0], abs=0.01)
        assert a == pytest.approx(expected[1], abs=0.01)
        assert b == pytest.approx(expected[2], abs=0.01)

    def test_accepts_hex_with_or_without_a_hash(self) -> None:
        assert hex_to_lab("#FF0000") == hex_to_lab("FF0000")

    @pytest.mark.parametrize("bad", ["#FFF", "navy blue", "", "#GGGGGG"])
    def test_rejects_anything_that_is_not_a_hex_colour(self, bad: str) -> None:
        """A model returning 'navy blue' is a prompt bug to surface."""
        with pytest.raises(ValueError, match="hex colour"):
            hex_to_lab(bad)

    def test_rgb_and_hex_paths_agree(self) -> None:
        assert rgb_to_lab(31, 42, 68) == hex_to_lab("#1F2A44")


class TestGeminiParsing:
    def test_parses_a_well_formed_garment_response(self) -> None:
        payload: dict[str, Any] = {
            "type": "hoodie",
            "typeConfidence": 0.94,
            "colors": [{"hex": "#8A8A8A", "coverage": 1.0, "name": "Grey"}],
            "colorConfidence": 0.9,
            "composition": [
                {"fiber": "cotton", "percent": 80},
                {"fiber": "polyester", "percent": 20},
            ],
            "brand": "Nike",
            "brandConfidence": 0.88,
            "suggestedName": "Grey Nike hoodie",
            "distinguishingText": "Just Do It",
        }

        result = _parse_garment(payload)

        assert result.type.value is ItemType.HOODIE
        assert result.type.confidence == pytest.approx(0.94)
        assert result.brand is not None and result.brand.value == "Nike"
        assert result.composition is not None
        assert result.composition.value.root == {Fiber.COTTON: 80, Fiber.POLYESTER: 20}
        assert result.colors is not None
        assert result.colors.value.dominant is not None
        assert result.distinguishing_text == "Just Do It"

    def test_omitted_optional_fields_stay_none(self) -> None:
        result = _parse_garment({"type": "tShirt", "typeConfidence": 0.8})

        assert result.brand is None
        assert result.composition is None
        assert result.colors is None

    def test_care_tag_omissions_survive_parsing(self) -> None:
        """The single most important parsing behaviour.

        A field the model left out must stay out. Filling a default here would
        destroy the distinction the whole care model rests on.
        """
        payload = {
            "instructions": {
                "method": "machine",
                "maxTempC": 30,
                "agitation": "normal",
            },
            "confidence": 0.85,
            "unreadableSymbolCount": 2,
        }

        result = _parse_care_tag(payload)

        assert result.instructions.method is WashMethod.MACHINE
        assert result.instructions.tumble_dry_allowed is None
        assert result.instructions.tumble_dry_heat is None
        assert not result.is_complete
        assert "tumbleDryAllowed" not in result.instructions.to_wire()

    def test_care_tag_composition_is_marked_as_read_from_a_tag(self) -> None:
        result = _parse_care_tag(
            {
                "instructions": {"method": "machine"},
                "confidence": 0.9,
                "composition": [{"fiber": "wool", "percent": 100}],
            }
        )

        assert result.composition is not None
        # Provenance matters: a composition printed on a label outranks one
        # guessed from a photograph when the two disagree.
        assert result.composition.source is Provenance.TAG_SCAN

    def test_parses_a_pile_response(self) -> None:
        payload = {
            "items": [
                {
                    "type": "jeans",
                    "typeConfidence": 0.9,
                    "boundingBox": {
                        "left": 0.1,
                        "top": 0.2,
                        "width": 0.3,
                        "height": 0.4,
                    },
                    "detectionConfidence": 0.87,
                }
            ],
            "partiallyObscuredCount": 2,
        }

        result = _parse_pile(payload)

        assert result.count == 1
        assert result.items[0].scan.type.value is ItemType.JEANS
        assert result.items[0].bounding_box.left == pytest.approx(0.1)
        assert result.partially_obscured_count == 2

    def test_out_of_range_confidence_is_clamped(self) -> None:
        """Models occasionally return 1.2. Clamp rather than reject the scan."""
        result = _parse_garment({"type": "tShirt", "typeConfidence": 1.4})
        assert result.type.confidence == 1.0

    def test_a_duplicate_fibre_is_summed_not_dropped(self) -> None:
        result = _parse_garment(
            {
                "type": "tShirt",
                "typeConfidence": 0.9,
                "composition": [
                    {"fiber": "cotton", "percent": 50},
                    {"fiber": "cotton", "percent": 50},
                ],
            }
        )
        assert result.composition is not None
        assert result.composition.value.root == {Fiber.COTTON: 100}

    def test_an_unknown_enum_value_is_an_error(self) -> None:
        """Better to fail loudly than to silently record a garment as 'other'."""
        with pytest.raises(ValueError):
            _parse_garment({"type": "spacesuit", "typeConfidence": 0.9})


class TestGeminiTransport:
    def _provider(self, handler: Any) -> GeminiVisionProvider:
        transport = httpx.MockTransport(handler)
        return GeminiVisionProvider(
            api_key="test-key",
            client=httpx.AsyncClient(transport=transport),
        )

    @staticmethod
    def _reply(payload: dict[str, Any]) -> httpx.Response:
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"parts": [{"text": json.dumps(payload)}]}}]},
        )

    async def test_sends_the_key_as_a_header_not_in_the_url(self) -> None:
        """URLs are logged by proxies and error trackers as a matter of course."""
        seen: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["url"] = str(request.url)
            seen["key"] = request.headers.get("x-goog-api-key")
            return self._reply({"type": "tShirt", "typeConfidence": 0.9})

        await self._provider(handler).scan_garment([scan_image()])

        assert seen["key"] == "test-key"
        assert "test-key" not in seen["url"]

    async def test_requests_structured_output(self) -> None:
        seen: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["body"] = json.loads(request.content)
            return self._reply({"type": "tShirt", "typeConfidence": 0.9})

        await self._provider(handler).scan_garment([scan_image()])

        config = seen["body"]["generationConfig"]
        assert config["responseMimeType"] == "application/json"
        assert "responseSchema" in config
        # Extraction, not composition: a creative reading of a label is a wrong one.
        assert config["temperature"] <= 0.2

    async def test_retries_once_on_unparseable_json(self) -> None:
        calls = {"count": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            calls["count"] += 1
            if calls["count"] == 1:
                return httpx.Response(
                    200,
                    json={"candidates": [{"content": {"parts": [{"text": "sorry!"}]}}]},
                )
            return self._reply({"type": "hoodie", "typeConfidence": 0.9})

        result = await self._provider(handler).scan_garment([scan_image()])

        assert calls["count"] == 2
        assert result.type.value is ItemType.HOODIE

    async def test_gives_up_after_the_retry(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(
                200, json={"candidates": [{"content": {"parts": [{"text": "nope"}]}}]}
            )

        with pytest.raises(ProviderError, match="valid JSON"):
            await self._provider(handler).scan_garment([scan_image()])

    async def test_an_http_error_does_not_leak_the_response_body(self) -> None:
        """An error body can echo the request back, including image data."""

        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(400, json={"error": "echo of your image bytes"})

        with pytest.raises(ProviderError) as caught:
            await self._provider(handler).scan_garment([scan_image()])

        assert "400" in str(caught.value)
        assert "echo of your image bytes" not in str(caught.value)

    async def test_an_http_error_reports_googles_own_explanation(self) -> None:
        """A status code alone cannot be acted on; the reason names the fix.

        A 404 says which model was not found, which is the difference between
        an operator correcting one environment variable and guessing at it.
        """

        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(
                404,
                json={
                    "error": {
                        "code": 404,
                        "message": (
                            "models/gemini-9-ultra is not found for API version "
                            "v1beta, or is not supported for generateContent."
                        ),
                        "status": "NOT_FOUND",
                    }
                },
            )

        with pytest.raises(ProviderError) as caught:
            await self._provider(handler).scan_garment([scan_image()])

        assert "404" in str(caught.value)
        assert "gemini-9-ultra is not found" in str(caught.value)

    async def test_an_error_body_that_is_not_googles_envelope_is_ignored(self) -> None:
        """Only `error.message` is trusted, so an odd body contributes nothing."""

        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(500, json={"error": {"detail": "image bytes here"}})

        with pytest.raises(ProviderError) as caught:
            await self._provider(handler).scan_garment([scan_image()])

        assert "500" in str(caught.value)
        assert "image bytes here" not in str(caught.value)

    async def test_a_non_json_error_body_is_survivable(self) -> None:
        """A proxy's HTML error page must not turn into a crash."""

        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(502, text="<html>Bad Gateway</html>")

        with pytest.raises(ProviderError) as caught:
            await self._provider(handler).scan_garment([scan_image()])

        assert "502" in str(caught.value)
        assert "html" not in str(caught.value).lower()

    async def test_an_unexpected_response_shape_is_reported_clearly(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json={"unexpected": True})

        with pytest.raises(ProviderError, match="unexpected response shape"):
            await self._provider(handler).scan_garment([scan_image()])

    def test_refuses_to_construct_without_a_key(self) -> None:
        with pytest.raises(ProviderError, match="no API key"):
            GeminiVisionProvider(api_key="")


class TestRegistry:
    def test_creates_a_registered_provider(self) -> None:
        registry = ProviderRegistry()
        registry.register("fake", FakeVisionProvider)

        assert registry.is_registered("fake")
        assert registry.create("fake").name == "fake"

    def test_rejects_a_duplicate_registration(self) -> None:
        registry = ProviderRegistry()
        registry.register("fake", FakeVisionProvider)

        with pytest.raises(ValueError, match="already registered"):
            registry.register("fake", FakeVisionProvider)

    def test_an_unknown_name_lists_what_is_available(self) -> None:
        registry = ProviderRegistry()
        registry.register("fake", FakeVisionProvider)

        with pytest.raises(KeyError) as caught:
            registry.create("nope")

        assert "fake" in str(caught.value)

    def test_registration_does_not_construct_the_provider(self) -> None:
        """Importing a provider must not open a connection or need a key."""
        registry = ProviderRegistry()
        constructed = {"count": 0}

        def factory() -> Any:
            constructed["count"] += 1
            return FakeVisionProvider()

        registry.register("counted", factory)
        assert constructed["count"] == 0

        registry.create("counted")
        assert constructed["count"] == 1


class TestScanImagePrivacy:
    def test_repr_omits_the_bytes(self) -> None:
        image = ScanImage(data=b"\x89PNG\r\n\x1a\nsecret-image-data", mime_type="image/png")
        rendered = repr(image)

        assert "secret-image-data" not in rendered
        assert "PNG" not in rendered
        assert "image/png" in rendered


class TestWhereTheGarmentWasMade:
    """The country printed beside the fibre content.

    Read here rather than by the garment scan, because a photograph of a
    jumper does not show where it came from. Everything below is about the
    string the app then groups, filters and sorts on: two spellings of one
    country would split a wardrobe on the model's phrasing rather than on
    anything printed on a tag.
    """

    def test_a_printed_country_is_read(self) -> None:
        result = _parse_care_tag(
            {
                "instructions": {"maxTempC": 30},
                "confidence": 0.9,
                "countryOfOrigin": "Portugal",
                "countryOfOriginConfidence": 0.94,
            }
        )

        assert result.country_of_origin is not None
        assert result.country_of_origin.value == "Portugal"
        assert result.country_of_origin.source is Provenance.TAG_SCAN

    def test_the_made_in_is_stripped_when_a_model_includes_it(self) -> None:
        # Asked for the country alone, but models oblige inconsistently, and
        # "Portugal" and "Made in Portugal" arriving as two places would split
        # a wardrobe by phrasing.
        result = _parse_care_tag(
            {
                "instructions": {"maxTempC": 30},
                "confidence": 0.9,
                "countryOfOrigin": "Made in Portugal",
            }
        )

        assert result.country_of_origin is not None
        assert result.country_of_origin.value == "Portugal"

    def test_the_printed_language_survives(self) -> None:
        # Never translated, for the same reason `rawText` is not: it is what
        # somebody checks against the tag in their hand.
        result = _parse_care_tag(
            {
                "instructions": {"maxTempC": 30},
                "confidence": 0.9,
                "countryOfOrigin": "Fabriqué en Tunisie",
            }
        )

        assert result.country_of_origin is not None
        assert result.country_of_origin.value == "Fabriqué en Tunisie"

    def test_a_label_that_does_not_say_reports_nothing(self) -> None:
        # The ordinary case, and it must stay null rather than becoming an
        # empty country that filters and tallies as a real place.
        result = _parse_care_tag({"instructions": {"maxTempC": 30}, "confidence": 0.9})

        assert result.country_of_origin is None

    @pytest.mark.parametrize("raw", ["", "   ", ".", 42, None, []])
    def test_nothing_usable_becomes_nothing(self, raw: Any) -> None:
        result = _parse_care_tag(
            {
                "instructions": {"maxTempC": 30},
                "confidence": 0.9,
                "countryOfOrigin": raw,
            }
        )

        assert result.country_of_origin is None

    def test_the_prompt_forbids_inferring_it(self) -> None:
        # The country is on the tag or it is not. Guessing it from the brand
        # or from the language of the words states a fact about the garment
        # that its label does not.
        from app.services.ai.prompts import CARE_TAG_PROMPT

        assert "Do not infer a country from the brand" in CARE_TAG_PROMPT

    async def test_the_fake_prints_it_in_the_labels_own_language(self) -> None:
        # So the whole pipeline carries a country that must not be translated,
        # without a test having to ask for one.
        provider = FakeVisionProvider()
        countries = set()
        for seed in range(6):
            result = await provider.scan_care_tag([scan_image(seed)])
            if result.country_of_origin is not None:
                countries.add(result.country_of_origin.value)

        assert countries == {"Portugal", "Tunisie"}
