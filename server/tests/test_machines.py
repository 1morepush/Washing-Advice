"""Machine identification: the fake's determinism, Gemini's parsing, and the
two routes end to end.

Mirrors `test_providers.py`'s shape for the same reason: the code turning a
model's JSON into a `WasherProfile`/`DryerProfile` is what is most likely to
break silently, since nothing downstream re-validates it against the Dart
side that actually decodes it.
"""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.v1.dependencies import get_machine_identifier
from app.schemas.machines import DryerProfile, WasherProfile
from app.services.ai.base import ProviderError
from app.services.machines.fake import FakeMachineIdentifier
from app.services.machines.gemini_identifier import (
    GeminiMachineIdentifier,
    NotIdentifiedError,
    _parse_dryer,
    _parse_washer,
)
from tests.test_health import configured


class TestFakeMachineIdentifier:
    async def test_the_same_input_always_answers_the_same_way(self) -> None:
        identifier = FakeMachineIdentifier()

        first = await identifier.identify_washer("Samsung", "WF45T6000AW")
        second = await identifier.identify_washer("Samsung", "WF45T6000AW")

        assert first.model_dump() == second.model_dump()

    async def test_different_input_answers_differently(self) -> None:
        identifier = FakeMachineIdentifier()

        samsung = await identifier.identify_washer("Samsung", "WF45T6000AW")
        lg = await identifier.identify_washer("LG", "WM4000HWA")

        assert samsung.capacity_kg != lg.capacity_kg or samsung.programs != lg.programs

    async def test_reports_the_brand_and_model_it_was_given(self) -> None:
        identifier = FakeMachineIdentifier()

        washer = await identifier.identify_washer("Bosch", "WGA12400UC")
        dryer = await identifier.identify_dryer("Bosch", "WTG86401UC")

        assert (washer.brand, washer.model) == ("Bosch", "WGA12400UC")
        assert (dryer.brand, dryer.model) == ("Bosch", "WTG86401UC")

    async def test_never_claims_to_be_a_verified_model(self) -> None:
        identifier = FakeMachineIdentifier()

        washer = await identifier.identify_washer("Bosch", "WGA12400UC")

        assert washer.is_verified_model is False


class TestGeminiParsing:
    """`_parse_washer`/`_parse_dryer` against recorded response shapes."""

    def test_a_recognised_washer_is_parsed_into_a_profile(self) -> None:
        payload = {
            "identified": True,
            "capacityKg": 9.0,
            "programs": [
                {
                    "displayName": "Cotton",
                    "kind": "cotton",
                    "availableTempsC": [0, 30, 40, 60, 90],
                    "defaultTempC": 40,
                    "agitation": "normal",
                    "spinSpeedsRpm": [0, 600, 800, 1200, 1400],
                    "suitableFor": ["normal", "heavy"],
                    "maxLoadFraction": 1.0,
                    "typicalDurationMinutes": 130,
                }
            ],
            "options": ["steam", "delayStart"],
        }

        result = _parse_washer(payload, brand="Samsung", model="WF45T6000AW")

        assert isinstance(result, WasherProfile)
        assert result.capacity_kg == 9.0
        assert result.programs[0].display_name == "Cotton"
        assert result.is_verified_model is False

    def test_a_recognised_dryer_is_parsed_into_a_profile(self) -> None:
        payload = {
            "identified": True,
            "capacityKg": 7.5,
            "programs": [
                {
                    "displayName": "Normal",
                    "kind": "normal",
                    "availableHeats": ["low", "medium", "high"],
                    "defaultHeat": "medium",
                    "suitableFor": ["normal"],
                    "control": "sensor",
                    "typicalDurationMinutes": 55,
                }
            ],
        }

        result = _parse_dryer(payload, brand="LG", model="DLEX3900W")

        assert isinstance(result, DryerProfile)
        assert result.programs[0].default_heat.value == "medium"

    def test_ids_are_assigned_by_the_server_not_the_model(self) -> None:
        """Gemini's schema has no id field at all — this is what fills it in."""
        payload = {
            "identified": True,
            "programs": [
                {
                    "displayName": "Cotton",
                    "kind": "cotton",
                    "defaultTempC": 40,
                    "agitation": "normal",
                }
            ],
        }

        result = _parse_washer(payload, brand="Samsung", model="WF 45 T6000AW")

        assert result.id == "ai.washer.samsung.wf-45-t6000aw"
        assert result.programs[0].id == f"{result.id}.program-0"

    def test_a_machine_the_model_does_not_recognise_is_refused(self) -> None:
        with pytest.raises(NotIdentifiedError):
            _parse_washer({"identified": False}, brand="Nonesuch", model="XY9000")

    def test_identified_true_but_no_programs_is_also_refused(self) -> None:
        """A schema-valid but empty reply is not usable, whatever it claims."""
        with pytest.raises(NotIdentifiedError):
            _parse_washer({"identified": True, "programs": []}, brand="X", model="Y")


