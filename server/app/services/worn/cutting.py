"""Cutting a garment out of a photograph of the person wearing it.

The other cutout (`images/cutout.py`) measures how far each pixel is from the
colour the frame's border is made of, which works because the garment is laid
flat on a plain background. It cannot work here: a shirt on a person is
surrounded by arms, a face and a room, and none of that is a border colour.
What separates the shirt is an outline, and the only thing that can draw one is
the model that looked at the photograph.

## Why this is its own deterministic module

The outline is a model's answer, and models draw bad ones: empty, the whole
box, a blob that spills over a neighbour, a PNG that will not decode. Nothing
here trusts one. Every mask is decoded, measured and either accepted or thrown
away, and what is thrown away costs the user a rectangle of background rather
than a wrong picture, because a detection whose mask fails falls back to a plain
crop of its box and says so (`CutoutKind.BOX`). A model that returns no masks at
all (Google's documents disagree on whether the current models can) therefore
degrades the feature instead of breaking it.

No network, no randomness and no clock: the same photograph, box and mask give
the same bytes, which is what lets this be tested harder than anything else in
the feature.

## What it does with a mask

1. Decode it, tolerating the `data:image/png;base64,` prefix the model's own
   format puts on it. A mask is a probability map sized to the *box*, not to
   the photograph.
2. Resize it to the box and threshold at half.
3. Reject it if it covers under 2% of the box (a speck) or over 98% (the box
   itself, which is no outline at all).
4. Keep every region that is a real part of the garment and drop the speckle.
   Not just the largest: a pair of shoes is two regions, and a cutout of one
   shoe is a wrong answer.
5. Fill small holes, feather the edge, cut the garment out and crop to the mask
   with a margin.

The colour under every fully transparent pixel is zeroed. A cutout is kept
forever and shown small; the face that stood beside the garment must not be
recoverable from the picture's invisible pixels.
"""

from __future__ import annotations

import base64
import binascii
import io
import math
from collections.abc import Sequence
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageFilter, ImageOps

from app.schemas.scan import CutoutKind
from app.services.ai.base import ScanImage
from app.services.images.cutout import _display_size, _label

# A mask is rejected when it covers less or more of its box than this. A real
# garment outline sits well inside: a long coat fills most of a tight box and
# glasses fill little of one, but nothing wearable is 1% or 99%.
_MIN_COVERAGE = 0.02
_MAX_COVERAGE = 0.98

# The probability map's midpoint. `>` rather than `>=`, as in Google's own
# example of using these masks.
_THRESHOLD = 127

# The longest edge the mask is analysed at. Region labelling is a flood fill in
# Python, so its cost is the pixel count: at the photograph's resolution it
# would be seconds a garment. Everything is decided at this size and only the
# finished alpha is resized up.
_WORK_EDGE = 320

# A region is part of the garment when it is at least this share of the largest
# region (and of the box). Two shoes are about equal; the speckle a threshold
# leaves is a thousandth.
_REGION_SHARE = 0.10
_MIN_REGION_COVERAGE = 0.005

# Holes smaller than this share of the box are noise inside the garment and are
# filled. Larger ones are real, such as the gap between a bag's strap and its
# body, and stay open, as do any that reach the box edge.
_HOLE_SHARE = 0.02

# Space left around the mask in the crop, as a share of its longer edge.
_MARGIN = 0.04

# Feather radius in working-resolution pixels, as `cutout.py` does it: blurred
# before the resize so the edge stays proportionate whatever the photograph's size.
_FEATHER_RADIUS = 1.2

# A box smaller than this on either side is a point, not a garment.
_MIN_BOX_PX = 4

# What a mask is allowed to cost before it is looked at. A PNG that is tiny to
# send and gigantic to decode is the cheap way to hurt a server.
_MAX_MASK_CHARS = 6_000_000
_MAX_MASK_PIXELS = 16_000_000


class PhotoError(Exception):
    """The photograph could not be opened, so nothing can be cut from it."""


