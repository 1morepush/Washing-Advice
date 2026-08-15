"""The HTTP surface: what a client actually sees."""

from __future__ import annotations

import asyncio
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.services.ai.base import ScanImage
from app.services.ai.providers.fake import FakeVisionProvider
from tests.conftest import png_bytes


def find_image(*, complete: bool) -> bytes:
    """An image the fake reads completely, or doesn't.

    Which seeds read cleanly depends on the image hash, so it is discovered
    rather than hard-coded — a fixed seed makes the caching tests a coin flip
    that only fails once the fake's hashing changes.

    The provider is asked directly rather than through the API, because probing
    over HTTP would populate the very cache the caller is about to test.
    """
    provider = FakeVisionProvider()
    for seed in range(40):
        data = png_bytes(seed)
        result = asyncio.run(provider.scan_care_tag([ScanImage(data=data, mime_type="image/png")]))
        if result.is_complete is complete:
            return data
    raise AssertionError(f"no seed produced a complete={complete} reading")


class TestHealth:
    def test_reports_the_live_wiring(self, client: TestClient) -> None:
        body = client.get("/v1/health").json()

        assert body["status"] == "ok"
        assert body["visionProvider"] == "fake"
        assert body["geminiConfigured"] is False
        assert body["availableProviders"] == ["fake", "gemini"]
        # The stage list is the useful part: it makes the pipeline's shape
        # visible from outside, so "why did that scan cost money?" is
        # answerable without reading the configuration.
        assert body["pipelineStages"] == ["knowledge-cache", "fake"]

    def test_never_exposes_the_credential(self, client: TestClient) -> None:
        raw = client.get("/v1/health").text.lower()
        assert "api_key" not in raw
        assert "apikey" not in raw


class TestGarmentScan:
    def test_identifies_a_garment(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/garment",
            files=[("images", ("front.png", png_bytes(1), "image/png"))],
        )

        assert response.status_code == 200
        result = response.json()["result"]
        assert result["type"]["value"]
        assert 0.0 <= result["type"]["confidence"] <= 1.0
        assert result["type"]["source"] == "aiInference"

    def test_accepts_several_photographs(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/garment",
            files=[
                ("images", ("front.png", png_bytes(1), "image/png")),
                ("images", ("back.png", png_bytes(2), "image/png")),
            ],
        )
        assert response.status_code == 200

    def test_rejects_more_images_than_the_limit(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/garment",
            files=[("images", (f"{i}.png", png_bytes(i), "image/png")) for i in range(9)],
        )

        assert response.status_code == 413
        assert response.json()["error"] == "payload_too_large"


class TestCareTagScan:
    def test_reads_a_label(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/care-tag",
            files={"image": ("tag.png", png_bytes(4), "image/png")},
        )

        assert response.status_code == 200
        result = response.json()["result"]
        assert result["instructions"]["method"] == "machine"
        # A bar-less tub is a stated fact, and the scan must say so rather than
        # leaving every ordinary garment to inherit a gentle cycle.
        assert result["instructions"]["agitation"] == "normal"

    @staticmethod
    def _scan(client: TestClient, image: bytes) -> Any:
        return client.post(
            "/v1/scan/care-tag", files={"image": ("tag.png", image, "image/png")}
        ).json()

    def test_both_sides_of_a_label_are_read_as_one(self, client: TestClient) -> None:
        # Labels are routinely printed on both sides, or continue onto a second
        # tag sewn behind the first. Two photographs are two parts of one
        # label, and must come back as one answer rather than two.
        response = client.post(
            "/v1/scan/care-tag",
            files=[
                ("images", ("front.png", png_bytes(4), "image/png")),
                ("images", ("back.png", png_bytes(5), "image/png")),
            ],
        )

        assert response.status_code == 200
        assert response.json()["result"]["instructions"]["method"] == "machine"

    def test_the_single_photo_form_still_works(self, client: TestClient) -> None:
        # What every build shipped before two-sided labels sends. An app that
        # has not been updated should keep working rather than start answering
        # 422 to a request that was correct when it was written.
        response = client.post(
            "/v1/scan/care-tag",
            files={"image": ("tag.png", png_bytes(4), "image/png")},
        )

        assert response.status_code == 200

    def test_no_photograph_at_all_is_refused(self, client: TestClient) -> None:
        response = client.post("/v1/scan/care-tag", data={"brand": "Uniqlo"})

        assert response.status_code == 422

    def test_the_language_of_the_words_is_reported(self, client: TestClient) -> None:
        # The symbols are ISO 3758 and mean the same everywhere, so a foreign
        # label is readable — but the app needs to know it was reading one to
        # say so, and to show the wording it could not place.
        response = client.post(
            "/v1/scan/care-tag",
            files={"image": ("tag.png", png_bytes(4), "image/png")},
        )

        result = response.json()["result"]
        assert "language" in result
        assert len(result["language"]) == 2

    def test_a_repeat_scan_of_a_clean_read_is_served_from_memory(self, client: TestClient) -> None:
        image = find_image(complete=True)

        first = self._scan(client, image)
        second = self._scan(client, image)

        assert first["diagnostics"]["stagesRun"] == ["knowledge-cache", "fake"]
        assert second["diagnostics"]["servedFromCache"] is True
        # The expensive stage was never reached the second time.
        assert second["diagnostics"]["stagesRun"] == ["knowledge-cache"]
        assert second["result"] == first["result"]

    def test_an_incomplete_read_is_never_cached(self, client: TestClient) -> None:
        """Caching a poor scan would make it permanent.

        A reading that admits it could not decode part of the label must be
        re-attempted, so the user can fix it by taking a better photograph.
        """
        image = find_image(complete=False)

        self._scan(client, image)
        second = self._scan(client, image)

        assert second["diagnostics"]["servedFromCache"] is False
        assert second["diagnostics"]["stagesRun"] == ["knowledge-cache", "fake"]

    def test_a_different_image_is_not_served_from_memory(self, client: TestClient) -> None:
        client.post("/v1/scan/care-tag", files={"image": ("a.png", png_bytes(1), "image/png")})
        second = client.post(
            "/v1/scan/care-tag", files={"image": ("b.png", png_bytes(2), "image/png")}
        ).json()

        assert second["diagnostics"]["servedFromCache"] is False


