"""The learned background remover: `u2netp` through ONNX Runtime.

See ADR 0010 for why this model and what it costs. The short version of the
constraints this file is written under:

* **Memory is the budget.** Render's free plan has 512 MB. So there is one
  session, loaded lazily, with ONNX Runtime's arena and memory pattern turned
  off; one inference at a time behind a lock; the photograph is decoded at the
  size it will be returned at rather than the size it arrived at; and the
  model sees 320x320.
* **Never the reason a request fails.** Anything that goes wrong here that is
  not the caller's fault (no model file, no onnxruntime, an inference error)
  raises [LearnedUnavailableError], and the fallback in `chain.py` answers with
  the classical remover instead.
"""

from __future__ import annotations

import ctypes
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

from app.services.images.cutout import (
    Cutout,
    CutoutError,
    _label,
    box_mean,
    decode_for_cutout,
    render_cutout,
)

MODEL_PATH = Path(__file__).parent / "models" / "u2netp.onnx"

# What the network was trained at. Fixed, not a tuning knob.
_INPUT_EDGE = 320  # the exported graph has a fixed 320x320 input
_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

# A model that finds nothing salient still returns *something*, and min-max
# normalising it would stretch noise to fill 0..1. If the raw answer never
# gets decisive, there is no subject to cut out.
_MIN_RAW_RANGE = 0.35

# Guided-filter radius as a fraction of the longer edge, and its regulariser.
_GUIDE_RADIUS_FRACTION = 0.012
_GUIDE_EPS = 2e-3

# Regions smaller than this fraction of the largest are specks; larger ones are
# kept, because a pair of socks is two garments' worth of pixels in one photo.
_KEEP_REGION_FRACTION = 0.10
# Holes up to this fraction of the subject are filled (a button, a print the
# model saw through); larger ones are real gaps.
_FILL_HOLE_FRACTION = 0.03
# Region and hole analysis runs on a copy this small, because the pure-Python
# labeller is linear in pixels and the answer does not need more.
_ANALYSIS_EDGE = 160


class LearnedUnavailableError(Exception):
    """The model could not be loaded or run, for a reason that is not the photo's."""


class LearnedRemover:
    """Cuts a garment out with a small salient-object network."""

    def __init__(self, model_path: Path = MODEL_PATH) -> None:
        self._model_path = model_path
        self._session: Any = None
        self._input_name = ""
        # One inference at a time, whole `remove` call included, so that the
        # working set of exactly one photograph exists at once.
        self._lock = threading.Lock()
        # And always on the same thread. glibc gives every thread its own heap
        # arena, and numpy/ONNX buffers freed into an arena other threads never
        # allocate from are not reused: measured, requests served by a rotating
        # pool of threads pushed the peak ~65 MB higher than the same requests
        # served by one.
        self._worker = ThreadPoolExecutor(max_workers=1, thread_name_prefix="cutout")

    def remove(self, image_bytes: bytes) -> Cutout:
        return self._worker.submit(self._remove, image_bytes).result()

    def _remove(self, image_bytes: bytes) -> Cutout:
        with self._lock:
            rgb = decode_for_cutout(image_bytes)
            probability = self._infer(rgb)
            mask = _refine(rgb, probability)
            cutout = render_cutout(rgb, mask)
            del rgb, probability, mask
            _release_freed_memory()
            return cutout

    # --- model ------------------------------------------------------------

    def _load(self) -> Any:
        if self._session is not None:
            return self._session
        try:
            import onnxruntime as ort

            options = ort.SessionOptions()
            options.intra_op_num_threads = 1
            options.inter_op_num_threads = 1
            # The two settings that keep the footprint down: the arena would
            # hold on to its high-water mark for the life of the process.
            options.enable_cpu_mem_arena = False
            options.enable_mem_pattern = False
            session = ort.InferenceSession(
                str(self._model_path), options, providers=["CPUExecutionProvider"]
            )
        except Exception as error:  # ImportError, a missing or corrupt file, ...
            raise LearnedUnavailableError(
                f"the cutout model could not be loaded: {error}"
            ) from error
        self._session = session
        self._input_name = session.get_inputs()[0].name
        return session

    def _infer(self, rgb: Image.Image) -> np.ndarray:
        """The model's soft 0..1 mask at 320x320."""
        session = self._load()

        small = rgb.resize((_INPUT_EDGE, _INPUT_EDGE), Image.Resampling.LANCZOS)
        scaled = (np.asarray(small, dtype=np.float32) / 255.0 - _MEAN) / _STD
        batch = np.ascontiguousarray(scaled.transpose(2, 0, 1)[None], dtype=np.float32)

        try:
            output = session.run(None, {self._input_name: batch})[0]
        except Exception as error:
            raise LearnedUnavailableError(f"the cutout model failed: {error}") from error

        raw = np.asarray(output[0, 0], dtype=np.float32)
        low, high = float(raw.min()), float(raw.max())
        if high - low < _MIN_RAW_RANGE:
            raise CutoutError("no subject could be separated from the background")
        normalised: np.ndarray = (raw - low) / (high - low)
        return normalised


