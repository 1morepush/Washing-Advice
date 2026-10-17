"""Writing a listing's facts: the fake, the prompt, Gemini's call, and the route.

The endpoint whose failure costs a seller a sale rather than a laundry cycle. A
draft that says "100% wool" over a garment that is acrylic, or a medium that is a
small, is a refund and a review, and the seller never knew the claim was in their
listing because a draft wrote it.

So the assertions worth having are the ones about what is *left out*: that a
fabric is never reported without a composition label in the photographs, that a
size is never reported without a size label, that nothing absent is ever sent as
null, and that a brand the seller typed is never second-guessed from a photograph.
Everything else here is plumbing around those.
"""

from __future__ import annotations

import json
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient
from pydantic import BaseModel

from app.api.v1.dependencies import get_listing_describer
from app.config import Settings
from app.main import create_app
from app.schemas.common import Confident, Provenance
from app.schemas.selling import (
    DescribeContext,
    KnownFacts,
    ListingFacts,
    SearchQueries,
)
from app.schemas.wardrobe import ItemType
from app.services.ai.base import ProviderError
from app.services.selling.base import DescribeRequest, ListingDescriber
from app.services.selling.fake import FakeListingDescriber
from app.services.selling.gemini_describer import GeminiListingDescriber, _parse
from app.services.selling.gemini_json import GeminiStructured
from app.services.selling.known import apply_known
from app.services.selling.prompts import LISTING_PROMPT, LISTING_SCHEMA, describe
from tests.conftest import png_bytes, scan_image

LISTING = Path(__file__).resolve().parents[2] / "contracts" / "examples" / "listing"

# The prompt with its line breaks taken out, so a test names a sentence rather
# than the place the editor happened to wrap it.
FLAT_PROMPT = " ".join(LISTING_PROMPT.split())

# The reading `contracts/examples/listing/describe.json` is the answer to.
GOOD_READING: dict[str, Any] = {
    "title": "Nike vintage crewneck sweatshirt grey",
    "itemType": "sweatshirt",
    "brand": "Nike",
    "brandConfidence": 0.93,
    "colors": ["Grey"],
    "material": "80% cotton, 20% polyester",
    "sizeOnTag": "M",
    "sizeConfidence": 0.9,
    "styleWords": ["vintage", "crewneck", "embroidered logo", "90s"],
    "era": "90s",
    "visibleFlaws": ["small mark on the left cuff"],
    "depopSearch": "Nike vintage crewneck sweatshirt grey",
    "retailSearch": "Nike Club Fleece crew sweatshirt grey",
}


def reading(**overrides: Any) -> dict[str, Any]:
    return {**GOOD_READING, **overrides}


def reply(payload: Any) -> httpx.Response:
    return httpx.Response(
        200,
        json={"candidates": [{"content": {"parts": [{"text": json.dumps(payload)}]}}]},
    )


def request_for(
    *seeds: int, known: KnownFacts | None = None, notes: str | None = None
) -> DescribeRequest:
    context = DescribeContext(known=known, notes=notes) if known or notes else None
    return DescribeRequest(images=[scan_image(seed) for seed in seeds or (1,)], context=context)


def known(**fields: Any) -> KnownFacts:
    return KnownFacts(**fields)


class Gemini:
    """A mocked Gemini that records every request and plays back scripted replies."""

    def __init__(self, *replies: httpx.Response | Callable[[httpx.Request], httpx.Response]):
        self._replies = list(replies)
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        # The last reply repeats, so a script of one answers every attempt.
        index = min(len(self.requests), len(self._replies)) - 1
        scripted = self._replies[index]
        if callable(scripted):
            return scripted(request)
        # A fresh response each time: one that has been read and closed once is
        # not a fair stand-in for the next attempt's.
        return httpx.Response(
            scripted.status_code, headers=scripted.headers, content=scripted.content
        )

    def bodies(self) -> list[dict[str, Any]]:
        return [json.loads(request.content) for request in self.requests]

    def prompts(self) -> list[str]:
        return [body["contents"][0]["parts"][0]["text"] for body in self.bodies()]

    def describer(self, **settings: Any) -> GeminiListingDescriber:
        return GeminiListingDescriber(
            api_key=settings.pop("api_key", "test-key"),
            client=httpx.AsyncClient(transport=httpx.MockTransport(self)),
            **settings,
        )


def nulls(value: Any, path: str = "$") -> list[str]:
    """Every place an explicit null appears, so none can hide in a nested object."""
    if value is None:
        return [path]
    if isinstance(value, dict):
        return [found for key, inner in value.items() for found in nulls(inner, f"{path}.{key}")]
    if isinstance(value, list):
        return [found for i, inner in enumerate(value) for found in nulls(inner, f"{path}[{i}]")]
    return []


@contextmanager
def serving(describer: ListingDescriber) -> Iterator[TestClient]:
    app = create_app()
    app.dependency_overrides[get_listing_describer] = lambda: describer
    with TestClient(app) as client:
        yield client


