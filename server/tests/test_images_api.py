"""The cutout endpoint."""

from __future__ import annotations

import io

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.api.v1.dependencies import reset_wiring
from app.main import create_app
from tests.test_cutout import NAVY, WHITE, photo


@pytest.fixture
def client() -> TestClient:
    reset_wiring()
    with TestClient(create_app()) as test_client:
        yield test_client
    reset_wiring()


def post(client: TestClient, data: bytes, *, mime: str = "image/png"):
    return client.post(
        "/v1/image/cutout",
        files={"image": ("garment.png", data, mime)},
    )


class TestSuccess:
    def test_returns_a_transparent_png(self, client):
        response = post(client, photo(WHITE, NAVY))

        assert response.status_code == 200
        assert response.headers["content-type"] == "image/png"

        image = Image.open(io.BytesIO(response.content))
        assert image.mode == "RGBA"

        alpha = image.split()[-1]
        width, height = alpha.size
        assert alpha.getpixel((width // 2, height // 2)) == 255
        assert alpha.getpixel((2, 2)) == 0

    def test_reports_how_much_of_the_frame_the_garment_filled(self, client):
        # In a header rather than the body, so the app can log and act on it
        # without decoding the PNG to find out.
        response = post(client, photo(WHITE, NAVY))

        assert float(response.headers["X-Cutout-Coverage"]) == pytest.approx(0.255, abs=0.03)
        assert response.headers["X-Cutout-Width"] == "420"
        assert response.headers["X-Cutout-Height"] == "560"

    def test_needs_no_credentials(self, client, monkeypatch):
        # The property the whole service is built to keep: nothing here calls a
        # model, so a cutout works with an empty environment and no billing.
        monkeypatch.delenv("GEMINI_API_KEY", raising=False)
        assert post(client, photo(WHITE, NAVY)).status_code == 200


class TestRefusal:
    def test_an_image_with_no_separable_subject_is_a_4xx(self, client):
        response = post(client, photo(WHITE, None))

        assert response.status_code == 422
        # The message has to tell the user what to *do*. "Segmentation failed"
        # is true and useless.
        assert "background" in response.text.lower()

    def test_a_failed_separation_is_refused_rather_than_returned(self, client):
        # A tiny speck separates cleanly and is not the garment. Returning it
        # would look like the feature worked.
        image = Image.new("RGB", (400, 400), WHITE)
        image.putpixel((200, 200), NAVY)
        for x in range(198, 203):
            for y in range(198, 203):
                image.putpixel((x, y), NAVY)
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")

        response = post(client, buffer.getvalue())
        assert response.status_code == 422

    def test_a_non_image_is_rejected(self, client):
        response = post(client, b"not an image at all", mime="text/plain")
        assert response.status_code in (415, 422)

    def test_an_empty_upload_is_rejected(self, client):
        response = post(client, b"")
        assert response.status_code in (415, 422)
