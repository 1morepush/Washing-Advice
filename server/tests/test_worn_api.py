"""The worn-photo endpoint and the service behind it, with the fake and with scripted scanners."""

from __future__ import annotations

import base64
import io
from typing import Any

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.api.v1.dependencies import get_worn_scanner
from app.main import create_app
from app.schemas.common import Confident
from app.schemas.scan import CutoutKind, GarmentScanResult
from app.schemas.wardrobe import ItemType
from app.services.ai.base import ProviderError, ScanImage
from app.services.worn.base import RawDetection
from app.services.worn.cutting import NormalisedBox, PhotoError
from app.services.worn.fake import FakeWornScanner
from app.services.worn.service import MAX_DETECTIONS, cut_detections, scan_worn
from tests.conftest import photo_bytes, png_bytes
from tests.test_worn_cutting import TestOrientation


def post(client: TestClient, data: bytes, *, mime: str = "image/png") -> Any:
    return client.post("/v1/scan/worn", files={"image": ("worn.png", data, mime)})


def decode(cutout: str) -> Image.Image:
    image = Image.open(io.BytesIO(base64.b64decode(cutout)))
    assert image.mode == "RGBA"
    return image


def garment(item_type: ItemType = ItemType.T_SHIRT) -> GarmentScanResult:
    return GarmentScanResult(type=Confident[ItemType](value=item_type, confidence=0.9))


def raw(
    box: NormalisedBox | None = None, confidence: float = 0.9, mask: str | None = None
) -> RawDetection:
    return RawDetection(
        scan=garment(),
        box=box or NormalisedBox(0.2, 0.2, 0.6, 0.6),
        detection_confidence=confidence,
        mask=mask,
    )