class TestTheFake:
    async def test_the_same_photograph_always_reads_the_same_way(self) -> None:
        describer = FakeListingDescriber()

        first = await describer.describe(request_for(3))
        second = await describer.describe(request_for(3))

        assert first.to_wire() == second.to_wire()

    async def test_different_photographs_read_differently(self) -> None:
        # A fake that returned one canned draft would make every screen test
        # look like it passed for the wrong reason.
        describer = FakeListingDescriber()

        titles = {(await describer.describe(request_for(seed))).title for seed in range(40)}

        assert len(titles) > 5

    async def test_a_second_photograph_does_not_change_the_reading(self) -> None:
        describer = FakeListingDescriber()

        alone = await describer.describe(request_for(3))
        with_back = await describer.describe(request_for(3, 4))

        assert alone.to_wire() == with_back.to_wire()

    async def test_it_works_with_one_photograph_and_with_four(self) -> None:
        describer = FakeListingDescriber()

        one = await describer.describe(request_for(1))
        four = await describer.describe(request_for(1, 2, 3, 4))

        assert one.title and four.title

    async def test_every_optional_field_is_sometimes_absent_and_sometimes_present(self) -> None:
        # The commonest real answer for a photograph with no label in it is a
        # draft with no brand, material or size. A screen only ever drawn with a
        # full draft has not been drawn.
        describer = FakeListingDescriber()
        drafts = [await describer.describe(request_for(seed)) for seed in range(60)]

        for optional in ("brand", "material", "size_on_tag", "era"):
            values = [getattr(draft, optional) for draft in drafts]
            assert any(value is None for value in values), f"{optional} is never absent"
            assert any(value is not None for value in values), f"{optional} is never present"
        assert any(not draft.visible_flaws for draft in drafts)
        assert any(draft.visible_flaws for draft in drafts)

    async def test_every_draft_is_within_the_contracts_bounds(self) -> None:
        # Constructing a `ListingFacts` is itself the check; this makes it loud
        # for a fake that drifts, rather than a failure inside a screen test.
        describer = FakeListingDescriber()

        for seed in range(60):
            draft = await describer.describe(request_for(seed))
            assert 3 <= len(draft.title) <= 80
            assert len(draft.colors) <= 3
            assert len(draft.style_words) <= 6

    async def test_a_known_brand_wins_and_is_in_the_title(self) -> None:
        describer = FakeListingDescriber()

        for seed in range(30):
            draft = await describer.describe(request_for(seed, known=known(brand="Patagonia")))

            assert draft.brand is not None
            assert draft.brand.value == "Patagonia"
            assert draft.brand.confidence == 1.0
            assert draft.brand.source is Provenance.USER_EDITED
            assert draft.title.startswith("Patagonia")

    async def test_every_known_fact_wins(self) -> None:
        describer = FakeListingDescriber()

        draft = await describer.describe(
            request_for(
                2,
                known=known(
                    item_type=ItemType.JEANS,
                    brand="Levi's",
                    colors=["Indigo"],
                    material="100% cotton",
                    size_label="W32 L30",
                ),
            )
        )

        assert draft.item_type is ItemType.JEANS
        assert draft.colors == ["Indigo"]
        assert draft.material == "100% cotton"
        assert draft.size_on_tag == Confident[str](
            value="W32 L30", confidence=1.0, source=Provenance.USER_EDITED
        )

    async def test_with_no_context_the_reading_is_the_photographs_alone(self) -> None:
        describer = FakeListingDescriber()

        plain = await describer.describe(request_for(5))
        with_empty_context = await describer.describe(
            DescribeRequest(images=[scan_image(5)], context=DescribeContext())
        )

        assert plain.to_wire() == with_empty_context.to_wire()

    def test_a_draft_needs_a_photograph(self) -> None:
        with pytest.raises(ValueError):
            DescribeRequest(images=[])

    def test_it_reports_its_name(self) -> None:
        assert FakeListingDescriber().name == "fake"


