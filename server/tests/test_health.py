"""Health reporting, including when the service cannot actually scan."""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.v1.dependencies import close_providers, get_pipeline, reset_wiring
from app.main import create_app
from app.services.ai.providers.gemini import GeminiVisionProvider


@contextmanager
def configured(monkeypatch: pytest.MonkeyPatch, **env: str | None) -> Iterator[TestClient]:
    """A client running under specific environment settings.

    Goes through the environment rather than `dependency_overrides`, because
    `get_pipeline` resolves settings itself rather than receiving them injected
    — overriding the dependency would leave the pipeline reading the real
    environment and quietly test nothing.
    """
    for key, value in env.items():
        if value is None:
            monkeypatch.delenv(key, raising=False)
        else:
            monkeypatch.setenv(key, value)

    reset_wiring()
    try:
        with TestClient(create_app()) as test_client:
            yield test_client
    finally:
        reset_wiring()


class TestHealthy:
    def test_reports_ok_with_the_live_stage_list(self, client: TestClient) -> None:
        body = client.get("/v1/health").json()

        assert body["status"] == "ok"
        assert body["pipelineStages"] == ["knowledge-cache", "fake"]
        assert "problem" not in body


class TestDegraded:
    """The endpoint an operator hits to find out why scanning is broken.

    It must answer, not fail. A 503 here reads as "the service is down" to every
    monitor and load balancer — it takes the process out of rotation and pages
    someone, when the truth is that the service is up and misconfigured.
    """

    def test_a_missing_credential_degrades_rather_than_503s(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        with configured(monkeypatch, VISION_PROVIDER="gemini", GEMINI_API_KEY=None) as client:
            response = client.get("/v1/health")

        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "degraded"
        assert body["pipelineStages"] == []
        # And it says what to do about it.
        assert "GEMINI_API_KEY" in body["problem"]

    def test_an_unknown_provider_degrades_and_lists_the_real_ones(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        with configured(monkeypatch, VISION_PROVIDER="nonesuch") as client:
            response = client.get("/v1/health")

        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "degraded"
        assert "fake" in body["problem"]

    def test_a_degraded_service_still_reports_its_configuration(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        with configured(monkeypatch, VISION_PROVIDER="gemini", GEMINI_API_KEY=None) as client:
            body = client.get("/v1/health").json()

        assert body["visionProvider"] == "gemini"
        assert body["geminiConfigured"] is False
        assert body["availableProviders"] == ["fake", "gemini"]

    def test_reports_which_model_will_be_called(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """A 404 from the API is unanswerable without the model name.

        "No such model for this API version" only becomes actionable once the
        name that was sent is visible from outside the process.
        """
        with configured(
            monkeypatch,
            VISION_PROVIDER="gemini",
            GEMINI_API_KEY="k",
            GEMINI_MODEL="gemini-9-ultra",
        ) as client:
            body = client.get("/v1/health").json()

        assert body["geminiModel"] == "gemini-9-ultra"

    def test_omits_the_model_when_there_is_no_credential(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """Reported only where it means something — the model that gets called."""
        with configured(monkeypatch, VISION_PROVIDER="fake", GEMINI_API_KEY=None) as client:
            body = client.get("/v1/health").json()

        assert "geminiModel" not in body

    def test_the_credential_never_appears_in_the_response(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        with configured(
            monkeypatch,
            VISION_PROVIDER="gemini",
            GEMINI_API_KEY="super-secret-value",
        ) as client:
            raw = client.get("/v1/health").text

        assert "super-secret-value" not in raw


class TestConnectionReuse:
    """The provider keeps one client rather than building one per request.

    Rebuilding it per call throws away the connection pool, so every scan pays a
    fresh TCP connection and TLS handshake before it can begin uploading a
    multi-megabyte image.
    """

    async def test_the_same_client_is_reused_across_calls(self) -> None:
        calls = 0

        def handler(request: httpx.Request) -> httpx.Response:
            nonlocal calls
            calls += 1
            return httpx.Response(
                200,
                json={
                    "candidates": [
                        {"content": {"parts": [{"text": '{"type":"hoodie","typeConfidence":0.9}'}]}}
                    ]
                },
            )

        provider = GeminiVisionProvider(api_key="k")
        # Swap in a mock transport on the provider's own lazily-built client.
        provider._client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        first = provider._http()

        from tests.conftest import scan_image

        await provider.scan_garment([scan_image(1)])
        await provider.scan_garment([scan_image(2)])

        assert calls == 2
        assert provider._http() is first, "a new client was built mid-flight"

    async def test_closing_releases_a_client_it_created(self) -> None:
        provider = GeminiVisionProvider(api_key="k")
        created = provider._http()

        await provider.aclose()

        assert created.is_closed
        # A fresh call builds a new one rather than reusing a closed pool.
        assert provider._http() is not created
        await provider.aclose()

    async def test_closing_leaves_an_injected_client_alone(self) -> None:
        """An injected client belongs to whoever passed it in.

        Closing it here would break a caller sharing one client across several
        providers.
        """
        injected = httpx.AsyncClient()
        provider = GeminiVisionProvider(api_key="k", client=injected)

        await provider.aclose()

        assert not injected.is_closed
        await injected.aclose()

    async def test_shutdown_closes_providers_without_raising(self) -> None:
        # The fake provider has no aclose(); shutdown must tolerate that rather
        # than assuming every provider holds resources.
        reset_wiring()
        get_pipeline()
        await close_providers()


@pytest.fixture
def client() -> TestClient:
    reset_wiring()
    return TestClient(create_app())