class TestPileScan:
    def test_detects_several_garments(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/pile",
            files={"image": ("pile.png", png_bytes(5), "image/png")},
        )

        assert response.status_code == 200
        result = response.json()["result"]
        assert len(result["items"]) >= 2

        for item in result["items"]:
            box = item["boundingBox"]
            # Normalised coordinates, so they survive the image being resized
            # or re-encoded between the device and the provider.
            assert 0.0 <= box["left"] <= 1.0
            assert 0.0 <= box["top"] <= 1.0
            assert 0.0 < box["width"] <= 1.0

    def test_reports_garments_it_could_not_identify(self, client: TestClient) -> None:
        """Better to admit two items are buried than to guess at their shapes."""
        counts = []
        for seed in range(6):
            response = client.post(
                "/v1/scan/pile",
                files={"image": ("pile.png", png_bytes(seed), "image/png")},
            )
            counts.append(response.json()["result"].get("partiallyObscuredCount", 0))

        assert any(count > 0 for count in counts)


class TestUploadValidation:
    def test_rejects_an_empty_file(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/care-tag", files={"image": ("empty.png", b"", "image/png")}
        )

        assert response.status_code == 415
        assert "empty" in response.json()["detail"]

    def test_rejects_a_non_image(self, client: TestClient) -> None:
        response = client.post(
            "/v1/scan/care-tag",
            files={"image": ("notes.txt", b"just some text", "text/plain")},
        )

        assert response.status_code == 415
        body = response.json()
        assert body["error"] == "unsupported_media"
        # The message names what would have been accepted.
        assert "image/png" in body["detail"]

    def test_accepts_a_camera_capture_declared_as_octet_stream(self, client: TestClient) -> None:
        """Clients routinely mislabel a capture; the bytes are the truth."""
        response = client.post(
            "/v1/scan/care-tag",
            files={
                "image": ("capture", png_bytes(3), "application/octet-stream"),
            },
        )
        assert response.status_code == 200

    def test_rejects_an_oversized_image(self, client: TestClient) -> None:
        oversized = png_bytes(1) + b"\x00" * (9 * 1024 * 1024)
        response = client.post(
            "/v1/scan/care-tag", files={"image": ("big.png", oversized, "image/png")}
        )

        assert response.status_code == 413
        body = response.json()
        assert body["error"] == "payload_too_large"
        # The hint tells the user what to do about it.
        assert "resolution" in body["detail"].lower()


class TestErrorEnvelope:
    @pytest.mark.parametrize(
        ("path", "files"),
        [
            ("/v1/scan/care-tag", {"image": ("x.txt", b"nope", "text/plain")}),
            ("/v1/scan/pile", {"image": ("x.txt", b"nope", "text/plain")}),
        ],
    )
    def test_every_failure_uses_the_same_shape(
        self, client: TestClient, path: str, files: dict[str, object]
    ) -> None:
        body = client.post(path, files=files).json()

        assert set(body) <= {"error", "detail", "hint"}
        assert isinstance(body["error"], str)
        assert isinstance(body["detail"], str)
        assert body["detail"], "a failure must always explain itself"