class TestKnownFactsOutrankTheReading:
    def facts(self, **overrides: Any) -> ListingFacts:
        fields: dict[str, Any] = {
            "title": "Adidas vintage crewneck sweatshirt grey",
            "item_type": ItemType.SWEATSHIRT,
            "brand": Confident[str](value="Adidas", confidence=0.7),
            "colors": ["Grey"],
            "material": "100% polyester",
            "size_on_tag": Confident[str](value="L", confidence=0.6),
            "style_words": ["vintage", "crewneck"],
            "era": "90s",
            "visible_flaws": ["small mark on the left cuff"],
            "search_queries": SearchQueries(
                depop="Adidas vintage crewneck grey", retail="Adidas crew sweatshirt grey"
            ),
        }
        fields.update(overrides)
        return ListingFacts(**fields)

    def test_nothing_known_changes_nothing(self) -> None:
        reading_ = self.facts()

        assert apply_known(reading_, None) is reading_

    def test_a_known_brand_is_a_user_edited_certainty(self) -> None:
        result = apply_known(self.facts(), known(brand="Nike"))

        assert result.brand == Confident[str](
            value="Nike", confidence=1.0, source=Provenance.USER_EDITED
        )

    def test_a_known_size_is_a_user_edited_certainty(self) -> None:
        result = apply_known(self.facts(), known(size_label="M"))

        assert result.size_on_tag == Confident[str](
            value="M", confidence=1.0, source=Provenance.USER_EDITED
        )

    def test_a_known_material_colours_and_type_replace_the_readings(self) -> None:
        result = apply_known(
            self.facts(),
            known(
                material="80% cotton, 20% polyester",
                colors=["Navy", "White"],
                item_type=ItemType.HOODIE,
            ),
        )

        assert result.material == "80% cotton, 20% polyester"
        assert result.colors == ["Navy", "White"]
        assert result.item_type is ItemType.HOODIE

    def test_what_is_not_known_is_left_as_read(self) -> None:
        result = apply_known(self.facts(), known(brand="Nike"))

        assert result.material == "100% polyester"
        assert result.size_on_tag is not None and result.size_on_tag.value == "L"
        assert result.colors == ["Grey"]
        assert result.era == "90s"
        assert result.visible_flaws == ["small mark on the left cuff"]

    def test_the_other_brand_is_taken_out_of_the_title_and_the_phrases(self) -> None:
        # A draft whose brand field says Nike and whose title says Adidas is
        # worse than either.
        result = apply_known(self.facts(), known(brand="Nike"))

        assert result.title == "Nike vintage crewneck sweatshirt grey"
        assert result.search_queries.depop == "Nike vintage crewneck grey"
        assert result.search_queries.retail == "Nike crew sweatshirt grey"
        assert "adidas" not in result.model_dump_json().lower()

    def test_a_brand_the_model_buried_mid_title_is_moved_to_the_front(self) -> None:
        reading_ = self.facts(title="Vintage Adidas crewneck sweatshirt grey")

        assert apply_known(reading_, known(brand="Nike")).title == (
            "Nike Vintage crewneck sweatshirt grey"
        )

    def test_a_brand_the_model_did_not_read_is_put_in_front(self) -> None:
        reading_ = self.facts(
            title="Vintage crewneck sweatshirt grey",
            brand=None,
            search_queries=SearchQueries(depop="vintage crewneck grey", retail="crew sweatshirt"),
        )

        result = apply_known(reading_, known(brand="Nike"))

        assert result.title == "Nike Vintage crewneck sweatshirt grey"
        assert result.search_queries.depop == "Nike vintage crewneck grey"
        assert result.search_queries.retail == "Nike crew sweatshirt"

    def test_a_title_that_already_names_the_brand_is_not_touched(self) -> None:
        reading_ = self.facts(title="nike VINTAGE crewneck sweatshirt grey")

        assert apply_known(reading_, known(brand="Nike")).title == (
            "nike VINTAGE crewneck sweatshirt grey"
        )

    def test_the_same_brand_spelt_differently_is_the_same_brand(self) -> None:
        reading_ = self.facts(title="Levis 501 jeans blue", brand=None)

        result = apply_known(reading_, known(brand="Levi's"))

        assert result.title == "Levis 501 jeans blue"

    def test_a_brand_inside_another_word_does_not_count_as_named(self) -> None:
        # "Ed" is not in "Red hoodie".
        reading_ = self.facts(title="Red hoodie oversized", brand=None)

        assert apply_known(reading_, known(brand="Ed")).title == "Ed Red hoodie oversized"

    def test_a_long_title_keeps_the_brand_and_loses_the_tail(self) -> None:
        long_title = "vintage crewneck sweatshirt embroidered logo oversized boxy streetwear grey"
        reading_ = self.facts(title=long_title, brand=None)

        result = apply_known(reading_, known(brand="Abercrombie & Fitch"))

        assert result.title.startswith("Abercrombie & Fitch vintage")
        assert len(result.title) <= 80

    def test_a_title_that_was_only_the_wrong_brand_stays_long_enough(self) -> None:
        # The contract wants three characters, and a two-letter brand replacing
        # a title that was just "Adidas" would leave two.
        reading_ = self.facts(title="Adidas")

        result = apply_known(reading_, known(brand="GU"))

        assert len(result.title) >= 3
        assert result.title.startswith("GU")

    def test_the_result_is_still_a_valid_listing(self) -> None:
        result = apply_known(
            self.facts(),
            known(
                brand="x" * 60,
                colors=["a", "b", "c"],
                size_label="x" * 30,
                material="m" * 120,
            ),
        )

        assert len(result.title) <= 80
        assert len(result.search_queries.depop) <= 120


