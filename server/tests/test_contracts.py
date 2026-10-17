"""The cross-language contract.

Two independent checks, and they fail for different reasons:

1. Every golden fixture in `contracts/examples/` validates against the JSON
   Schema. That catches a fixture drifting from the normative definition.
2. Every response this server produces validates against the same schema. That
   catches the *server* drifting — which is the failure that reaches a phone.

The Dart side parses the identical fixtures, so a field renamed in one language
and not the other fails a test here or there rather than at runtime.
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from tests.conftest import png_bytes
from tests.selling_support import (
    Gemini,
    Tavily,
    answer,
    hostile_tavily,
    lying_reader_says,
    price_request,
    reply,
    searcher_for,
    serving,
    standard_tavily,
    status,
)

CONTRACTS = Path(__file__).resolve().parents[2] / "contracts"


def _load() -> tuple[dict[str, Any], Registry]:  # type: ignore[type-arg]
    """The scan schema plus a registry that can resolve its references."""
    schemas = {path.name: json.loads(path.read_text()) for path in CONTRACTS.glob("*.schema.json")}
    # Registered under both the bare filename (how the $ref is written) and the
    # canonical $id, so relative and absolute references both resolve.
    registry = Registry().with_resources(
        [(name, Resource.from_contents(body)) for name, body in schemas.items()]
        + [(body["$id"], Resource.from_contents(body)) for body in schemas.values()]
    )
    return schemas["scan_results.schema.json"], registry


def _validator() -> Draft202012Validator:
    schema, registry = _load()
    return Draft202012Validator(schema, registry=registry)


def assert_valid(payload: dict[str, Any], *, label: str) -> None:
    errors = sorted(_validator().iter_errors(payload), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{label}: {list(e.path)}: {e.message}" for e in errors[:5])


def fixture_names() -> list[str]:
    return sorted(path.name for path in (CONTRACTS / "examples").glob("*.json"))


@pytest.mark.parametrize("name", fixture_names())
def test_golden_fixtures_match_the_schema(name: str) -> None:
    payload = json.loads((CONTRACTS / "examples" / name).read_text())
    assert_valid(payload, label=name)


def test_the_three_result_shapes_are_mutually_exclusive() -> None:
    """`oneOf` only works if a payload matches exactly one alternative.

    If two shapes ever became indistinguishable, validation would start passing
    payloads the client cannot dispatch on.
    """
    schema, registry = _load()
    alternatives = [
        Draft202012Validator({"$defs": schema["$defs"], **branch}, registry=registry)
        for branch in schema["oneOf"]
    ]

    for name in fixture_names():
        payload = json.loads((CONTRACTS / "examples" / name).read_text())
        matches = sum(1 for validator in alternatives if not list(validator.iter_errors(payload)))
        assert matches == 1, f"{name} matched {matches} alternatives, expected 1"


class TestLiveResponsesMatchTheContract:
    """What the server actually returns, not what it intends to."""

    def test_garment_scan(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/garment",
            files=[("images", ("front.png", png_bytes(11), "image/png"))],
        )
        assert response.status_code == 200
        assert_valid(response.json(), label="live garment scan")

    def test_care_tag_scan(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/care-tag",
            files={"image": ("tag.png", png_bytes(12), "image/png")},
        )
        assert response.status_code == 200
        assert_valid(response.json(), label="live care tag scan")

    def test_pile_scan(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/pile",
            files={"image": ("pile.png", png_bytes(13), "image/png")},
        )
        assert response.status_code == 200
        assert_valid(response.json(), label="live pile scan")


class TestUnstatedFieldsAreAbsent:
    """The semantic the whole care model rests on.

    An unstated care field must be *absent* from the JSON. If it serialised as
    an explicit null, the Dart core would decode it as a stated value and treat
    a guess as the manufacturer's instruction. See ADR 4.
    """

    def test_no_care_field_is_ever_explicitly_null(self, client: TestClient) -> None:
        # Several seeds, because the fake reports an unreadable symbol on only
        # some of them and both paths must hold.
        for seed in range(8):
            response = client.post(
                "/v1/scan/care-tag",
                files={"image": ("tag.png", png_bytes(seed), "image/png")},
            )
            instructions = response.json()["result"]["instructions"]
            nulls = [key for key, value in instructions.items() if value is None]
            assert not nulls, f"seed {seed} sent explicit nulls: {nulls}"

    def test_an_unreadable_symbol_omits_the_field_entirely(self, client: TestClient) -> None:
        found_incomplete = False
        for seed in range(12):
            response = client.post(
                "/v1/scan/care-tag",
                files={"image": ("tag.png", png_bytes(seed), "image/png")},
            )
            result = response.json()["result"]
            if result.get("unreadableSymbolCount", 0) == 0:
                continue

            found_incomplete = True
            assert "tumbleDryAllowed" not in result["instructions"], (
                "an unreadable drying symbol must leave the field absent, "
                "not present with a guessed value"
            )

        assert found_incomplete, "no seed produced an incomplete reading to check"


class TestTheWarningVocabularyIsOneVocabulary:
    """`CareWarning` exists three times — here, in the JSON Schema, and in Dart.

    The wire carries the identifier and Dart's `values.byName` matches on it,
    so a member spelled differently in one place is not a mismatch anyone sees
    reported: it is a decode failure on a real phone reading a real label.
    This repo has shipped that bug before, in a different enum.

    The Dart half of this pair lives in `packages/wardrobe_core/test/`, which
    parses these same identifiers out of the same file.
    """

    def _schema_warnings(self) -> list[str]:
        schema = json.loads((CONTRACTS / "care_constraint.schema.json").read_text())
        return list(schema["properties"]["warnings"]["items"]["enum"])

    def test_the_contract_lists_exactly_the_enum(self) -> None:
        from app.schemas.care import CareWarning

        assert sorted(self._schema_warnings()) == sorted(w.value for w in CareWarning)

    def test_neither_side_has_a_duplicate_hiding_a_missing_member(self) -> None:
        # Sorted-set equality above would pass if one side listed a member
        # twice and omitted another. Length is what rules that out.
        from app.schemas.care import CareWarning

        listed = self._schema_warnings()
        assert len(listed) == len(set(listed))
        assert len(listed) == len(CareWarning)


class TestThePromptAsksForEveryWarning:
    """A warning nothing asks for is a warning no label ever reports.

    `CareWarning` had ten members and `CARE_TAG_PROMPT` mentioned none of
    them, so a label printing "wash inside out, with like colors" in plain
    English produced an empty `warnings` list — the field existed at every
    layer and was never populated by anything but a fixture.
    """

    def test_every_member_appears_in_the_prompt(self) -> None:
        from app.schemas.care import CareWarning
        from app.services.ai.prompts import CARE_TAG_PROMPT

        missing = [w.value for w in CareWarning if w.value not in CARE_TAG_PROMPT]
        assert not missing, f"the care-tag prompt never asks for: {missing}"


# --- Selling ----------------------------------------------------------------
#
# `listing.schema.json` has its own golden fixtures, in a subfolder on purpose:
# the scan checks above glob `examples/*.json` without recursing, and these
# payloads are not scans. The same two questions are asked of them — does the
# fixture match the schema, and does what the server actually returns?

LISTING = CONTRACTS / "examples" / "listing"
LISTING_SCHEMA_ID = "https://washing-advice.app/contracts/listing.schema.json"


def _listing_schema() -> tuple[dict[str, Any], Registry]:  # type: ignore[type-arg]
    schema = json.loads((CONTRACTS / "listing.schema.json").read_text())
    _, registry = _load()
    return schema, registry


def assert_valid_listing(payload: dict[str, Any], *, label: str) -> None:
    """Validates against the schema's root, which is `oneOf` the two responses."""
    schema, registry = _listing_schema()
    validator = Draft202012Validator(schema, registry=registry)
    errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{label}: {list(e.path)}: {e.message}" for e in errors[:5])


