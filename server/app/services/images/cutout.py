"""Removing the background from a garment photograph.

## Why this is classical rather than a model

The app already tells the user to "lay it flat against a plain background",
because that is also what makes the garment easiest to *identify*. Given that
instruction, the hard part of matting — separating a subject from a cluttered
scene — does not arise, and the remaining problem is well handled by measuring
how far each pixel sits from the colour the borders are made of.

A learned matting model would be better on hair, lace and fringing, and it is
the obvious upgrade. It is not the starting point, because it would cost a
~170 MB download at first run and break the property that this service starts
and passes its whole suite with no network and no credentials.

`BackgroundRemover` is therefore an interface with one implementation and a
documented seam, in the same shape as `VisionProvider`: a learned remover slots
in beside this one without any caller changing.

## What it does

1. Sample the border to build a model of the background colour. Real photos
   have gradients and shadow, so the border is clustered rather than averaged —
   one mean over a background that is white at the top and grey at the bottom
   describes neither.
2. Score every pixel by its distance to the nearest background cluster, in
   CIELAB so the distance is perceptual rather than a raw RGB difference.
3. Threshold, keep the largest connected region, fill its holes.
4. Feather the edge, so the result composites without a hard jagged line.
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from typing import Protocol

import numpy as np
from PIL import Image, ImageFilter

# Photographs come in far larger than anything a wardrobe list needs, and the
# segmentation cost is quadratic in edge length. Everything below runs on a
# downscaled copy; only the final alpha is resized back.
_WORK_EDGE = 512

# How wide a border strip counts as "definitely background", as a fraction of
# the shorter edge. Narrow enough to exclude a garment that fills the frame,
# wide enough to survive a slightly off-centre shot.
_BORDER_FRACTION = 0.06

# Background colour clusters. More than one because a real backdrop is lit
# unevenly; more than a handful just fits noise.
_BACKGROUND_CLUSTERS = 4


class CutoutError(Exception):
    """The image could not be separated from its background."""


@dataclass(frozen=True, slots=True)
class Cutout:
    """A background-removed image."""

    png: bytes
    """RGBA PNG bytes."""

    coverage: float
    """Fraction of the frame the subject occupies, 0..1.

    Reported so a caller can refuse an implausible result rather than storing
    it. A cutout covering 98% of the frame means the background was never
    found; one covering 1% means the garment was.
    """

    width: int
    height: int

    @property
    def is_plausible(self) -> bool:
        """Whether this looks like a garment rather than a failed separation.

        A garment photographed to fill the frame lands somewhere in the middle
        of this range. Outside it, showing the user a "cutout" that is really
        the whole photograph — or a scrap of one — is worse than showing them
        nothing, because it looks like the feature works.
        """
        return 0.04 <= self.coverage <= 0.92


class BackgroundRemover(Protocol):
    """Separates a subject from its background."""

    def remove(self, image_bytes: bytes) -> Cutout: ...


class BorderSampledRemover:
    """Segments by distance from the colours found at the frame's border."""

    def remove(self, image_bytes: bytes) -> Cutout:
        try:
            source = Image.open(io.BytesIO(image_bytes))
            source.load()
        except Exception as error:  # Pillow raises a wide variety here.
            raise CutoutError("the image could not be decoded") from error

        rgb = source.convert("RGB")
        full_size = rgb.size

        work = rgb.copy()
        work.thumbnail((_WORK_EDGE, _WORK_EDGE), Image.Resampling.LANCZOS)

        lab = _to_lab(np.asarray(work, dtype=np.float64) / 255.0)
        distance = _distance_from_background(lab)
        mask = _largest_region(distance > _threshold(distance))

        coverage = float(mask.mean())

        alpha = Image.fromarray((mask * 255).astype(np.uint8), mode="L")
        # Feathering before the upscale, so the blur is in working-resolution
        # pixels and the edge stays proportionate whatever the source size.
        alpha = alpha.filter(ImageFilter.GaussianBlur(radius=1.2))
        alpha = alpha.resize(full_size, Image.Resampling.BILINEAR)

        cut = rgb.convert("RGBA")
        cut.putalpha(alpha)

        buffer = io.BytesIO()
        cut.save(buffer, format="PNG", optimize=True)

        return Cutout(
            png=buffer.getvalue(),
            coverage=coverage,
            width=full_size[0],
            height=full_size[1],
        )