class TestThePrompt:
    def test_it_forbids_a_material_without_a_composition_label(self) -> None:
        # The claim a buyer returns a garment over.
        assert "only if a care or composition label is photographed and legible" in FLAT_PROMPT
        assert "Never from how the fabric looks or would feel" in FLAT_PROMPT
        assert "omit `material` entirely" in FLAT_PROMPT

    def test_it_forbids_a_size_without_a_size_label(self) -> None:
        assert "only from a size label that is photographed" in FLAT_PROMPT
        assert "Never from how the garment sits on a bed or a hanger" in FLAT_PROMPT
        assert "omit `sizeOnTag` entirely" in FLAT_PROMPT

    def test_it_takes_a_brand_only_from_a_logo_or_a_label(self) -> None:
        assert "only from a logo or a brand label you can actually read" in FLAT_PROMPT
        assert "A swoosh-shaped print is not a Nike logo" in FLAT_PROMPT
        assert "Omit the brand rather than guess" in FLAT_PROMPT

    def test_it_asks_for_an_honest_confidence(self) -> None:
        assert "`brandConfidence` honestly" in FLAT_PROMPT

    def test_it_says_an_empty_list_of_flaws_is_not_a_promise(self) -> None:
        assert "It is not a promise that there are none" in FLAT_PROMPT

    def test_it_forbids_inventing_a_flaw(self) -> None:
        assert "Do not invent a flaw" in FLAT_PROMPT

    def test_it_limits_and_shapes_the_title(self) -> None:
        assert "At most 80 characters" in FLAT_PROMPT
        assert "No hype" in FLAT_PROMPT
        assert "most important first" in FLAT_PROMPT

    def test_it_keeps_the_brand_out_of_the_style_words(self) -> None:
        assert "Never the brand, which has its own field" in FLAT_PROMPT
        assert "never filler" in FLAT_PROMPT

    def test_it_asks_for_both_search_phrases(self) -> None:
        assert "depopSearch" in FLAT_PROMPT
        assert "retailSearch" in FLAT_PROMPT
        assert "in the brand's own naming" in FLAT_PROMPT

    def test_it_asks_for_plain_colour_names(self) -> None:
        assert "plain colour names" in FLAT_PROMPT
        assert "dominant one first" in FLAT_PROMPT

    def test_it_only_wants_an_era_the_photographs_show(self) -> None:
        assert "A purchase date is not an era" in FLAT_PROMPT

    def test_several_photographs_are_one_garment(self) -> None:
        assert "SEVERAL PHOTOGRAPHS ARE ONE GARMENT" in FLAT_PROMPT

    def test_with_nothing_known_nothing_is_claimed_to_be(self) -> None:
        assert "ALREADY KNOWS" not in describe(request_for(1))

    def test_known_facts_are_put_to_the_model_as_given(self) -> None:
        prompt = describe(
            request_for(
                1,
                known=known(
                    item_type=ItemType.SWEATSHIRT,
                    brand="Nike",
                    colors=["Grey"],
                    material="80% cotton, 20% polyester",
                    size_label="M",
                ),
            )
        )

        assert "THE SELLER ALREADY KNOWS THESE. They outrank anything you see" in prompt
        assert "- Brand: Nike" in prompt
        assert "- Item type: sweatshirt" in prompt
        assert "- Colours: Grey" in prompt
        assert "- Material, from the care label: 80% cotton, 20% polyester" in prompt
        assert "- Size, from the size label: M" in prompt

    def test_only_what_is_known_is_listed(self) -> None:
        prompt = describe(request_for(1, known=known(brand="Nike")))

        assert "- Brand: Nike" in prompt
        assert "- Size" not in prompt
        assert "- Material" not in prompt

    def test_a_note_is_background_not_listing_text(self) -> None:
        prompt = describe(request_for(1, notes="bought in 2019, worn twice"))

        assert '"bought in 2019, worn twice"' in prompt
        assert "background, not text for the listing" in prompt
        assert "Do not turn a purchase date" in prompt

    def test_the_schema_cannot_force_a_guess(self) -> None:
        # If material or size were required, a model with no label to read would
        # have to write something. Required means invented.
        required = set(LISTING_SCHEMA["required"])

        for optional in ("brand", "material", "sizeOnTag", "era", "brandConfidence"):
            assert optional not in required
            assert LISTING_SCHEMA["properties"][optional] is not None

    def test_the_schema_offers_only_the_closed_list_of_item_types(self) -> None:
        offered = LISTING_SCHEMA["properties"]["itemType"]["enum"]

        assert offered == [member.value for member in ItemType]

    def test_the_schema_and_the_contract_ask_for_the_same_things(self) -> None:
        # The fields the contract requires must be the fields the model is
        # required to supply, apart from the two search phrases, which the
        # parser can fall back on.
        assert {"title", "itemType", "colors", "styleWords", "visibleFlaws"} <= set(
            LISTING_SCHEMA["required"]
        )