@dataclass(frozen=True, slots=True)
class NormalisedBox:
    """A rectangle as a model reported it, as fractions of the photograph.

    Not validated, deliberately. A box that is backwards, empty or off the edge
    is exactly what `pixel_box` exists to reject, and a type that refused to
    hold one would turn a bad detection into a failed request.
    """

    left: float
    top: float
    right: float
    bottom: float

    @classmethod
    def from_box_2d(cls, box_2d: Sequence[float]) -> NormalisedBox:
        """From Gemini's `[y0, x0, y1, x1]`, normalised to 0-1000."""
        y0, x0, y1, x1 = box_2d
        return cls(left=x0 / 1000, top=y0 / 1000, right=x1 / 1000, bottom=y1 / 1000)


@dataclass(frozen=True, slots=True)
class PixelBox:
    """A box on the photograph's own pixels, inside it and not empty."""

    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self) -> int:
        return self.right - self.left

    @property
    def height(self) -> int:
        return self.bottom - self.top


@dataclass(frozen=True, slots=True)
class Cut:
    """One garment's picture."""

    png: bytes
    """RGBA PNG bytes, cropped and capped to the display size."""

    kind: CutoutKind

    box: NormalisedBox
    """The box the picture was cut from, clamped to the photograph.

    Reported back rather than the model's own, so that what the app is told is
    where the garment is cannot lie outside the photograph.
    """

    width: int
    height: int


@dataclass(frozen=True, slots=True)
class OrientedPhoto:
    """A photograph stood upright, and the bytes to show a model of it."""

    image: Image.Image
    """RGB and upright: the one picture every box is measured against."""

    for_model: ScanImage
    """What the model is sent.

    The original bytes when the photograph needed no turning, so an ordinary
    shot is not re-encoded; otherwise the upright pixels. Never the sideways
    original with a rotation tag, because the model's boxes and this module's
    crops must be measured on the same picture, and that is not something to
    leave to whether a model's decoder honours a tag.
    """


def orient_photo(photo: ScanImage) -> OrientedPhoto:
    """Stands a photograph upright by its EXIF orientation.

    A phone camera stores the sensor's pixels and a tag saying how to turn them.
    Pillow ignores the tag unless asked, so a crop taken without this one is
    cut from a sideways picture while the model, which reads the tag, boxed an
    upright one. Done once, here, so both halves see one photograph.
    """
    try:
        source = Image.open(io.BytesIO(photo.data))
        source.load()
    except Exception as error:  # Pillow raises a wide variety here.
        raise PhotoError("the photograph could not be opened") from error

    try:
        turned = source.getexif().get(0x0112, 1) not in (0, 1)
        upright = ImageOps.exif_transpose(source) if turned else source
        rgb = upright.convert("RGB")
    except Exception as error:
        raise PhotoError("the photograph could not be read") from error

    if not turned:
        return OrientedPhoto(image=rgb, for_model=photo)

    buffer = io.BytesIO()
    rgb.save(buffer, format="JPEG", quality=92)
    return OrientedPhoto(
        image=rgb,
        for_model=ScanImage(data=buffer.getvalue(), mime_type="image/jpeg"),
    )


def pixel_box(box: NormalisedBox, size: tuple[int, int]) -> PixelBox | None:
    """The box on the photograph's pixels, or nothing if it is nonsense.

    Clamped to the photograph: a box that hangs a little over the edge is an
    ordinary model habit and is cut where it is visible. Nonsense is a box with
    no area (backwards, a line, a point, or entirely off the photograph, which
    clamping turns into one) or one that is not a number.
    """
    width, height = size
    values = (box.left, box.top, box.right, box.bottom)
    if not all(math.isfinite(value) for value in values):
        return None

    # Rounded before floor and ceil, so 0.3 of a 10 px photograph is 3 and not
    # 4 because the float came out a hair over.
    left = _clamp(math.floor(round(box.left * width, 6)), 0, width)
    top = _clamp(math.floor(round(box.top * height, 6)), 0, height)
    right = _clamp(math.ceil(round(box.right * width, 6)), 0, width)
    bottom = _clamp(math.ceil(round(box.bottom * height, 6)), 0, height)

    if right - left < _MIN_BOX_PX or bottom - top < _MIN_BOX_PX:
        return None
    return PixelBox(left, top, right, bottom)