class TestGeminiTransport:
    def _identifier(self, handler: Any) -> GeminiMachineIdentifier:
        transport = httpx.MockTransport(handler)
        return GeminiMachineIdentifier(
            api_key="test-key",
            client=httpx.AsyncClient(transport=transport),
        )

    @staticmethod
    def _reply(payload: dict[str, Any]) -> httpx.Response:
        return httpx.Response(
            200,
            json={"candidates": [{"content": {"parts": [{"text": json.dumps(payload)}]}}]},
        )

    async def test_sends_no_image_parts_only_text(self) -> None:
        seen: dict[str, Any] = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["body"] = json.loads(request.content)
            return self._reply({"identified": False})

        with pytest.raises(NotIdentifiedError):
            await self._identifier(handler).identify_washer("Samsung", "WF45T6000AW")

        parts = seen["body"]["contents"][0]["parts"]
        assert len(parts) == 1
        assert "inline_data" not in parts[0]
        assert "Samsung" in parts[0]["text"]
        assert "WF45T6000AW" in parts[0]["text"]

    async def test_a_successful_reply_round_trips(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return self._reply(
                {
                    "identified": True,
                    "capacityKg": 9.0,
                    "programs": [
                        {
                            "displayName": "Cotton",
                            "kind": "cotton",
                            "defaultTempC": 40,
                            "agitation": "normal",
                        }
                    ],
                }
            )

        result = await self._identifier(handler).identify_washer("Samsung", "WF45T6000AW")

        assert result.capacity_kg == 9.0

    async def test_retries_once_on_unparseable_json(self) -> None:
        calls = {"count": 0}

        def handler(request: httpx.Request) -> httpx.Response:
            calls["count"] += 1
            if calls["count"] == 1:
                return httpx.Response(
                    200,
                    json={"candidates": [{"content": {"parts": [{"text": "sorry!"}]}}]},
                )
            return self._reply({"identified": False})

        with pytest.raises(NotIdentifiedError):
            await self._identifier(handler).identify_washer("Samsung", "WF45T6000AW")

        assert calls["count"] == 2

    async def test_an_http_error_reports_googles_own_explanation(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(
                404,
                json={"error": {"message": "models/gemini-9 is not found"}},
            )

        with pytest.raises(ProviderError) as caught:
            await self._identifier(handler).identify_washer("Samsung", "WF45T6000AW")

        assert "404" in str(caught.value)
        assert "not found" in str(caught.value)

    def test_refuses_to_construct_without_a_key(self) -> None:
        with pytest.raises(ProviderError, match="no API key"):
            GeminiMachineIdentifier(api_key="")


class TestRoutes:
    def test_identify_washer_returns_a_profile(self, client: TestClient) -> None:
        response = client.post(
            "/v1/machine/washer", json={"brand": "Samsung", "model": "WF45T6000AW"}
        )

        assert response.status_code == 200
        body = response.json()
        assert body["result"]["brand"] == "Samsung"
        assert body["result"]["programs"]
        assert body["diagnostics"]["stageAnswered"] == "fake"

    def test_identify_dryer_returns_a_profile(self, client: TestClient) -> None:
        response = client.post("/v1/machine/dryer", json={"brand": "LG", "model": "DLEX3900W"})

        assert response.status_code == 200
        assert response.json()["result"]["brand"] == "LG"

    def test_an_empty_brand_is_rejected(self, client: TestClient) -> None:
        response = client.post("/v1/machine/washer", json={"brand": "", "model": "X"})

        assert response.status_code == 422

    def test_a_missing_field_is_rejected(self, client: TestClient) -> None:
        response = client.post("/v1/machine/washer", json={"brand": "LG"})

        assert response.status_code == 422

    def test_an_unrecognised_machine_is_a_client_error_not_a_server_one(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """The model saying "I don't know this one" is a 422, not a 500 —
        the request was well-formed and got an honest answer, not a crash.
        """

        class _AlwaysUnidentified(FakeMachineIdentifier):
            async def identify_washer(self, brand: str, model: str) -> WasherProfile:
                raise NotIdentifiedError("gemini", "no reliable knowledge")

        from app.main import create_app

        app = create_app()
        app.dependency_overrides[get_machine_identifier] = _AlwaysUnidentified
        with TestClient(app) as test_client:
            response = test_client.post(
                "/v1/machine/washer", json={"brand": "Nonesuch", "model": "XY9000"}
            )

        assert response.status_code == 422
        assert response.json()["error"] == "machine_not_identified"

    def test_a_missing_credential_is_unavailable_not_a_crash(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        with configured(monkeypatch, VISION_PROVIDER="gemini", GEMINI_API_KEY=None) as test_client:
            response = test_client.post(
                "/v1/machine/washer", json={"brand": "Samsung", "model": "WF45T6000AW"}
            )

        assert response.status_code == 503
        assert response.json()["error"] == "provider_unavailable"
