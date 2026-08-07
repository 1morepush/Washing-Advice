"""Cross-origin access for the browser-hosted app.

The app is a GitHub Pages page calling this API from a different origin, so
without the right CORS headers every request is blocked by the browser
before it reaches a route — this never shows up as a server-side failure the
test suite would otherwise catch.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.api.v1.dependencies import reset_wiring
from app.main import create_app


class TestAllowedOrigins:
    def test_the_configured_pages_origin_is_allowed(self) -> None:
        reset_wiring()
        client = TestClient(create_app())

        response = client.get("/v1/health", headers={"Origin": "https://1morepush.github.io"})

        assert response.headers["access-control-allow-origin"] == "https://1morepush.github.io"

    def test_local_development_is_always_allowed(self) -> None:
        reset_wiring()
        client = TestClient(create_app())

        response = client.get("/v1/health", headers={"Origin": "http://localhost:5173"})

        assert response.headers["access-control-allow-origin"] == "http://localhost:5173"

    def test_an_unrelated_origin_is_not_allowed(self) -> None:
        reset_wiring()
        client = TestClient(create_app())

        response = client.get("/v1/health", headers={"Origin": "https://evil.example"})

        assert "access-control-allow-origin" not in response.headers

    def test_extra_origins_can_be_configured(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv(
            "CORS_ALLOWED_ORIGINS", "https://1morepush.github.io,https://example.com"
        )
        reset_wiring()
        client = TestClient(create_app())

        response = client.get("/v1/health", headers={"Origin": "https://example.com"})

        assert response.headers["access-control-allow-origin"] == "https://example.com"
        reset_wiring()
