"""The learned remover, its fallback, and the shared edge rendering.

These use the bundled `u2netp` model (4.6 MB, no network) on synthetic photos
whose correct answer is known. A real photograph on a real carpet is still the
final judge, and the README says so.
"""

from __future__ import annotations

import io
import logging
import threading
import time

import numpy as np
import pytest
from PIL import Image

from app.api.v1.dependencies import get_background_remover, reset_wiring
from app.services.images.chain import FallbackRemover
from app.services.images.cutout import (
    BorderSampledRemover,
    Cutout,
    CutoutError,
    _label,
    decode_for_cutout,
)
from app.services.images.learned import MODEL_PATH, LearnedRemover, LearnedUnavailableError
from tests import garment_photos as photos


@pytest.fixture(scope="module")
def learned() -> LearnedRemover:
    return LearnedRemover()


def alpha_of(png: bytes) -> np.ndarray:
    image = Image.open(io.BytesIO(png))
    assert image.mode == "RGBA"
    return np.asarray(image.split()[-1])


def region_count(alpha: np.ndarray, *, min_share: float = 0.01) -> int:
    """Connected opaque regions bigger than `min_share` of the opaque area."""
    small = np.asarray(Image.fromarray(alpha).resize((120, 160))) > 127
    _, sizes = _label(small)
    total = sum(sizes.values())
    return sum(1 for size in sizes.values() if size >= total * min_share)


class TestTheBundledModel:
    def test_the_model_ships_inside_the_package(self) -> None:
        assert MODEL_PATH.is_file()
        assert MODEL_PATH.stat().st_size > 1_000_000


class TestSyntheticFailures:
    def test_a_garment_on_a_board_with_a_soft_shadow(self, learned: LearnedRemover) -> None:
        result = learned.remove(photos.on_board())

        alpha = alpha_of(result.png)
        assert result.is_plausible
        assert region_count(alpha) == 1
        assert photos.iou(alpha, photos.truth_mask()) > 0.95

    def test_the_shadow_costs_the_classical_remover_accuracy(self, learned: LearnedRemover) -> None:
        data = photos.on_board()
        truth = photos.truth_mask()

        ours = photos.iou(alpha_of(learned.remove(data).png), truth)
        theirs = photos.iou(alpha_of(BorderSampledRemover().remove(data).png), truth)

        assert ours > theirs

    def test_a_board_on_a_darker_textured_surround(self, learned: LearnedRemover) -> None:
        result = learned.remove(photos.board_on_carpet())

        alpha = alpha_of(result.png)
        assert result.is_plausible
        assert region_count(alpha) == 1
        assert photos.iou(alpha, photos.truth_mask()) > 0.95

    def test_the_classical_remover_also_copes_with_two_backgrounds(self) -> None:
        # Board along two edges, carpet along the others: the border is two
        # surfaces, and both must count as background.
        result = BorderSampledRemover().remove(photos.board_on_carpet())

        assert photos.iou(alpha_of(result.png), photos.truth_mask()) > 0.95

    def test_dark_trousers_beside_carpet(self, learned: LearnedRemover) -> None:
        result = learned.remove(photos.trousers_on_board())

        alpha = alpha_of(result.png)
        assert result.is_plausible
        assert photos.iou(alpha, photos.trousers_truth()) > 0.95


class TestEdgeDecontamination:
    @pytest.mark.parametrize("which", ["learned", "classical"])
    def test_no_pale_ring_on_a_dark_garment(self, which: str, learned: LearnedRemover) -> None:
        remover = learned if which == "learned" else BorderSampledRemover()
        result = remover.remove(photos.on_board(colour=(30, 36, 56)))

        image = np.asarray(Image.open(io.BytesIO(result.png)).convert("RGBA"), dtype=np.float64)
        alpha = image[..., 3]
        brightest = image[..., :3].max(axis=2)

        # Every pixel that is even faintly visible must be garment-coloured. The
        # board is ~244; a fringe would be pixels well above the garment's ~60.
        visible = alpha > 20
        assert visible.sum() > 1000
        assert brightest[visible].max() < 140

    def test_the_result_composites_on_a_dark_tile_without_a_halo(
        self, learned: LearnedRemover
    ) -> None:
        result = learned.remove(photos.on_board(colour=(30, 36, 56)))
        image = Image.open(io.BytesIO(result.png)).convert("RGBA")
        tile = Image.new("RGBA", image.size, (14, 20, 30, 255))
        tile.alpha_composite(image)

        outline = photos.truth_mask()
        pixels = np.asarray(tile.convert("L"), dtype=np.float64)
        # A ring of pixels within a few pixels of the true outline.
        shifted = [np.roll(outline, s, axis=a) for a in (0, 1) for s in (-3, 3)]
        ring = np.any(shifted, axis=0) & ~np.all(shifted, axis=0)
        assert pixels[ring].max() < 120