def assert_valid_definition(payload: dict[str, Any], definition: str, *, label: str) -> None:
    """Validates against one `$defs` entry, the way a request body is checked."""
    _, registry = _listing_schema()
    validator = Draft202012Validator(
        {"$ref": f"{LISTING_SCHEMA_ID}#/$defs/{definition}"}, registry=registry
    )
    errors = sorted(validator.iter_errors(payload), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{label}: {list(e.path)}: {e.message}" for e in errors[:5])


def listing_response_fixtures() -> list[str]:
    return sorted(path.name for path in LISTING.glob("*.json"))


def listing_request_fixtures() -> list[str]:
    return sorted(path.name for path in (LISTING / "requests").glob("*.json"))


class TestTheListingFixtures:
    def test_there_are_fixtures_to_check(self) -> None:
        # A glob that matched nothing would make every parametrised test below
        # pass by not existing.
        assert len(listing_response_fixtures()) >= 4
        assert set(listing_request_fixtures()) >= {"describe_context.json", "price_search.json"}

    @pytest.mark.parametrize("name", listing_response_fixtures())
    def test_every_response_fixture_matches_the_schema(self, name: str) -> None:
        payload = json.loads((LISTING / name).read_text())

        assert_valid_listing(payload, label=name)

    @pytest.mark.parametrize("name", listing_response_fixtures())
    def test_and_exactly_one_of_the_two_response_shapes(self, name: str) -> None:
        """`oneOf` only works if a payload matches one alternative, not both.

        The app dispatches on the shape, so two indistinguishable responses
        would validate and then be decoded as the wrong one.
        """
        schema, registry = _listing_schema()
        alternatives = [
            Draft202012Validator({"$defs": schema["$defs"], **branch}, registry=registry)
            for branch in schema["oneOf"]
        ]
        payload = json.loads((LISTING / name).read_text())

        matches = sum(1 for validator in alternatives if not list(validator.iter_errors(payload)))

        assert matches == 1, f"{name} matched {matches} alternatives, expected 1"

    def test_the_describe_context_fixture_matches_its_definition(self) -> None:
        payload = json.loads((LISTING / "requests" / "describe_context.json").read_text())

        assert_valid_definition(payload, "describeContext", label="describe_context.json")

    def test_the_price_search_fixture_matches_its_definition(self) -> None:
        payload = json.loads((LISTING / "requests" / "price_search.json").read_text())

        assert_valid_definition(payload, "priceSearchRequest", label="price_search.json")

    def test_a_request_the_schema_refuses_is_refused(self) -> None:
        """The checks above would pass if the definitions accepted anything."""
        schema, registry = _listing_schema()
        validator = Draft202012Validator(
            {"$ref": f"{LISTING_SCHEMA_ID}#/$defs/priceSearchRequest"}, registry=registry
        )

        assert list(validator.iter_errors({"title": "Nike crewneck"}))
        assert schema["$defs"]["priceSearchRequest"]["additionalProperties"] is False


class TestLiveListingResponsesMatchTheContract:
    """What the server actually returns for a listing, not what it intends to."""

    def describe(self, client: TestClient, seeds: tuple[int, ...], **form: str) -> dict[str, Any]:
        response = client.post(
            "/v1/sell/describe",
            files=[
                ("images", (f"photo{seed}.png", png_bytes(seed), "image/png")) for seed in seeds
            ],
            data=form,
        )
        assert response.status_code == 200, response.text
        body: dict[str, Any] = response.json()
        return body

    def test_a_draft_from_one_photograph(self, client: TestClient) -> None:
        assert_valid_listing(self.describe(client, (21,)), label="live describe, one photograph")

    def test_a_draft_from_four(self, client: TestClient) -> None:
        body = self.describe(client, (21, 22, 23, 24))

        assert_valid_listing(body, label="live describe, four photographs")

    def test_a_draft_for_a_garment_the_wardrobe_knows(self, client: TestClient) -> None:
        context = (LISTING / "requests" / "describe_context.json").read_text()

        body = self.describe(client, (21,), context=context)

        assert_valid_listing(body, label="live describe, with the example context")

    def test_every_kind_of_draft_the_fake_can_write_validates(self, client: TestClient) -> None:
        # The fake varies on purpose: some drafts have a brand, a size and
        # flaws and some have none. All of those shapes have to be the schema's.
        for seed in range(40):
            assert_valid_listing(
                self.describe(client, (seed,)), label=f"live describe, seed {seed}"
            )

    def test_a_draft_is_a_describe_response_and_not_a_price_search(
        self, client: TestClient
    ) -> None:
        schema, registry = _listing_schema()
        describe_branch = Draft202012Validator(
            {"$defs": schema["$defs"], **schema["oneOf"][0]}, registry=registry
        )
        prices_branch = Draft202012Validator(
            {"$defs": schema["$defs"], **schema["oneOf"][1]}, registry=registry
        )

        body = self.describe(client, (21,))

        assert not list(describe_branch.iter_errors(body))
        assert list(prices_branch.iter_errors(body))

    # --- prices ---------------------------------------------------------------

    def prices(self, client: TestClient, **overrides: Any) -> dict[str, Any]:
        response = client.post("/v1/sell/prices", json=price_request(**overrides))
        assert response.status_code == 200, response.text
        body: dict[str, Any] = response.json()
        return body

    def test_a_search_with_no_key(self, client: TestClient) -> None:
        # The default wiring in a test run: no TAVILY_API_KEY, so no call.
        body = self.prices(client)

        assert body["result"]["status"] == "notConfigured"
        assert_valid_listing(body, label="live prices, no key")

    def test_a_search_with_no_key_is_the_contracts_example(self, client: TestClient) -> None:
        # The same request the fixture answers, so the two can be compared.
        example = json.loads((LISTING / "prices_not_configured.json").read_text())

        body = self.prices(client)

        assert body["result"] == example["result"]

    def test_a_search_that_found_prices(self) -> None:
        with serving(searcher=searcher_for(standard_tavily())) as client:
            body = self.prices(client)

        assert body["result"]["status"] == "ok"
        assert body["result"]["comparables"]
        assert body["result"]["retail"]
        assert_valid_listing(body, label="live prices, mocked search and the pattern reader")

    def test_a_search_read_by_a_model(self) -> None:
        gemini = Gemini(reply(lying_reader_says()))
        with serving(searcher=searcher_for(hostile_tavily(), reader=gemini.reader())) as client:
            body = self.prices(client)

        assert body["result"]["status"] == "ok"
        assert_valid_listing(body, label="live prices, mocked search and a model reader")

    def test_a_search_that_found_nothing(self) -> None:
        with serving(searcher=searcher_for(Tavily(answer(), answer()))) as client:
            body = self.prices(client)

        assert body["result"]["status"] == "ok"
        assert_valid_listing(body, label="live prices, nothing found")

    def test_an_answer_from_the_cache(self) -> None:
        with serving(searcher=searcher_for(standard_tavily())) as client:
            self.prices(client)
            body = self.prices(client)

        assert body["diagnostics"]["servedFromCache"] is True
        assert_valid_listing(body, label="live prices, from the cache")

    @pytest.mark.parametrize(
        ("name", "script", "expected"),
        [
            ("allowance used up", lambda: Tavily(status(432), status(432)), "quotaExceeded"),
            ("service broken", lambda: Tavily(status(500), status(500)), "unavailable"),
            ("key refused", lambda: Tavily(status(401), status(401)), "unavailable"),
        ],
    )
    def test_every_way_a_search_can_fail_is_still_the_schemas(
        self, name: str, script: Any, expected: str
    ) -> None:
        with serving(searcher=searcher_for(script())) as client:
            body = self.prices(client)

        assert body["result"]["status"] == expected
        assert_valid_listing(body, label=f"live prices, {name}")

    def test_a_model_that_is_down(self) -> None:
        gemini = Gemini(httpx.Response(500, json={"error": {"message": "down"}}))
        with serving(searcher=searcher_for(standard_tavily(), reader=gemini.reader())) as client:
            body = self.prices(client)

        assert body["result"]["status"] == "unavailable"
        assert_valid_listing(body, label="live prices, reader down")

    def test_a_price_search_is_a_price_search_and_not_a_describe_response(self) -> None:
        schema, registry = _listing_schema()
        describe_branch = Draft202012Validator(
            {"$defs": schema["$defs"], **schema["oneOf"][0]}, registry=registry
        )
        prices_branch = Draft202012Validator(
            {"$defs": schema["$defs"], **schema["oneOf"][1]}, registry=registry
        )

        with serving(searcher=searcher_for(standard_tavily())) as client:
            body = self.prices(client)

        assert not list(prices_branch.iter_errors(body))
        assert list(describe_branch.iter_errors(body))

    def test_the_time_a_search_ran_is_a_date_time(self) -> None:
        # The schema's `format: date-time` is not checked by the validator
        # without an optional package, so it is checked here.
        with serving(searcher=searcher_for(standard_tavily())) as client:
            body = self.prices(client)

        stamp = body["result"]["searchedAt"]
        assert stamp.endswith("Z")
        assert datetime.fromisoformat(stamp).utcoffset() == timedelta(0)

    def test_the_contracts_example_shapes_are_what_a_live_search_produces(self) -> None:
        # The golden fixture and a live answer have the same keys everywhere.
        example = json.loads((LISTING / "prices_ok.json").read_text())

        with serving(searcher=searcher_for(standard_tavily())) as client:
            body = self.prices(client)

        live = body["result"]
        assert set(live) == set(example["result"])
        assert set(live["comparables"][0]) <= set(example["result"]["comparables"][0]) | {
            "sold",
            "condition",
            "why",
        }
        assert set(live["retail"][0]) <= set(example["result"]["retail"][0])
        assert set(live["excluded"]) == set(example["result"]["excluded"])
        assert set(body["diagnostics"]) <= {
            "stagesRun",
            "stageAnswered",
            "servedFromCache",
            "elapsedMs",
        }