def cut_garment(photo: Image.Image, box: NormalisedBox, mask: str | None) -> Cut | None:
    """One garment's picture, or nothing when even its box is nonsense.

    [photo] must be the upright picture the box was measured on
    (`OrientedPhoto.image`). With no usable mask the result is the box's crop
    and `CutoutKind.BOX`; there is no failing outcome beyond a bad box, because
    a detection that has facts and a place is worth listing with a rough picture.
    """
    pixels = pixel_box(box, photo.size)
    if pixels is None:
        return None

    outline = _outline(mask, pixels.width, pixels.height) if mask else None
    if outline is None:
        return _box_cut(photo, pixels)
    return _outline_cut(photo, pixels, outline)


# --- The mask -----------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class _Outline:
    """A vetted mask, at working resolution and over the whole box."""

    alpha: Image.Image
    """Mode `L`, feathered: the box's shape at `_WORK_EDGE`."""

    bounds: tuple[int, int, int, int]
    """The tight bounds of the garment within [alpha], before feathering."""


def _outline(encoded: str, box_width: int, box_height: int) -> _Outline | None:
    """The vetted outline, or nothing if the mask should not be believed."""
    decoded = _decode_mask(encoded)
    if decoded is None:
        return None

    scale = min(1.0, _WORK_EDGE / max(box_width, box_height))
    size = (max(1, round(box_width * scale)), max(1, round(box_height * scale)))

    inside = np.asarray(decoded.resize(size, Image.Resampling.BILINEAR)) > _THRESHOLD
    if not _plausible(inside):
        return None

    kept = _keep_regions(inside)
    # Judged again, because cleaning can leave nothing worth having: a mask that
    # was a dozen scattered specks passes the first test by their total.
    if kept is None or not _plausible(kept):
        return None

    rows, columns = np.nonzero(kept)
    bounds = (
        int(columns.min()),
        int(rows.min()),
        int(columns.max()) + 1,
        int(rows.max()) + 1,
    )

    alpha = Image.fromarray(kept.astype(np.uint8) * 255, mode="L")
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius=_FEATHER_RADIUS))
    return _Outline(alpha=alpha, bounds=bounds)


def _decode_mask(encoded: str) -> Image.Image | None:
    """The mask as a greyscale image, or nothing if it will not decode."""
    text = encoded.strip()
    if not text or len(text) > _MAX_MASK_CHARS:
        return None

    if text[:5].lower() == "data:":
        _, comma, text = text.partition(",")
        if not comma:
            return None

    # Whitespace and the URL-safe alphabet are tolerated, and missing padding
    # restored: all are things a model's output does, and none is a reason to
    # lose a good outline.
    text = "".join(text.split()).replace("-", "+").replace("_", "/")
    text += "=" * (-len(text) % 4)

    try:
        raw = base64.b64decode(text, validate=True)
        with Image.open(io.BytesIO(raw)) as image:
            if image.width * image.height > _MAX_MASK_PIXELS:
                return None
            image.load()
            return image.convert("L")
    except (binascii.Error, ValueError):
        return None
    except Exception:  # Pillow raises a wide variety on a corrupt file.
        return None


def _plausible(inside: np.ndarray) -> bool:
    """Whether a mask covers a believable share of its box."""
    if inside.size == 0:
        return False
    coverage = float(inside.mean())
    return _MIN_COVERAGE <= coverage <= _MAX_COVERAGE