class TestMemoryDiscipline:
    def test_a_large_jpeg_is_decoded_at_the_size_it_is_returned_at(self) -> None:
        buffer = io.BytesIO()
        Image.new("RGB", (4000, 3000), (240, 240, 240)).save(buffer, format="JPEG")

        rgb = decode_for_cutout(buffer.getvalue())

        assert rgb.size == (768, 576)

    def test_inference_never_runs_twice_at_once(self) -> None:
        remover = LearnedRemover()
        running = 0
        peak = 0
        gate = threading.Lock()

        def slow_infer(rgb: Image.Image) -> np.ndarray:
            nonlocal running, peak
            with gate:
                running += 1
                peak = max(peak, running)
            time.sleep(0.15)
            with gate:
                running -= 1
            probability = np.zeros((320, 320), dtype=np.float32)
            probability[80:240, 80:240] = 1.0
            return probability

        remover._infer = slow_infer  # type: ignore[method-assign]
        data = photos.on_board()
        threads = [threading.Thread(target=remover.remove, args=(data,)) for _ in range(3)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        assert peak == 1


class FixedRemover:
    def __init__(self, coverage: float, *, fail: Exception | None = None) -> None:
        self.coverage = coverage
        self.fail = fail
        self.calls = 0

    def remove(self, image_bytes: bytes) -> Cutout:
        self.calls += 1
        if self.fail is not None:
            raise self.fail
        return Cutout(png=b"png", coverage=self.coverage, width=1, height=1)


class TestFallback:
    def test_a_missing_model_is_unavailable_not_a_crash(self, tmp_path) -> None:
        remover = LearnedRemover(model_path=tmp_path / "missing.onnx")

        with pytest.raises(LearnedUnavailableError):
            remover.remove(photos.on_board())

    def test_a_missing_model_falls_back_to_the_classical_remover(self, tmp_path) -> None:
        chain = FallbackRemover(
            LearnedRemover(model_path=tmp_path / "missing.onnx"), BorderSampledRemover()
        )

        result = chain.remove(photos.on_board())

        assert result.is_plausible
        assert photos.iou(alpha_of(result.png), photos.truth_mask()) > 0.9

    def test_an_inference_error_falls_back(self) -> None:
        primary = FixedRemover(0.5, fail=RuntimeError("onnx exploded"))
        fallback = FixedRemover(0.4)

        result = FallbackRemover(primary, fallback).remove(b"x")

        assert result.coverage == 0.4

    def test_the_reason_is_logged_once(self, caplog: pytest.LogCaptureFixture) -> None:
        chain = FallbackRemover(FixedRemover(0.5, fail=RuntimeError("no model")), FixedRemover(0.4))

        with caplog.at_level(logging.WARNING):
            for _ in range(3):
                chain.remove(b"x")

        assert len([r for r in caplog.records if "no model" in r.getMessage()]) == 1

    @pytest.mark.parametrize("coverage", [0.0, 0.01, 0.97])
    def test_an_implausible_learned_mask_tries_the_classical_one(self, coverage: float) -> None:
        primary = FixedRemover(coverage)
        fallback = FixedRemover(0.4)

        assert FallbackRemover(primary, fallback).remove(b"x").coverage == 0.4
        assert fallback.calls == 1

    def test_when_both_are_implausible_the_nearer_one_is_returned(self) -> None:
        chain = FallbackRemover(FixedRemover(0.99), FixedRemover(0.50 + 0.5))

        assert chain.remove(b"x").coverage == 0.99

        chain = FallbackRemover(FixedRemover(0.0), FixedRemover(0.03))
        assert chain.remove(b"x").coverage == 0.03

    def test_a_plausible_answer_never_wakes_the_fallback(self) -> None:
        fallback = FixedRemover(0.4)

        FallbackRemover(FixedRemover(0.5), fallback).remove(b"x")

        assert fallback.calls == 0

    def test_an_undecodable_image_is_still_the_callers_error(self) -> None:
        chain = FallbackRemover(LearnedRemover(), BorderSampledRemover())

        with pytest.raises(CutoutError):
            chain.remove(b"not an image")

    def test_the_learned_mask_failing_and_the_classical_failing_raises(self) -> None:
        primary = FixedRemover(0.5, fail=CutoutError("nothing salient"))
        fallback = FixedRemover(0.5, fail=CutoutError("nothing either"))

        with pytest.raises(CutoutError, match="nothing salient"):
            FallbackRemover(primary, fallback).remove(b"x")


class TestSelection:
    def test_learned_is_the_default_and_wrapped_in_a_fallback(self) -> None:
        reset_wiring()
        assert isinstance(get_background_remover(), FallbackRemover)
        reset_wiring()

    def test_the_switch_selects_the_classical_remover(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("CUTOUT_REMOVER", "classical")
        reset_wiring()

        assert isinstance(get_background_remover(), BorderSampledRemover)
        reset_wiring()