class TestParsingGeminisReading:
    def test_a_good_reading_becomes_the_contracts_example(self) -> None:
        expected = json.loads((LISTING / "describe.json").read_text())["result"]

        assert _parse(GOOD_READING).to_wire() == expected

    def test_what_was_not_read_is_absent(self) -> None:
        facts = _parse(
            {
                "title": "Grey crewneck sweatshirt",
                "itemType": "sweatshirt",
                "colors": [],
                "styleWords": [],
                "visibleFlaws": [],
                "depopSearch": "grey crewneck sweatshirt",
                "retailSearch": "grey crewneck sweatshirt",
            }
        )

        assert facts.brand is None
        assert facts.material is None
        assert facts.size_on_tag is None
        assert facts.era is None
        assert "brand" not in facts.to_wire()
        assert "material" not in facts.to_wire()
        assert "sizeOnTag" not in facts.to_wire()

    def test_null_means_not_read(self) -> None:
        facts = _parse(reading(brand=None, material=None, sizeOnTag=None, era=None))

        assert facts.brand is None
        assert facts.material is None
        assert facts.size_on_tag is None
        assert facts.era is None

    @pytest.mark.parametrize("blank", ["", "   ", "\n"])
    def test_a_blank_value_is_not_read_either(self, blank: str) -> None:
        facts = _parse(reading(brand=blank, material=blank, sizeOnTag=blank, era=blank))

        assert facts.brand is None
        assert facts.material is None
        assert facts.size_on_tag is None
        assert facts.era is None

    def test_a_brand_and_a_size_are_marked_as_inferred_with_their_confidence(self) -> None:
        facts = _parse(GOOD_READING)

        assert facts.brand == Confident[str](
            value="Nike", confidence=0.93, source=Provenance.AI_INFERENCE
        )
        assert facts.size_on_tag == Confident[str](
            value="M", confidence=0.9, source=Provenance.AI_INFERENCE
        )

    def test_a_brand_with_no_confidence_is_half_sure_not_certain(self) -> None:
        facts = _parse(reading(brandConfidence=None, sizeConfidence="high"))

        assert facts.brand is not None and facts.brand.confidence == 0.5
        assert facts.size_on_tag is not None and facts.size_on_tag.confidence == 0.6

    def test_a_confidence_out_of_range_is_clamped(self) -> None:
        facts = _parse(reading(brandConfidence=1.4, sizeConfidence=-0.2))

        assert facts.brand is not None and facts.brand.confidence == 1.0
        assert facts.size_on_tag is not None and facts.size_on_tag.confidence == 0.0

    def test_a_runaway_title_is_cut_at_a_word_boundary(self) -> None:
        # Trimmed rather than refused: the head of a degenerate answer is the
        # real one, and refusing it would cost the seller the whole draft.
        runaway = "Nike vintage crewneck sweatshirt grey " + "stunning amazing must have " * 10

        title = _parse(reading(title=runaway)).title

        assert len(title) <= 80
        assert title.startswith("Nike vintage crewneck sweatshirt grey")
        assert not title.endswith(" ")

    def test_a_title_is_one_line(self) -> None:
        assert _parse(reading(title="Nike\nvintage   crewneck")).title == "Nike vintage crewneck"

    def test_more_than_three_colours_are_cut_to_three(self) -> None:
        facts = _parse(reading(colors=["Grey", "Navy", "White", "Red", "Green"]))

        assert facts.colors == ["Grey", "Navy", "White"]

    def test_a_colour_named_twice_is_one_colour(self) -> None:
        facts = _parse(reading(colors=["Grey", "grey", " GREY ", "Navy"]))

        assert facts.colors == ["Grey", "Navy"]

    def test_the_brand_is_not_a_style_word(self) -> None:
        facts = _parse(reading(styleWords=["Nike", "vintage", "nike", "crewneck"]))

        assert facts.style_words == ["vintage", "crewneck"]

    def test_at_most_six_style_words(self) -> None:
        facts = _parse(reading(styleWords=[f"word{n}" for n in range(10)]))

        assert len(facts.style_words) == 6

    def test_a_flaw_that_says_nothing_is_dropped_and_a_runaway_one_is_cut(self) -> None:
        facts = _parse(
            reading(visibleFlaws=["ab", "", "   ", "small mark on the left cuff", "x " * 200])
        )

        assert facts.visible_flaws[0] == "small mark on the left cuff"
        assert len(facts.visible_flaws) == 2
        assert len(facts.visible_flaws[1]) <= 120

    def test_at_most_five_flaws(self) -> None:
        facts = _parse(reading(visibleFlaws=[f"flaw number {n}" for n in range(9)]))

        assert len(facts.visible_flaws) == 5

    def test_a_search_phrase_the_model_left_out_is_the_title(self) -> None:
        facts = _parse(reading(depopSearch=None, retailSearch=""))

        assert facts.search_queries.depop == facts.title
        assert facts.search_queries.retail == facts.title

    def test_a_search_phrase_that_is_too_long_is_cut(self) -> None:
        facts = _parse(reading(depopSearch="nike crewneck " * 30))

        assert len(facts.search_queries.depop) <= 120

    def test_anything_that_is_not_a_list_where_a_list_belongs_is_empty(self) -> None:
        facts = _parse(reading(colors="Grey", styleWords=None, visibleFlaws=5))

        assert facts.colors == []
        assert facts.style_words == []
        assert facts.visible_flaws == []

    def test_an_item_type_outside_the_closed_list_is_refused(self) -> None:
        # Not repaired: a model that says "spacesuit" has failed the task, and
        # the retry with the problem fed back is the response.
        with pytest.raises(ValueError, match="itemType"):
            _parse(reading(itemType="spacesuit"))

    def test_a_missing_item_type_is_refused(self) -> None:
        bad = reading()
        del bad["itemType"]

        with pytest.raises(ValueError, match="itemType"):
            _parse(bad)

    def test_a_missing_title_is_refused(self) -> None:
        with pytest.raises(ValueError, match="title"):
            _parse(reading(title="  "))

    def test_a_two_letter_title_is_refused(self) -> None:
        with pytest.raises(ValueError, match="title"):
            _parse(reading(title="ab"))

    @pytest.mark.parametrize("not_an_object", [[], "text", 5, None])
    def test_a_reply_that_is_not_an_object_is_refused(self, not_an_object: Any) -> None:
        with pytest.raises(ValueError, match="JSON object"):
            _parse(not_an_object)


