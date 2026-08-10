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
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from tests.conftest import png_bytes

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