def _refine(rgb: Image.Image, probability: np.ndarray) -> np.ndarray:
    """From the model's blurry 320x320 mask to a boolean mask on the photograph.

    The network's outline is right to within a few pixels at 320, which is
    several at the size that is returned, and soft. A guided filter (He et al.)
    pulls it onto the edges the photograph itself has: within a window it fits
    the mask as a linear function of the image's brightness, so the mask
    follows a real garment edge and ignores a texture that is not one.
    """
    width, height = rgb.size
    soft = np.asarray(
        Image.fromarray(probability, mode="F").resize((width, height), Image.Resampling.BICUBIC),
        dtype=np.float32,
    )
    soft = np.clip(soft, 0.0, 1.0)

    guide = np.asarray(rgb.convert("L"), dtype=np.float32) / 255.0
    radius = max(2, round(max(width, height) * _GUIDE_RADIUS_FRACTION))

    mean_guide = box_mean(guide, radius)
    mean_soft = box_mean(soft, radius)
    covariance = box_mean(guide * soft, radius) - mean_guide * mean_soft
    variance = box_mean(guide * guide, radius) - mean_guide * mean_guide
    slope = covariance / (variance + _GUIDE_EPS)
    offset = mean_soft - slope * mean_guide
    refined = box_mean(slope, radius) * guide + box_mean(offset, radius)

    mask: np.ndarray = refined >= 0.5
    return _tidy(mask)


def _tidy(mask: np.ndarray) -> np.ndarray:
    """Keeps the significant regions and fills small holes.

    Analysed on a small copy and applied back at full size: which regions
    matter is a coarse question, and the full-size mask keeps its own edge
    because it is only ever ANDed with (regions) or ORed with (holes) the
    coarse answer.
    """
    height, width = mask.shape
    scale = _ANALYSIS_EDGE / max(height, width)
    if scale >= 1.0:
        small = mask
        small_size = (width, height)
    else:
        small_size = (max(1, round(width * scale)), max(1, round(height * scale)))
        small = (
            np.asarray(
                Image.fromarray((mask * 255).astype(np.uint8), mode="L").resize(
                    small_size, Image.Resampling.BILINEAR
                )
            )
            >= 128
        )

    labels, sizes = _label(small)
    if not sizes:
        raise CutoutError("no subject could be separated from the background")
    biggest = max(sizes.values())
    keep_labels = [lab for lab, size in sizes.items() if size >= biggest * _KEEP_REGION_FRACTION]
    keep_small = np.isin(labels, keep_labels)

    # Holes: background regions of the kept subject that do not touch the frame.
    hole_labels, hole_sizes = _label(~keep_small)
    subject_area = int(keep_small.sum())
    holes_small = np.zeros_like(keep_small)
    for lab, size in hole_sizes.items():
        touches = (
            np.any(hole_labels[0, :] == lab)
            or np.any(hole_labels[-1, :] == lab)
            or np.any(hole_labels[:, 0] == lab)
            or np.any(hole_labels[:, -1] == lab)
        )
        if not touches and size <= subject_area * _FILL_HOLE_FRACTION:
            holes_small |= hole_labels == lab

    def up(small_mask: np.ndarray) -> np.ndarray:
        if small_mask.shape == mask.shape:
            return small_mask
        image = Image.fromarray((small_mask * 255).astype(np.uint8), mode="L")
        # Slightly generous: a one-cell border of slack so the full-size edge,
        # not the coarse one, decides where the outline falls.
        grown = image.resize((width, height), Image.Resampling.BILINEAR)
        result: np.ndarray = np.asarray(grown) >= 32
        return result

    result: np.ndarray = (mask & up(keep_small)) | up(holes_small)
    return result


def _release_freed_memory() -> None:
    """Hands freed heap back to the OS where glibc lets us.

    Python's allocator and numpy's leave freed pages in the process, so the
    resident size after an inference stays near its high-water mark. On glibc,
    `malloc_trim` returns them. A no-op elsewhere.
    """
    try:
        ctypes.CDLL("libc.so.6").malloc_trim(0)
    except (OSError, AttributeError):
        pass
