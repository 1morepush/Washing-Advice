"""Removing the background from a garment photograph.

## Two removers behind one seam

`BackgroundRemover` is an interface with two implementations:

* `LearnedRemover` (`learned.py`) runs the 4.6 MB `u2netp` salient-object
  model, bundled in this package, and is the default. It copes with what the
  owner's real photographs actually look like: a garment on a white board on a
  carpet, with soft shadows and creases. See ADR 0010 for why this model, what
  it costs in memory, and what was rejected.
* `BorderSampledRemover` (below) is the classical remover this service started
  with. It stays, for two reasons: it is the fallback when the model cannot
  run, and it keeps the property that the service starts and passes its suite
  with no network and no credentials even if the model file were missing.

Both finish through the same code here, [render_cutout], so a cutout looks the
same whichever one found the garment: the mask is eroded a pixel, the colour of
the edge is replaced with the garment's own, and the result is lightly
feathered. That last step matters more than the choice of remover for how the
result *looks*: the white fringe the owner saw was the board's colour bleeding
into edge pixels, and it appears on a dark tile whatever found the outline.

## What the classical remover does

1. Sample the border to build a model of the background colour. Real photos
   have gradients, shadow, and sometimes two different surfaces, so the border
   is clustered rather than averaged. Only clusters holding a real share of the
   border count as background: a garment touching the frame makes a small
   cluster, which must not be mistaken for backdrop.
2. Score every pixel by its distance to the nearest background cluster, in
   CIELAB so the distance is perceptual, less each cluster's own spread so a
   textured carpet is background rather than a field of tiny foregrounds.
3. Threshold, keep the largest connected region, fill its holes.
4. Render it (above).
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

# The longest edge of the cutout that gets returned.
#
# A cutout is only ever *displayed* — it is the picture in a wardrobe row, a
# grid cell, or the 160dp image on an item's page, so about 540 device pixels
# at its very largest on a phone. Returning it at the source's full size meant
# a PNG with an alpha channel at up to 1600px: several megabytes per garment,
# sent over mobile data and then kept forever in a browser's storage, for
# roughly nine times the pixels anything draws.
#
# 768 leaves comfortable headroom over that 540 while cutting the stored bytes
# several-fold. The identification pipeline is unaffected — it reads the
# original photograph, never this.
_MAX_CUTOUT_EDGE = 768

# How wide a border strip counts as "definitely background", as a fraction of
# the shorter edge. Narrow enough to exclude a garment that fills the frame,
# wide enough to survive a slightly off-centre shot.
_BORDER_FRACTION = 0.06

# Background colour clusters. More than one because a real backdrop is lit
# unevenly; more than a handful just fits noise.
_BACKGROUND_CLUSTERS = 4

# A border cluster is only backdrop if it holds at least this share of the
# border. Smaller ones are more likely a garment touching the frame.
_MIN_CLUSTER_SHARE = 0.08

# How many of a cluster's own standard deviations are forgiven when measuring
# distance to it, so texture does not read as subject.
_SPREAD_DISCOUNT = 2.0


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
        rgb = decode_for_cutout(image_bytes)

        work = rgb.copy()
        work.thumbnail((_WORK_EDGE, _WORK_EDGE), Image.Resampling.LANCZOS)

        lab = _to_lab(np.asarray(work, dtype=np.float64) / 255.0)
        distance = _distance_from_background(lab)
        mask = _largest_region(distance > _threshold(distance))

        return render_cutout(rgb, _resize_mask(mask, rgb.size))


def decode_for_cutout(image_bytes: bytes) -> Image.Image:
    """The photograph as RGB at the size the cutout will be returned at.

    Never holds the full-size image when it does not have to: a JPEG is decoded
    at a reduced scale (Pillow's `draft`, which makes the decoder skip the
    discarded detail rather than computing and throwing it away), so a
    12-megapixel photograph costs about what a 1-megapixel one does. This is
    the first line of defence for the server's 512 MB.
    """
    try:
        source = Image.open(io.BytesIO(image_bytes))
        target = _display_size(source.size)
        if source.format == "JPEG":
            source.draft("RGB", target)
        source.load()
        rgb = source.convert("RGB")
    except Exception as error:  # Pillow raises a wide variety here.
        raise CutoutError("the image could not be decoded") from error

    if rgb.size != target:
        rgb = rgb.resize(target, Image.Resampling.LANCZOS)
    return rgb


def _resize_mask(mask: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    """A boolean mask at another size, with a smooth rather than blocky edge."""
    if (mask.shape[1], mask.shape[0]) == size:
        return mask
    image = Image.fromarray((mask * 255).astype(np.uint8), mode="L")
    resized = np.asarray(image.resize(size, Image.Resampling.BILINEAR))
    result: np.ndarray = resized >= 128
    return result


# How far inside the garment the "trusted" colour starts, and how far out the
# trusted colour is spread. The mask is eroded by one pixel; the colour of
# everything outside the trusted interior is then rebuilt from the interior.
_EDGE_TRUST_PX = 3
_EDGE_FILL_RADIUS = 8
_FEATHER_RADIUS = 1.0


def box_mean(values: np.ndarray, radius: int) -> np.ndarray:
    """Mean over a (2r+1) square window, by integral image.

    Windows are clipped at the frame rather than padded, so an edge pixel is
    the mean of the pixels that exist. Float32 throughout: this runs over
    every pixel of the returned image and the memory is the constraint.
    """
    height, width = values.shape[:2]
    padded = np.zeros((height + 1, width + 1, *values.shape[2:]), dtype=np.float64)
    padded[1:, 1:] = values.cumsum(axis=0).cumsum(axis=1)

    ys = np.arange(height)
    xs = np.arange(width)
    y0 = np.clip(ys - radius, 0, height)
    y1 = np.clip(ys + radius + 1, 0, height)
    x0 = np.clip(xs - radius, 0, width)
    x1 = np.clip(xs + radius + 1, 0, width)

    total = padded[y1][:, x1] - padded[y0][:, x1] - padded[y1][:, x0] + padded[y0][:, x0]
    area = ((y1 - y0)[:, None] * (x1 - x0)[None, :]).astype(np.float64)
    if values.ndim == 3:
        area = area[..., None]
    result: np.ndarray = (total / area).astype(np.float32)
    return result


def _erode(mask: np.ndarray, pixels: int) -> np.ndarray:
    if pixels <= 0:
        return mask
    image = Image.fromarray((mask * 255).astype(np.uint8), mode="L")
    eroded = image.filter(ImageFilter.MinFilter(2 * pixels + 1))
    result: np.ndarray = np.asarray(eroded) >= 128
    return result


def render_cutout(rgb: Image.Image, mask: np.ndarray) -> Cutout:
    """Turns a boolean subject mask over [rgb] into the PNG that is returned.

    `mask` is at `rgb`'s own size. This is where the white fringe is removed:

    1. Erode the mask a pixel, so the outline sits on the garment rather than
       on the blend of garment and board that the camera recorded at the edge.
    2. Take the colour of the garment's *interior* (a few pixels in from the
       outline) and spread it outward over the edge band. The pixels that
       survive at the edge then carry the garment's colour, not the board's,
       so a dark shirt on a dark tile has no pale halo whatever the alpha does.
    3. Feather lightly, so it composites without a hard jagged line.
    """
    coverage = float(mask.mean())

    outline = _erode(mask, 1)
    interior = _erode(mask, _EDGE_TRUST_PX)

    pixels = np.asarray(rgb, dtype=np.float32)
    weight = interior.astype(np.float32)
    colour = box_mean(pixels * weight[..., None], _EDGE_FILL_RADIUS)
    support = box_mean(weight, _EDGE_FILL_RADIUS)

    # Where the interior reaches (support > 0) the colour is rebuilt from it;
    # beyond that, or in a part too thin to have an interior, keep the original.
    reach = (support > 1e-3) & ~interior
    filled = np.where(reach[..., None], colour / np.maximum(support, 1e-3)[..., None], pixels)

    alpha = Image.fromarray((outline * 255).astype(np.uint8), mode="L")
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=_FEATHER_RADIUS))

    cut = Image.fromarray(np.clip(filled, 0, 255).astype(np.uint8), mode="RGB").convert("RGBA")
    cut.putalpha(alpha)

    buffer = io.BytesIO()
    cut.save(buffer, format="PNG", optimize=True)

    return Cutout(
        png=buffer.getvalue(),
        coverage=coverage,
        # The returned image's own size, which is what a caller laying it out
        # needs — not the size of the photograph it came from.
        width=rgb.size[0],
        height=rgb.size[1],
    )


def _display_size(size: tuple[int, int]) -> tuple[int, int]:
    """The size to return a cutout at, capped to [_MAX_CUTOUT_EDGE].

    Never upscales: a small photograph stays its own size rather than being
    inflated to a cap, which would add bytes and no detail. Aspect ratio is
    preserved, and neither edge is allowed to round down to zero.
    """
    width, height = size
    longest = max(width, height)
    if longest <= _MAX_CUTOUT_EDGE:
        return size

    scale = _MAX_CUTOUT_EDGE / longest
    return (max(1, round(width * scale)), max(1, round(height * scale)))


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


def _background_clusters(border: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Representative background colours and each one's spread, by k-means.

    Clustered rather than averaged because a backdrop lit from one side is two
    colours, and their mean is a third that appears nowhere in the picture —
    which makes both real ones look like foreground. A white board with carpet
    showing at its edge is the same shape of problem.

    Only a cluster holding a real share of the border is background. A garment
    that touches the frame makes a small cluster of its own, and counting that
    as backdrop would eat the garment from the side. Where *every* cluster is
    small (a very noisy border) all are kept, as before.
    """
    rng = np.random.default_rng(0)  # Deterministic: same photo, same cutout.
    k = min(_BACKGROUND_CLUSTERS, len(border))
    centres = border[rng.choice(len(border), size=k, replace=False)]

    assignment = np.zeros(len(border), dtype=np.int64)
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

    shares = np.array([np.mean(assignment == i) for i in range(k)])
    spreads = np.array(
        [
            float(np.sqrt(((border[assignment == i] - centres[i]) ** 2).sum(axis=1).mean()))
            if np.any(assignment == i)
            else 0.0
            for i in range(k)
        ]
    )

    keep = shares >= _MIN_CLUSTER_SHARE
    if not keep.any():
        keep = shares > 0
    return centres[keep], spreads[keep]


def _distance_from_background(lab: np.ndarray) -> np.ndarray:
    """Per-pixel distance to the nearest background colour, beyond its spread.

    A textured backdrop (carpet) is a cloud of colours, not a point. Measuring
    to the cloud's centre makes every fibre look like foreground; discounting
    the cloud's own spread makes the carpet background and leaves the garment,
    which is a different colour altogether, far from it.
    """
    centres, spreads = _background_clusters(_border_pixels(lab))
    flat = lab.reshape(-1, 1, 3)
    raw = np.linalg.norm(flat - centres[None, :, :], axis=2)
    discounted = np.clip(raw - _SPREAD_DISCOUNT * spreads[None, :], 0.0, None)
    reshaped: np.ndarray = discounted.min(axis=1).reshape(lab.shape[:2])
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