class TestTheGeminiCall:
    async def test_a_response_schema_is_sent_and_json_is_asked_for(self) -> None:
        gemini = Gemini(reply(GOOD_READING))

        await gemini.describer().describe(request_for(1))

        config = gemini.bodies()[0]["generationConfig"]
        assert config["responseMimeType"] == "application/json"
        assert config["responseSchema"] == LISTING_SCHEMA

    async def test_every_photograph_is_sent(self) -> None:
        gemini = Gemini(reply(GOOD_READING))

        await gemini.describer().describe(request_for(1, 2, 3, 4))

        parts = gemini.bodies()[0]["contents"][0]["parts"]
        pictures = [part for part in parts if "inlineData" in part]
        assert len(pictures) == 4
        assert {picture["inlineData"]["mimeType"] for picture in pictures} == {"image/png"}

    async def test_it_runs_cold(self) -> None:
        # Composition from evidence, not taste.
        gemini = Gemini(reply(GOOD_READING))

        await gemini.describer().describe(request_for(1))

        assert gemini.bodies()[0]["generationConfig"]["temperature"] <= 0.3

    async def test_the_key_goes_in_a_header_and_never_the_address(self) -> None:
        gemini = Gemini(reply(GOOD_READING))

        await gemini.describer(api_key="gem-secret-key").describe(request_for(1))

        request = gemini.requests[0]
        assert request.headers["x-goog-api-key"] == "gem-secret-key"
        assert "gem-secret-key" not in str(request.url)

    async def test_the_configured_model_is_the_one_called(self) -> None:
        gemini = Gemini(reply(GOOD_READING))

        await gemini.describer(model="gemini-test-model").describe(request_for(1))

        assert gemini.requests[0].url.path.endswith("/models/gemini-test-model:generateContent")

    async def test_it_can_be_built_from_the_settings(self) -> None:
        settings = Settings(gemini_api_key="from-settings", gemini_model="models/gemini-x")

        describer = GeminiListingDescriber.from_settings(settings)

        assert describer.name == "gemini"
        await describer.aclose()

    def test_it_cannot_be_built_without_a_key(self) -> None:
        with pytest.raises(ProviderError, match="GEMINI_API_KEY"):
            GeminiListingDescriber.from_settings(Settings(gemini_api_key=None))
        with pytest.raises(ProviderError, match="no API key"):
            GeminiListingDescriber(api_key="")

    async def test_the_known_facts_reach_the_model_in_the_prompt(self) -> None:
        gemini = Gemini(reply(GOOD_READING))

        await gemini.describer().describe(request_for(1, known=known(brand="Nike")))

        assert "- Brand: Nike" in gemini.prompts()[0]

    async def test_a_good_reading_is_the_drafts_facts(self) -> None:
        facts = await Gemini(reply(GOOD_READING)).describer().describe(request_for(1))

        assert facts.title == "Nike vintage crewneck sweatshirt grey"
        assert facts.item_type is ItemType.SWEATSHIRT
        assert facts.material == "80% cotton, 20% polyester"

    async def test_a_known_brand_overwrites_what_the_model_read(self) -> None:
        # The model read an Adidas logo; the seller says Nike. The seller's word
        # is not a candidate the model weighs against its own.
        wrong = reading(
            title="Adidas vintage crewneck sweatshirt grey",
            brand="Adidas",
            depopSearch="Adidas vintage crewneck grey",
            retailSearch="Adidas crew sweatshirt grey",
        )

        facts = await (
            Gemini(reply(wrong)).describer().describe(request_for(1, known=known(brand="Nike")))
        )

        assert facts.brand == Confident[str](
            value="Nike", confidence=1.0, source=Provenance.USER_EDITED
        )
        assert facts.title == "Nike vintage crewneck sweatshirt grey"
        assert facts.search_queries.depop == "Nike vintage crewneck grey"
        assert facts.search_queries.retail == "Nike crew sweatshirt grey"

    async def test_every_known_fact_overwrites_the_reading(self) -> None:
        facts = await (
            Gemini(reply(GOOD_READING))
            .describer()
            .describe(
                request_for(
                    1,
                    known=known(
                        item_type=ItemType.HOODIE,
                        brand="Champion",
                        colors=["Navy"],
                        material="100% cotton",
                        size_label="XL",
                    ),
                )
            )
        )

        assert facts.item_type is ItemType.HOODIE
        assert facts.brand is not None and facts.brand.value == "Champion"
        assert facts.colors == ["Navy"]
        assert facts.material == "100% cotton"
        assert facts.size_on_tag == Confident[str](
            value="XL", confidence=1.0, source=Provenance.USER_EDITED
        )

    async def test_a_reply_that_breaks_the_contract_is_retried_with_the_problem(self) -> None:
        gemini = Gemini(reply(reading(title="  ")), reply(GOOD_READING))

        facts = await gemini.describer().describe(request_for(1, 2))

        assert facts.title == "Nike vintage crewneck sweatshirt grey"
        assert len(gemini.requests) == 2
        retry = gemini.prompts()[1]
        assert retry.startswith(describe(request_for(1, 2)))
        assert "Your previous reply could not be used" in retry
        assert "title is missing" in retry
        # The photographs go again with it, or the retry would be a guess.
        retried_parts = gemini.bodies()[1]["contents"][0]["parts"]
        assert len([part for part in retried_parts if "inlineData" in part]) == 2

    async def test_an_item_type_outside_the_list_is_retried(self) -> None:
        gemini = Gemini(reply(reading(itemType="spacesuit")), reply(GOOD_READING))

        await gemini.describer().describe(request_for(1))

        assert "itemType must be one of the listed values" in gemini.prompts()[1]

    async def test_a_reply_that_is_not_json_is_retried(self) -> None:
        not_json = httpx.Response(
            200, json={"candidates": [{"content": {"parts": [{"text": "Sure! Here you go:"}]}}]}
        )
        gemini = Gemini(not_json, reply(GOOD_READING))

        facts = await gemini.describer().describe(request_for(1))

        assert facts.title
        assert "not valid JSON" in gemini.prompts()[1]

    async def test_it_retries_once_and_then_gives_up(self) -> None:
        gemini = Gemini(reply(reading(title="")))

        with pytest.raises(ProviderError, match="could not be used"):
            await gemini.describer().describe(request_for(1))

        assert len(gemini.requests) == 2

    async def test_the_thinking_is_not_mistaken_for_the_answer(self) -> None:
        thinking = httpx.Response(
            200,
            json={
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {"thought": True, "text": "Let me look at the label..."},
                                {"text": json.dumps(GOOD_READING)},
                            ]
                        }
                    }
                ]
            },
        )

        facts = await Gemini(thinking).describer().describe(request_for(1))

        assert facts.title == "Nike vintage crewneck sweatshirt grey"

    async def test_a_rate_limit_carries_how_long_to_wait(self) -> None:
        limited = httpx.Response(
            429, headers={"retry-after": "37"}, json={"error": {"message": "quota"}}
        )

        with pytest.raises(ProviderError) as raised:
            await Gemini(limited).describer().describe(request_for(1))

        assert raised.value.retry_after == 37.0
        assert "rate limited" in str(raised.value)

    async def test_any_other_http_failure_is_a_provider_error_with_the_reason(self) -> None:
        broken = httpx.Response(404, json={"error": {"message": "models/gemini-9 is not found"}})

        with pytest.raises(ProviderError, match=r"HTTP 404.*gemini-9 is not found") as raised:
            await Gemini(broken).describer().describe(request_for(1))

        assert raised.value.retry_after is None

    async def test_a_network_failure_is_a_provider_error(self) -> None:
        def refuse(request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError("no route to host")

        with pytest.raises(ProviderError, match="request failed"):
            await Gemini(refuse).describer().describe(request_for(1))

    async def test_a_blocked_reply_is_a_provider_error(self) -> None:
        # The shape a safety block comes back as: a candidate with a finishReason
        # and no content at all.
        blocked = httpx.Response(200, json={"candidates": [{"finishReason": "SAFETY"}]})

        with pytest.raises(ProviderError, match="unexpected response shape"):
            await Gemini(blocked).describer().describe(request_for(1))

    async def test_an_error_never_quotes_the_key_or_the_photographs(self) -> None:
        echoing = httpx.Response(
            500, json={"error": {"message": "bad request"}, "echo": "SECRET-IMAGE-BYTES"}
        )

        with pytest.raises(ProviderError) as raised:
            await Gemini(echoing).describer(api_key="gem-secret-key").describe(request_for(1))

        assert "gem-secret-key" not in str(raised.value)
        assert "SECRET-IMAGE-BYTES" not in str(raised.value)


class TestTheSharedCallFeedsBackTheProblemNotTheInput:
    """What the retry says to the model, when the reply broke a Pydantic model."""

    class Probe(BaseModel):
        count: int

    async def test_the_field_and_the_rule_are_fed_back_and_the_input_is_not(self) -> None:
        gemini = Gemini(reply({"count": "SENSITIVE-PAGE-TEXT"}), reply({"count": 3}))
        transport = GeminiStructured(
            "k", client=httpx.AsyncClient(transport=httpx.MockTransport(gemini))
        )

        result = await transport.generate(
            [{"text": "Count them."}],
            {"type": "object"},
            self.Probe.model_validate,
            temperature=0.0,
        )

        assert result.count == 3
        retry = gemini.prompts()[1]
        assert "count: Input should be a valid integer" in retry
        assert "SENSITIVE-PAGE-TEXT" not in retry

    async def test_what_is_fed_back_is_bounded(self) -> None:
        class Many(BaseModel):
            items: list[int]

        gemini = Gemini(reply({"items": ["x"] * 400}), reply({"items": [1]}))
        transport = GeminiStructured(
            "k", client=httpx.AsyncClient(transport=httpx.MockTransport(gemini))
        )

        await transport.generate(
            [{"text": "List."}], {"type": "object"}, Many.model_validate, temperature=0.0
        )

        retry = gemini.prompts()[1]
        assert len(retry) < len("List.") + 1000

    async def test_a_client_it_was_given_is_not_closed_by_it(self) -> None:
        client = httpx.AsyncClient(transport=httpx.MockTransport(Gemini(reply({"count": 1}))))
        transport = GeminiStructured("k", client=client)

        await transport.aclose()

        assert not client.is_closed
        await client.aclose()


class TestTheRoute:
    def post(self, client: TestClient, seeds: tuple[int, ...] = (1,), **form: str) -> Any:
        return client.post(
            "/v1/sell/describe",
            files=[
                ("images", (f"photo{seed}.png", png_bytes(seed), "image/png")) for seed in seeds
            ],
            data=form,
        )

    def test_it_writes_a_draft_from_one_photograph(self, client: TestClient) -> None:
        response = self.post(client)

        assert response.status_code == 200
        result = response.json()["result"]
        assert result["title"]
        assert result["itemType"]
        assert result["searchQueries"]["depop"]
        assert result["searchQueries"]["retail"]

    def test_and_from_four(self, client: TestClient) -> None:
        assert self.post(client, (1, 2, 3, 4)).status_code == 200

    def test_a_fifth_photograph_is_refused_like_the_scans_refuse_too_many(
        self, client: TestClient
    ) -> None:
        response = self.post(client, (1, 2, 3, 4, 5))

        assert response.status_code == 413
        assert response.json()["error"] == "payload_too_large"
        assert "at most 4 images" in response.json()["detail"]

    def test_a_photograph_is_required(self, client: TestClient) -> None:
        response = client.post("/v1/sell/describe", data={"context": "{}"})

        assert response.status_code == 422

    def test_something_that_is_not_an_image_is_refused_like_the_scans_refuse_it(
        self, client: TestClient
    ) -> None:
        response = client.post(
            "/v1/sell/describe",
            files=[("images", ("notes.txt", b"not a picture", "text/plain"))],
        )

        assert response.status_code == 415
        assert response.json()["error"] == "unsupported_media"

    def test_an_empty_file_is_refused(self, client: TestClient) -> None:
        response = client.post(
            "/v1/sell/describe", files=[("images", ("empty.png", b"", "image/png"))]
        )

        assert response.status_code == 415

    def test_the_scans_size_limit_applies(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("MAX_IMAGE_BYTES", "16")
        app = create_app()

        with TestClient(app) as client:
            response = self.post(client)

        assert response.status_code == 413
        assert "image is" in response.json()["detail"]

    def test_the_camera_may_label_a_photograph_as_anything(self, client: TestClient) -> None:
        # Clients routinely send application/octet-stream for a capture; the
        # bytes are consulted before anything is refused.
        response = client.post(
            "/v1/sell/describe",
            files=[("images", ("capture", png_bytes(1), "application/octet-stream"))],
        )

        assert response.status_code == 200

    def test_nothing_that_was_not_read_is_ever_null(self, client: TestClient) -> None:
        # Absent means the photographs did not show it. A null would be decoded
        # as a stated value, and a fabric stated as null is a fabric guessed.
        for seed in range(30):
            body = self.post(client, (seed,)).json()
            assert nulls(body) == [], f"seed {seed}: {nulls(body)}"

    def test_it_reports_which_describer_answered(self, client: TestClient) -> None:
        diagnostics = self.post(client).json()["diagnostics"]

        assert diagnostics["stagesRun"] == ["fake"]
        assert diagnostics["stageAnswered"] == "fake"
        assert diagnostics["elapsedMs"] >= 0

    def test_the_known_facts_in_the_context_win(self, client: TestClient) -> None:
        context = {
            "known": {"brand": "Patagonia", "sizeLabel": "L", "material": "100% nylon"},
            "notes": "bought in 2019, worn twice",
        }

        result = self.post(client, context=json.dumps(context)).json()["result"]

        assert result["brand"] == {
            "value": "Patagonia",
            "confidence": 1.0,
            "source": "userEdited",
        }
        assert result["sizeOnTag"] == {"value": "L", "confidence": 1.0, "source": "userEdited"}
        assert result["material"] == "100% nylon"
        assert result["title"].startswith("Patagonia")

    def test_the_contracts_own_example_context_is_accepted(self, client: TestClient) -> None:
        example = (LISTING / "requests" / "describe_context.json").read_text()

        result = self.post(client, context=example).json()["result"]

        assert result["itemType"] == "sweatshirt"
        assert result["colors"] == ["Grey"]
        assert result["brand"]["value"] == "Nike"

    @pytest.mark.parametrize("blank", ["", "   "])
    def test_a_blank_context_is_no_context(self, client: TestClient, blank: str) -> None:
        assert self.post(client, context=blank).status_code == 200

    def test_a_context_that_is_not_json_is_a_422_that_says_so(self, client: TestClient) -> None:
        response = self.post(client, context="{not json")

        assert response.status_code == 422
        body = response.json()
        assert body["error"] == "invalid_field"
        assert "'context'" in body["detail"]
        assert "valid JSON" in body["detail"] or "Invalid JSON" in body["detail"]
        assert "known" in body["hint"]

    def test_a_context_that_is_not_an_object_is_a_422(self, client: TestClient) -> None:
        response = self.post(client, context='["Nike"]')

        assert response.status_code == 422
        assert response.json()["error"] == "invalid_field"

    def test_an_unknown_key_is_named(self, client: TestClient) -> None:
        # Quietly ignored, a misspelt key would send a typed size back to be
        # guessed at from a photograph.
        response = self.post(client, context='{"known": {"sizelabel": "M"}}')

        assert response.status_code == 422
        assert "known.sizelabel" in response.json()["detail"]

    def test_a_value_the_schema_refuses_is_named(self, client: TestClient) -> None:
        response = self.post(client, context=json.dumps({"known": {"brand": "x" * 61}}))

        assert response.status_code == 422
        assert "known.brand" in response.json()["detail"]

    def test_an_item_type_the_wardrobe_does_not_have_is_named(self, client: TestClient) -> None:
        response = self.post(client, context='{"known": {"itemType": "spacesuit"}}')

        assert response.status_code == 422
        assert "known.itemType" in response.json()["detail"]

    def test_notes_are_bounded(self, client: TestClient) -> None:
        response = self.post(client, context=json.dumps({"notes": "x" * 301}))

        assert response.status_code == 422
        assert "notes" in response.json()["detail"]

    def test_a_bad_context_is_refused_before_any_model_is_asked(self) -> None:
        class Counting:
            name = "counting"
            calls = 0

            async def describe(self, request: DescribeRequest) -> ListingFacts:
                self.calls += 1
                raise AssertionError("must not be reached")

        describer = Counting()
        with serving(describer) as client:
            response = self.post(client, context="{not json")

        assert response.status_code == 422
        assert describer.calls == 0

    def test_a_gemini_failure_is_a_503_in_the_usual_envelope(self) -> None:
        gemini = Gemini(httpx.Response(500, json={"error": {"message": "backend down"}}))

        with serving(gemini.describer()) as client:
            response = self.post(client)

        assert response.status_code == 503
        body = response.json()
        assert body["error"] == "provider_unavailable"
        assert "HTTP 500" in body["detail"]

    def test_a_rate_limit_is_a_429_with_the_wait_in_the_header(self) -> None:
        limited = httpx.Response(429, headers={"retry-after": "42"}, json={"error": {}})
        gemini = Gemini(limited)

        with serving(gemini.describer()) as client:
            response = self.post(client)

        assert response.status_code == 429
        assert response.headers["retry-after"] == "42"
        assert response.json()["error"] == "rate_limited"

    def test_a_real_reading_goes_end_to_end(self) -> None:
        gemini = Gemini(reply(GOOD_READING))

        with serving(gemini.describer()) as client:
            response = self.post(client, (1, 2), context=json.dumps({"known": {"brand": "Nike"}}))

        assert response.status_code == 200
        body = response.json()
        assert body["diagnostics"]["stageAnswered"] == "gemini"
        assert body["result"]["brand"]["source"] == "userEdited"
        assert body["result"]["material"] == "80% cotton, 20% polyester"
        assert nulls(body) == []
        assert len(gemini.requests) == 1