def _to_lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB in 0..1 to CIELAB (D65).

    The same conversion the Dart core does, for the same reason: a Euclidean
    distance in RGB says a dark navy and a dark brown are far apart while
    calling two obviously different mid-greys close. In Lab the distance
    roughly matches what a person would say.
    """
    linear = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)

    r, g, b = linear[..., 0], linear[..., 1], linear[..., 2]
    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

    xn, yn, zn = 0.95047, 1.0, 1.08883
    delta = 6.0 / 29.0

    def f(t: np.ndarray) -> np.ndarray:
        return np.where(
            t > delta**3,
            np.cbrt(np.clip(t, 0.0, None)),
            t / (3 * delta**2) + 4.0 / 29.0,
        )

    fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
    return np.stack([116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)], axis=-1)


def _border_pixels(lab: np.ndarray) -> np.ndarray:
    """The Lab values around the edge of the frame."""
    height, width = lab.shape[:2]
    band = max(2, int(min(height, width) * _BORDER_FRACTION))

    strips = [
        lab[:band, :, :].reshape(-1, 3),
        lab[-band:, :, :].reshape(-1, 3),
        lab[:, :band, :].reshape(-1, 3),
        lab[:, -band:, :].reshape(-1, 3),
    ]
    return np.concatenate(strips, axis=0)


def _background_clusters(border: np.ndarray) -> np.ndarray:
    """A few representative background colours, by k-means on the border.

    Clustered rather than averaged because a backdrop lit from one side is two
    colours, and their mean is a third that appears nowhere in the picture —
    which makes both real ones look like foreground.
    """
    rng = np.random.default_rng(0)  # Deterministic: same photo, same cutout.
    k = min(_BACKGROUND_CLUSTERS, len(border))
    centres = border[rng.choice(len(border), size=k, replace=False)]

    for _ in range(12):
        distances = np.linalg.norm(border[:, None, :] - centres[None, :, :], axis=2)
        assignment = distances.argmin(axis=1)

        moved = np.stack(
            [
                border[assignment == i].mean(axis=0) if np.any(assignment == i) else centres[i]
                for i in range(k)
            ]
        )
        if np.allclose(moved, centres, atol=0.1):
            centres = moved
            break
        centres = moved

    return centres


def _distance_from_background(lab: np.ndarray) -> np.ndarray:
    """Per-pixel distance to the nearest background colour."""
    centres = _background_clusters(_border_pixels(lab))
    flat = lab.reshape(-1, 1, 3)
    distances = np.linalg.norm(flat - centres[None, :, :], axis=2).min(axis=1)
    reshaped: np.ndarray = distances.reshape(lab.shape[:2])
    return reshaped


def _threshold(distance: np.ndarray) -> float:
    """Otsu's threshold over the distance map.

    Otsu rather than a fixed number because "far from the background" is
    relative: a white shirt on a cream sheet and a black coat on white differ
    by an order of magnitude, and any constant would fail one of them.
    """
    finite = distance[np.isfinite(distance)]
    if finite.size == 0:
        raise CutoutError("the image has no measurable content")

    counts, edges = np.histogram(finite, bins=256)
    centres = (edges[:-1] + edges[1:]) / 2
    weight = counts.cumsum()
    total = weight[-1]
    if total == 0:
        raise CutoutError("the image has no measurable content")

    weight_below = weight / total
    weight_above = 1.0 - weight_below

    cumulative_mean = (counts * centres).cumsum()
    grand_mean = cumulative_mean[-1] / total

    with np.errstate(divide="ignore", invalid="ignore"):
        mean_below = cumulative_mean / weight
        mean_above = (cumulative_mean[-1] - cumulative_mean) / (total - weight)
        between = weight_below * weight_above * (mean_below - mean_above) ** 2

    between = np.nan_to_num(between, nan=0.0, posinf=0.0, neginf=0.0)
    if not np.any(between > 0):
        # A single-colour image: everything is background, and saying so is
        # more useful than returning an arbitrary split.
        return float(grand_mean + 1e9)

    return float(centres[int(between.argmax())])


def _largest_region(mask: np.ndarray) -> np.ndarray:
    """The biggest connected blob in [mask], with its holes filled.

    A garment is one object. Keeping only the largest region discards the
    speckle that any threshold leaves behind, and filling holes recovers the
    parts of the garment that happen to match the backdrop — a white button on
    a white sheet is still part of the shirt.
    """
    labels, sizes = _label(mask)
    if not sizes:
        raise CutoutError("no subject could be separated from the background")

    largest = max(sizes, key=lambda label: sizes[label])
    subject = labels == largest

    # Holes are background regions that do not touch the frame edge.
    holes, hole_sizes = _label(~subject)
    for label in hole_sizes:
        touching = (
            np.any(holes[0, :] == label)
            or np.any(holes[-1, :] == label)
            or np.any(holes[:, 0] == label)
            or np.any(holes[:, -1] == label)
        )
        if not touching:
            subject |= holes == label

    filled: np.ndarray = subject
    return filled


def _label(mask: np.ndarray) -> tuple[np.ndarray, dict[int, int]]:
    """Four-connected component labelling.

    Written out rather than pulled from SciPy: this is the only thing that
    would have been needed from it, and a 90 MB dependency for one function is
    a poor trade in a service that is otherwise numpy and Pillow.
    """
    height, width = mask.shape
    labels = np.zeros((height, width), dtype=np.int32)
    sizes: dict[int, int] = {}
    next_label = 0

    # Iterative flood fill. Recursion would overflow the stack on a large
    # region long before it ran out of memory.
    for start_y in range(height):
        for start_x in range(width):
            if not mask[start_y, start_x] or labels[start_y, start_x]:
                continue

            next_label += 1
            stack = [(start_y, start_x)]
            labels[start_y, start_x] = next_label
            size = 0

            while stack:
                y, x = stack.pop()
                size += 1
                for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                    if 0 <= ny < height and 0 <= nx < width and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = next_label
                        stack.append((ny, nx))

            sizes[next_label] = size

    return labels, sizes