class TestTheEndpoint:
    def test_finds_garments_and_cuts_each_one_out(self, client: TestClient) -> None:
        response = post(client, photo_bytes(3))

        assert response.status_code == 200
        body = response.json()
        detections = body["result"]["detections"]
        assert 2 <= len(detections) <= 3
        for detection in detections:
            box = detection["boundingBox"]
            assert 0 <= box["left"] and 0 < box["width"] and box["left"] + box["width"] <= 1.0001
            assert detection["cutoutKind"] in {"outline", "box"}
            assert decode(detection["cutout"]).width > 0
        assert body["diagnostics"]["stagesRun"] == ["fake"]
        assert body["diagnostics"]["stageAnswered"] == "fake"

    def test_no_field_is_ever_explicitly_null(self, client: TestClient) -> None:
        def nulls(value: Any, path: str = "$") -> list[str]:
            if value is None:
                return [path]
            if isinstance(value, dict):
                return [n for k, v in value.items() for n in nulls(v, f"{path}.{k}")]
            if isinstance(value, list):
                return [n for i, v in enumerate(value) for n in nulls(v, f"{path}[{i}]")]
            return []

        for seed in range(6):
            assert nulls(post(client, photo_bytes(seed)).json()) == []

    def test_a_one_pixel_photograph_finds_nothing_and_says_so(self, client: TestClient) -> None:
        # Every box on one pixel is nothing: an empty list, not an error.
        response = post(client, png_bytes(1))

        assert response.status_code == 200
        assert response.json()["result"]["detections"] == []

    def test_a_photograph_the_server_cannot_open_is_a_422(self, client: TestClient) -> None:
        # Passes the magic-byte check, then fails to decode.
        response = post(client, b"\xff\xd8\xff" + b"\x00" * 64, mime="image/jpeg")

        assert response.status_code == 422
        assert response.json()["error"] == "scan_failed"
        assert "JPEG or PNG" in response.json()["hint"]

    def test_an_exif_rotated_photograph_is_cut_upright(self, client: TestClient) -> None:
        upright = TestOrientation.upright_scene()
        data = TestOrientation.sideways_jpeg(6, upright)

        scanner = _Recording([raw(NormalisedBox(0.0, 0.0, 0.4, 0.375))])
        app = create_app()
        app.dependency_overrides[get_worn_scanner] = lambda: scanner
        with TestClient(app) as scripted:
            response = post(scripted, data, mime="image/jpeg")

        assert response.status_code == 200
        # The model was shown the upright picture...
        assert scanner.seen is not None
        assert Image.open(io.BytesIO(scanner.seen.data)).size == (100, 160)
        # ...and the red block, at the top left of it, is what was cut.
        cutout = decode(response.json()["result"]["detections"][0]["cutout"])
        r, g, b, _ = cutout.getpixel((cutout.width // 2, cutout.height // 2))
        assert r > 200 and g < 60 and b < 60


class TestLimitsAndBadInputAreThePileScans:
    def test_rejects_an_empty_file(self, client: TestClient) -> None:
        response = post(client, b"")
        assert response.status_code == 415
        assert "empty" in response.json()["detail"]

    def test_rejects_a_non_image(self, client: TestClient) -> None:
        response = post(client, b"just some text", mime="text/plain")
        assert response.status_code == 415
        assert response.json()["error"] == "unsupported_media"
        assert "image/png" in response.json()["detail"]

    def test_rejects_an_oversized_image(self, client: TestClient) -> None:
        response = post(client, png_bytes(1) + b"\x00" * (9 * 1024 * 1024))
        assert response.status_code == 413
        assert response.json()["error"] == "payload_too_large"
        assert "resolution" in response.json()["detail"].lower()

    def test_accepts_a_capture_declared_as_octet_stream(self, client: TestClient) -> None:
        response = post(client, photo_bytes(2), mime="application/octet-stream")
        assert response.status_code == 200

    def test_a_missing_image_is_a_validation_error(self, client: TestClient) -> None:
        response = client.post("/v1/scan/worn")
        assert response.status_code in (400, 422)
        assert set(response.json()) <= {"error", "detail", "hint"}

    def test_failures_use_the_common_envelope(self, client: TestClient) -> None:
        body = post(client, b"nope", mime="text/plain").json()
        assert set(body) <= {"error", "detail", "hint"} and body["detail"]


class TestProviderFailures:
    @staticmethod
    def failing(error: ProviderError) -> TestClient:
        class Failing:
            name = "gemini"

            async def read(self, image: ScanImage) -> list[RawDetection]:
                raise error

        app = create_app()
        app.dependency_overrides[get_worn_scanner] = lambda: Failing()
        return TestClient(app)

    def test_a_rate_limit_is_a_429_with_the_wait(self) -> None:
        with self.failing(ProviderError("gemini", "rate limited", retry_after=42)) as client:
            response = post(client, photo_bytes())

        assert response.status_code == 429
        assert response.headers["retry-after"] == "42"
        assert response.json()["error"] == "rate_limited"

    def test_any_other_failure_is_a_503(self) -> None:
        with self.failing(ProviderError("gemini", "HTTP 500 from the Gemini API")) as client:
            response = post(client, photo_bytes())

        assert response.status_code == 503
        assert response.json()["error"] == "provider_unavailable"

    def test_gemini_without_a_key_is_a_503_that_says_what_to_set(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("VISION_PROVIDER", "gemini")
        monkeypatch.setenv("GEMINI_API_KEY", "")

        with TestClient(create_app()) as client:
            response = post(client, photo_bytes())

        assert response.status_code == 503
        assert "GEMINI_API_KEY" in response.json()["hint"]


class _Recording:
    name = "scripted"

    def __init__(self, found: list[RawDetection]) -> None:
        self._found = found
        self.seen: ScanImage | None = None

    async def read(self, image: ScanImage) -> list[RawDetection]:
        self.seen = image
        return self._found


class TestTheService:
    async def test_drops_nonsense_boxes_and_keeps_the_rest(self) -> None:
        scanner = _Recording(
            [
                raw(NormalisedBox(0.3, 0.3, 0.3, 0.6)),
                raw(NormalisedBox(1.2, 0.1, 1.5, 0.5)),
                raw(NormalisedBox(0.1, 0.1, 0.5, 0.5)),
            ]
        )

        result = await scan_worn(ScanImage(photo_bytes(), "image/png"), scanner)

        assert result.count == 1

    async def test_a_bad_mask_keeps_the_detection_as_a_box(self) -> None:
        scanner = _Recording([raw(mask="garbage")])

        result = await scan_worn(ScanImage(photo_bytes(), "image/png"), scanner)

        assert [d.cutout_kind for d in result.detections] == [CutoutKind.BOX]
        assert result.detections[0].cutout is not None

    async def test_is_capped_keeping_the_most_certain_in_the_models_order(self) -> None:
        found = [raw(confidence=0.5 + i / 100) for i in range(MAX_DETECTIONS + 3)]
        # The three least certain are the first three.
        result = await scan_worn(ScanImage(photo_bytes(), "image/png"), _Recording(found))

        assert result.count == MAX_DETECTIONS
        confidences = [d.detection_confidence for d in result.detections]
        assert confidences == sorted(confidences)
        assert min(confidences) == pytest.approx(0.53)

    async def test_a_nonsense_box_does_not_use_up_a_place_in_the_cap(self) -> None:
        found = [raw(NormalisedBox(0.5, 0.5, 0.5, 0.5), confidence=1.0) for _ in range(5)]
        found += [raw() for _ in range(MAX_DETECTIONS)]

        result = await scan_worn(ScanImage(photo_bytes(), "image/png"), _Recording(found))

        assert result.count == MAX_DETECTIONS

    async def test_an_unopenable_photograph_is_a_photo_error_and_the_scanner_is_not_asked(
        self,
    ) -> None:
        scanner = _Recording([raw()])

        with pytest.raises(PhotoError):
            await scan_worn(ScanImage(b"not an image", "image/png"), scanner)

        assert scanner.seen is None

    async def test_the_boxes_in_the_result_are_the_clamped_ones(self) -> None:
        scanner = _Recording([raw(NormalisedBox(0.5, 0.5, 1.5, 1.5))])

        result = await scan_worn(ScanImage(photo_bytes(), "image/png"), scanner)

        box = result.detections[0].bounding_box
        assert box.left + box.width == pytest.approx(1.0)

    def test_cut_detections_needs_no_event_loop(self) -> None:
        image = Image.open(io.BytesIO(photo_bytes())).convert("RGB")
        assert cut_detections(image, [raw()]).count == 1


class TestTheFake:
    async def test_is_deterministic(self) -> None:
        image = ScanImage(photo_bytes(4), "image/png")
        first = await FakeWornScanner().read(image)
        second = await FakeWornScanner().read(image)

        assert first == second

    async def test_finds_two_or_three_pieces_with_real_masks(self) -> None:
        counts: set[int] = set()
        for seed in range(12):
            found = await FakeWornScanner().read(ScanImage(photo_bytes(seed), "image/png"))
            counts.add(len(found))
            assert found[0].mask is not None and found[0].mask.startswith("data:image/png;base64,")

        assert counts == {2, 3}

    async def test_sometimes_leaves_the_last_mask_off(self) -> None:
        masks_missing = 0
        for seed in range(12):
            found = await FakeWornScanner().read(ScanImage(photo_bytes(seed), "image/png"))
            masks_missing += found[-1].mask is None

        assert 0 < masks_missing < 12

    async def test_the_shoes_are_two_regions_and_both_survive(self) -> None:
        for seed in range(40):
            image = ScanImage(photo_bytes(seed, (300, 400)), "image/png")
            found = await FakeWornScanner().read(image)
            if len(found) == 3 and found[-1].mask is not None:
                break
        else:
            pytest.fail("no seed produced shoes with a mask")

        result = cut_detections(Image.open(io.BytesIO(image.data)).convert("RGB"), found)
        shoes = result.detections[-1]
        alpha = decode(shoes.cutout or "").split()[-1]

        assert shoes.cutout_kind is CutoutKind.OUTLINE
        row = alpha.height // 2
        assert alpha.getpixel((alpha.width // 4, row)) == 255
        assert alpha.getpixel((alpha.width // 2, row)) == 0
        assert alpha.getpixel((3 * alpha.width // 4, row)) == 255

    async def test_is_selected_by_the_vision_provider_switch(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("VISION_PROVIDER", "fake")
        assert get_worn_scanner().name == "fake"
