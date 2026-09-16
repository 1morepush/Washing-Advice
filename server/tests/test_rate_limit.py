"""A rate-limited model, from the provider to the wire.

The free tier meters by the minute, and the one thing that makes a rate limit
worse is the next request. So a 429 from the model has to reach the app *as* a
429, with the wait attached — not as a stage declining ("try a better photo")
or a 503 ("the server is down"), both of which send the app straight back into
the same limit.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from app.api.v1.dependencies import get_pipeline
from app.core.errors import ProviderUnavailableError, RateLimitedError, from_provider_error
from app.main import create_app
from app.schemas.scan import GarmentScanResult, ScanKind
from app.services.ai.base import ProviderError, ScanImage, ScanRequest
from app.services.ai.pipeline import VisionPipeline
from app.services.ai.providers.fake import FakeVisionProvider
from app.services.ai.stages import ProviderStage
from tests.conftest import png_bytes, scan_image


class RateLimitedProvider(FakeVisionProvider):
    """The fake provider, refusing the way Gemini does when the minute is spent."""

    async def scan_garment(self, images: list[ScanImage]) -> GarmentScanResult:
        raise ProviderError("gemini", "rate limited", retry_after=42.0)


class BrokenProvider(FakeVisionProvider):
    async def scan_garment(self, images: list[ScanImage]) -> GarmentScanResult:
        raise ProviderError("gemini", "HTTP 500 from the Gemini API")


async def test_a_rate_limit_passes_through_the_stage_rather_than_declining() -> None:
    # Declining is right for every other provider failure: the pipeline
    # carries on and a cheaper stage may answer. Stages run cheapest first,
    # so by the time the model is asked nothing cheaper is left — and the
    # honest answer to "the model is busy" is not "the photo is bad".
    stage = ProviderStage(RateLimitedProvider())

    with pytest.raises(ProviderError) as raised:
        await stage.run(ScanRequest(kind=ScanKind.GARMENT, images=[scan_image()]))

    assert raised.value.retry_after == 42.0


async def test_every_other_provider_failure_still_declines() -> None:
    stage = ProviderStage(BrokenProvider())

    outcome = await stage.run(ScanRequest(kind=ScanKind.GARMENT, images=[scan_image()]))

    assert not outcome.answered
    assert "HTTP 500" in outcome.notes[0]


def test_a_rate_limit_becomes_a_429_with_the_wait_in_the_header() -> None:
    error = from_provider_error(ProviderError("gemini", "rate limited", retry_after=7.2))

    assert isinstance(error, RateLimitedError)
    response = error.to_response()
    assert response.status_code == 429
    # Rounded up: a header that says 7 for a wait of 7.2 sends the client
    # back a fraction early, into the same limit.
    assert response.headers["retry-after"] == "8"


def test_a_wait_under_a_second_is_still_a_second() -> None:
    error = from_provider_error(ProviderError("gemini", "rate limited", retry_after=0.0))

    assert isinstance(error, RateLimitedError)
    assert error.to_response().headers["retry-after"] == "1"


def test_anything_else_is_the_provider_being_unavailable() -> None:
    error = from_provider_error(ProviderError("gemini", "no API key configured"))

    assert isinstance(error, ProviderUnavailableError)
    assert error.to_response().status_code == 503


def test_a_rate_limited_scan_is_a_429_on_the_wire() -> None:
    """End to end: what the app actually receives.

    The status is what the app switches on, and the header is what its batch
    flow waits for. Either one lost in the plumbing and the app is back to
    "The scan failed (429)".
    """
    app = create_app()
    app.dependency_overrides[get_pipeline] = lambda: VisionPipeline(
        [ProviderStage(RateLimitedProvider())]
    )

    with TestClient(app) as client:
        response = client.post(
            "/v1/scan/garment",
            files={"images": ("tee.png", png_bytes(1), "image/png")},
        )

    assert response.status_code == 429
    assert response.headers["retry-after"] == "42"
    assert response.json()["error"] == "rate_limited"
    assert "busy" in response.json()["detail"]
