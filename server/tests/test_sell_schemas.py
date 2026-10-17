"""The selling wire models, against the golden fixtures and the schema's bounds.

`test_contracts.py` asks whether the fixtures match the JSON Schema. This asks
the other half of the same question: whether the server's own models read those
fixtures and write them back out unchanged. A field named differently here than
in the schema would pass the first and fail this, and it is the second that
decides what a phone receives.

The bounds are tested because they are what lets a response that was built be
a response that validates. A `Comparable` that could carry an `http://` link or
a pound price would only ever be caught by the live-response checks, and only if
one of them happened to produce it.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError

from app.schemas.common import Confident, Provenance
from app.schemas.scan import ScanDiagnostics
from app.schemas.selling import (
    Comparable,
    DescribeContext,
    DescribeResponse,
    ExcludedCounts,
    KnownFacts,
    ListingFacts,
    PriceSearch,
    PriceSearchRequest,
    PriceSearchResponse,
    PriceSearchStatus,
    RetailReference,
    SearchQueries,
)
from app.schemas.wardrobe import ItemType

LISTING = Path(__file__).resolve().parents[2] / "contracts" / "examples" / "listing"


def fixture(name: str) -> dict[str, Any]:
    loaded: dict[str, Any] = json.loads((LISTING / name).read_text())
    return loaded


def facts(**overrides: Any) -> ListingFacts:
    fields: dict[str, Any] = {
        "title": "Nike vintage crewneck sweatshirt grey",
        "item_type": ItemType.SWEATSHIRT,
        "colors": ["Grey"],
        "style_words": ["vintage"],
        "visible_flaws": [],
        "search_queries": SearchQueries(depop="nike crewneck", retail="nike club fleece crew"),
    }
    fields.update(overrides)
    return ListingFacts(**fields)


def comparable(**overrides: Any) -> Comparable:
    fields: dict[str, Any] = {
        "title": "Nike crewneck",
        "url": "https://www.depop.com/products/example/",
        "price": 28.0,
        "match": "same",
    }
    fields.update(overrides)
    return Comparable(**fields)


class TestTheFixturesParseIntoTheServersModels:
    @pytest.mark.parametrize("name", ["describe.json", "describe_minimal.json"])
    def test_a_describe_fixture_is_read_and_written_back_unchanged(self, name: str) -> None:
        payload = fixture(name)

        parsed = DescribeResponse.model_validate(payload)

        assert parsed.result.to_wire() == payload["result"]

    @pytest.mark.parametrize("name", ["prices_ok.json", "prices_not_configured.json"])
    def test_a_prices_fixture_is_read_and_written_back_unchanged(self, name: str) -> None:
        payload = fixture(name)

        parsed = PriceSearchResponse.model_validate(payload)

        assert parsed.result.to_wire() == payload["result"]

    def test_the_diagnostics_of_every_fixture_are_understood(self) -> None:
        for name in ("describe.json", "describe_minimal.json", "prices_not_configured.json"):
            diagnostics = ScanDiagnostics.model_validate(fixture(name)["diagnostics"])
            assert diagnostics.stages_run == fixture(name)["diagnostics"]["stagesRun"]

    def test_the_describe_context_fixture_is_understood(self) -> None:
        context = DescribeContext.model_validate(fixture("requests/describe_context.json"))

        assert context.known is not None
        assert context.known.item_type is ItemType.SWEATSHIRT
        assert context.known.brand == "Nike"
        assert context.known.colors == ["Grey"]
        assert context.known.material == "80% cotton, 20% polyester"
        assert context.known.size_label == "M"
        assert context.notes == "Bought in 2019, worn a handful of times"

    def test_the_price_search_fixture_is_understood(self) -> None:
        request = PriceSearchRequest.model_validate(fixture("requests/price_search.json"))

        assert request.queries.depop == "Nike vintage crewneck sweatshirt grey"
        assert request.queries.retail == "Nike Club Fleece crew sweatshirt grey"
        assert request.item_type is ItemType.SWEATSHIRT
        assert request.brand == "Nike"
        assert request.colors == ["Grey"]


class TestTheWireNames:
    def test_the_listing_facts_are_camel_case_and_leave_out_what_was_not_read(self) -> None:
        wire = facts().to_wire()

        assert set(wire) == {
            "title",
            "itemType",
            "colors",
            "styleWords",
            "visibleFlaws",
            "searchQueries",
        }

    def test_what_was_read_is_sent_under_the_contracts_names(self) -> None:
        wire = facts(
            brand=Confident[str](value="Nike", confidence=0.9),
            size_on_tag=Confident[str](value="M", confidence=0.8),
            material="100% cotton",
            era="90s",
        ).to_wire()

        assert wire["brand"] == {"value": "Nike", "confidence": 0.9, "source": "aiInference"}
        assert wire["sizeOnTag"]["value"] == "M"
        assert wire["material"] == "100% cotton"
        assert wire["era"] == "90s"

    def test_the_excluded_counts_use_the_contracts_names(self) -> None:
        wire = ExcludedCounts(not_usd=2, unverified_price=1, not_comparable=4).to_wire()

        assert wire == {"notUsd": 2, "unverifiedPrice": 1, "notComparable": 4}

    def test_the_statuses_are_the_contracts_words(self) -> None:
        assert {status.value for status in PriceSearchStatus} == {
            "ok",
            "notConfigured",
            "quotaExceeded",
            "unavailable",
        }

    def test_a_comparable_always_says_it_is_in_dollars(self) -> None:
        assert comparable().to_wire()["currency"] == "USD"

    def test_a_listing_still_for_sale_says_so_and_one_that_does_not_say_is_silent(self) -> None:
        # Three states, and `false` must not be swallowed as though it were
        # absent: the core weighs a sold price and an asking price differently.
        assert comparable(sold=False).to_wire()["sold"] is False
        assert comparable(sold=True).to_wire()["sold"] is True
        assert "sold" not in comparable().to_wire()


class TestTheBoundsTheSchemaStates:
    def test_a_title_is_at_most_eighty_characters(self) -> None:
        facts(title="x" * 80)
        with pytest.raises(ValidationError):
            facts(title="x" * 81)

    def test_a_title_is_at_least_three(self) -> None:
        with pytest.raises(ValidationError):
            facts(title="ab")

    def test_at_most_three_colours(self) -> None:
        with pytest.raises(ValidationError):
            facts(colors=["a", "b", "c", "d"])

    def test_at_most_six_style_words(self) -> None:
        with pytest.raises(ValidationError):
            facts(style_words=[f"w{n}" for n in range(7)])

    def test_at_most_five_flaws_each_at_least_three_characters(self) -> None:
        with pytest.raises(ValidationError):
            facts(visible_flaws=[f"flaw {n}" for n in range(6)])
        with pytest.raises(ValidationError):
            facts(visible_flaws=["ab"])

    def test_the_search_phrases_are_three_to_a_hundred_and_twenty_characters(self) -> None:
        with pytest.raises(ValidationError):
            SearchQueries(depop="ab", retail="nike crewneck")
        with pytest.raises(ValidationError):
            SearchQueries(depop="nike crewneck", retail="x" * 121)

    def test_an_era_is_at_most_twenty_characters(self) -> None:
        with pytest.raises(ValidationError):
            facts(era="x" * 21)

    def test_the_colours_are_required_even_when_there_are_none(self) -> None:
        # Absent would read as "not read"; an empty list says there were none
        # to name. The schema requires them, and so does the model.
        with pytest.raises(ValidationError):
            ListingFacts.model_validate(
                {
                    "title": "Grey crewneck",
                    "itemType": "sweatshirt",
                    "styleWords": [],
                    "visibleFlaws": [],
                    "searchQueries": {"depop": "grey crewneck", "retail": "grey crewneck"},
                }
            )

    def test_a_confidence_outside_zero_to_one_is_refused(self) -> None:
        with pytest.raises(ValidationError):
            Confident[str](value="Nike", confidence=1.2)


class TestAPriceIsAPriceInDollarsFromAPageWeCanPointTo:
    def test_a_price_must_be_positive(self) -> None:
        with pytest.raises(ValidationError):
            comparable(price=0)
        with pytest.raises(ValidationError):
            comparable(price=-5)

    def test_a_price_is_at_most_a_hundred_thousand(self) -> None:
        comparable(price=100_000)
        with pytest.raises(ValidationError):
            comparable(price=100_000.01)

    def test_only_dollars_are_carried(self) -> None:
        with pytest.raises(ValidationError):
            comparable(currency="GBP")

    def test_a_link_must_be_https(self) -> None:
        with pytest.raises(ValidationError):
            comparable(url="http://www.depop.com/products/example/")

    def test_a_link_has_a_length_limit(self) -> None:
        with pytest.raises(ValidationError):
            comparable(url="https://www.depop.com/" + "a" * 2048)

    def test_a_match_is_same_or_similar(self) -> None:
        with pytest.raises(ValidationError):
            comparable(match="identical")

    def test_the_text_fields_have_the_schemas_limits(self) -> None:
        with pytest.raises(ValidationError):
            comparable(title="")
        with pytest.raises(ValidationError):
            comparable(title="x" * 201)
        with pytest.raises(ValidationError):
            comparable(condition="x" * 41)
        with pytest.raises(ValidationError):
            comparable(why="x" * 161)

    def test_a_retail_reference_has_the_same_guarantees(self) -> None:
        RetailReference(
            title="Nike Club Fleece Crew",
            url="https://www.nike.com/t/example",
            price=60.0,
            match="similar",
            seller="nike.com",
        )
        with pytest.raises(ValidationError):
            RetailReference(
                title="x", url="http://nike.com/t", price=60.0, match="similar", seller="nike.com"
            )
        with pytest.raises(ValidationError):
            RetailReference(
                title="x", url="https://nike.com/t", price=60.0, match="similar", seller="x" * 81
            )

    def test_at_most_twelve_comparables_and_six_retail(self) -> None:
        queries = SearchQueries(depop="nike crewneck", retail="nike crew")
        base: dict[str, Any] = {
            "status": PriceSearchStatus.OK,
            "queries": queries,
            "excluded": ExcludedCounts.zero(),
        }

        PriceSearch(comparables=[comparable() for _ in range(12)], retail=[], **base)
        with pytest.raises(ValidationError):
            PriceSearch(comparables=[comparable() for _ in range(13)], retail=[], **base)

        retail = RetailReference(title="x", url="https://nike.com/t", price=60.0, match="same")
        PriceSearch(comparables=[], retail=[retail] * 6, **base)
        with pytest.raises(ValidationError):
            PriceSearch(comparables=[], retail=[retail] * 7, **base)

    def test_a_search_time_must_say_which_time_zone(self) -> None:
        # "2026-10-17T14:05:00" with no zone is a time nobody can place.
        with pytest.raises(ValidationError):
            PriceSearch.model_validate(
                {
                    "status": "ok",
                    "searchedAt": "2026-10-17T14:05:00",
                    "queries": {"depop": "nike crewneck", "retail": "nike crew"},
                    "comparables": [],
                    "retail": [],
                    "excluded": {"notUsd": 0, "unverifiedPrice": 0, "notComparable": 0},
                }
            )

    def test_the_counts_cannot_be_negative(self) -> None:
        with pytest.raises(ValidationError):
            ExcludedCounts(not_usd=-1, unverified_price=0, not_comparable=0)


class TestTheRequestsRefuseWhatTheSchemaRefuses:
    def test_an_unknown_key_in_the_context_is_refused(self) -> None:
        # A misspelt `sizelabel` quietly ignored would turn the typed size back
        # into a guess from a photograph.
        with pytest.raises(ValidationError, match="sizelabel"):
            DescribeContext.model_validate({"known": {"sizelabel": "M"}})

    def test_an_unknown_top_level_key_is_refused(self) -> None:
        with pytest.raises(ValidationError):
            DescribeContext.model_validate({"note": "worn twice"})

    def test_an_unknown_key_in_a_price_search_is_refused(self) -> None:
        payload = fixture("requests/price_search.json")
        payload["size"] = "M"

        with pytest.raises(ValidationError):
            PriceSearchRequest.model_validate(payload)

    def test_the_known_facts_have_the_schemas_limits(self) -> None:
        with pytest.raises(ValidationError):
            KnownFacts(brand="x" * 61)
        with pytest.raises(ValidationError):
            KnownFacts(material="x" * 121)
        with pytest.raises(ValidationError):
            KnownFacts(size_label="x" * 31)
        with pytest.raises(ValidationError):
            KnownFacts(colors=["a", "b", "c", "d"])
        with pytest.raises(ValidationError):
            KnownFacts(colors=["x" * 31])

    def test_the_notes_are_at_most_three_hundred_characters(self) -> None:
        DescribeContext(notes="x" * 300)
        with pytest.raises(ValidationError):
            DescribeContext(notes="x" * 301)

    def test_an_item_type_the_wardrobe_does_not_have_is_refused(self) -> None:
        with pytest.raises(ValidationError):
            KnownFacts.model_validate({"itemType": "spacesuit"})

    def test_a_cleared_field_is_not_a_known_fact(self) -> None:
        # A garment whose brand was cleared sends "", and taking that as the
        # brand would overwrite the photographs with nothing.
        known = KnownFacts.model_validate(
            {"brand": "  ", "material": "", "sizeLabel": "", "colors": ["", " "]}
        )

        assert known.brand is None
        assert known.material is None
        assert known.size_label is None
        assert known.colors is None

    def test_a_typed_value_is_trimmed(self) -> None:
        known = KnownFacts.model_validate({"brand": "  Nike ", "colors": [" Grey ", ""]})

        assert known.brand == "Nike"
        assert known.colors == ["Grey"]

    def test_the_price_search_phrases_must_be_three_characters_or_more(self) -> None:
        payload = fixture("requests/price_search.json")
        payload["queries"]["depop"] = "  ab "

        with pytest.raises(ValidationError):
            PriceSearchRequest.model_validate(payload)

    def test_the_price_search_needs_its_three_required_fields(self) -> None:
        for missing in ("queries", "itemType", "title"):
            payload = fixture("requests/price_search.json")
            del payload[missing]
            with pytest.raises(ValidationError):
                PriceSearchRequest.model_validate(payload)

    def test_a_brand_and_colours_are_optional_in_a_price_search(self) -> None:
        payload = fixture("requests/price_search.json")
        del payload["brand"]
        del payload["colors"]

        request = PriceSearchRequest.model_validate(payload)

        assert request.brand is None
        assert request.colors is None

    def test_the_provenance_a_known_brand_is_given_is_the_strongest(self) -> None:
        # Pinned here because the whole point of a known fact is that nothing
        # outranks it, and `userEdited` is the top of the order by declaration.
        assert max(Provenance, key=lambda p: p.resolution_rank) is Provenance.USER_EDITED