def _keep_regions(inside: np.ndarray) -> np.ndarray | None:
    """The mask's real regions, with small holes filled.

    A region is kept when it is a real fraction of the biggest one. That keeps
    both shoes and drops the speckle, which "keep the largest" (as `cutout.py`
    does for a garment that is one object) would not: a worn pair is two.
    """
    labels, sizes = _label(inside)
    if not sizes:
        return None

    floor = max(max(sizes.values()) * _REGION_SHARE, inside.size * _MIN_REGION_COVERAGE)
    keep = [label for label, size in sizes.items() if size >= floor]
    if not keep:
        return None
    kept: np.ndarray = np.isin(labels, keep)

    holes, hole_sizes = _label(~kept)
    on_the_edge = {
        *np.unique(holes[0, :]).tolist(),
        *np.unique(holes[-1, :]).tolist(),
        *np.unique(holes[:, 0]).tolist(),
        *np.unique(holes[:, -1]).tolist(),
    }
    limit = kept.size * _HOLE_SHARE
    fill = [
        label for label, size in hole_sizes.items() if size <= limit and label not in on_the_edge
    ]
    if fill:
        kept = kept | np.isin(holes, fill)
    return kept


# --- The picture --------------------------------------------------------------


def _outline_cut(photo: Image.Image, pixels: PixelBox, outline: _Outline) -> Cut:
    work_width, work_height = outline.alpha.size
    left, top, right, bottom = outline.bounds

    margin = max(1, round(max(right - left, bottom - top) * _MARGIN))
    left, top = max(0, left - margin), max(0, top - margin)
    right, bottom = min(work_width, right + margin), min(work_height, bottom + margin)

    # Working coordinates back to the photograph's. The crop is rounded outwards
    # to whole pixels and the alpha is then resampled from exactly the region
    # that crop covers, so the two never drift apart by a pixel.
    to_x, to_y = pixels.width / work_width, pixels.height / work_height
    crop_box = (
        max(pixels.left, math.floor(pixels.left + left * to_x)),
        max(pixels.top, math.floor(pixels.top + top * to_y)),
        min(pixels.right, math.ceil(pixels.left + right * to_x)),
        min(pixels.bottom, math.ceil(pixels.top + bottom * to_y)),
    )
    crop = photo.crop(crop_box)
    out_size = _display_size(crop.size)

    source = (
        (crop_box[0] - pixels.left) / to_x,
        (crop_box[1] - pixels.top) / to_y,
        (crop_box[2] - pixels.left) / to_x,
        (crop_box[3] - pixels.top) / to_y,
    )
    alpha = outline.alpha.resize(out_size, Image.Resampling.BILINEAR, box=source)
    colour = crop if out_size == crop.size else crop.resize(out_size, Image.Resampling.LANCZOS)

    return _finish(colour, np.asarray(alpha), CutoutKind.OUTLINE, pixels, photo.size)


def _box_cut(photo: Image.Image, pixels: PixelBox) -> Cut:
    crop = photo.crop((pixels.left, pixels.top, pixels.right, pixels.bottom))
    out_size = _display_size(crop.size)
    if out_size != crop.size:
        crop = crop.resize(out_size, Image.Resampling.LANCZOS)

    # Opaque: the background is in this picture, and an alpha channel that said
    # otherwise would make it look cut out.
    opaque = np.full((out_size[1], out_size[0]), 255, dtype=np.uint8)
    return _finish(crop, opaque, CutoutKind.BOX, pixels, photo.size)


def _finish(
    colour: Image.Image,
    alpha: np.ndarray,
    kind: CutoutKind,
    pixels: PixelBox,
    photo_size: tuple[int, int],
) -> Cut:
    rgba = np.dstack([np.asarray(colour, dtype=np.uint8), alpha])
    # Nothing is left behind a fully transparent pixel. See the module docstring.
    rgba[alpha == 0, :3] = 0

    buffer = io.BytesIO()
    Image.fromarray(rgba, mode="RGBA").save(buffer, format="PNG", optimize=True)

    width, height = photo_size
    return Cut(
        png=buffer.getvalue(),
        kind=kind,
        box=NormalisedBox(
            left=pixels.left / width,
            top=pixels.top / height,
            right=pixels.right / width,
            bottom=pixels.bottom / height,
        ),
        width=colour.width,
        height=colour.height,
    )


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))
