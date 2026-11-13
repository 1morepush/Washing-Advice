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
5. Fill small holes, feather the edge and cut the garment out.

## The cutout is the box, not the garment

An outline cutout covers exactly the detection's box, transparent where the
garment is not, and is *not* trimmed to the garment. The app keeps an opaque
crop of the same box beside it, and the cutout editor's "add back" brush
restores pixels from that crop, so the two have to be the same frame: a cutout
trimmed to the mask would not line up with anything, and a garment whose outline
was drawn too tight could never be repaired. The app trims transparent margins
itself when it draws a tile.

The box is `pixel_box`'s: the model's fractions floored on the left and top and
ceiled on the right and bottom, then clamped to the photograph. The response
reports that box as pixel edges divided by the photograph's size, so the app
multiplying back and rounding to the nearest pixel finds exactly these edges
and crops exactly these pixels. Both halves round the same way and neither
trusts a float to land on an integer.

## Invisible pixels, and the soft edge

The colour under every fully transparent pixel is zeroed. A cutout is kept
forever and shown small; the face that stood beside the garment must not be
recoverable from the picture's invisible pixels.

The feathered band around the outline is not fully transparent, so zeroing
would not cover it, and left alone it would carry the neighbour's real colour
(an arm, a wall) at low opacity. Outside the thresholded mask the colour is
instead bled outward from the garment's own edge, so the band is garment-coloured
and the background never appears in the file at any opacity.
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

# Feather radius in working-resolution pixels, as `cutout.py` does it: blurred
# before the resize so the edge stays proportionate whatever the photograph's size.
_FEATHER_RADIUS = 1.2

# A box smaller than this on either side is a point, not a garment.
_MIN_BOX_PX = 4

# The most pixels a photograph may have before it is refused, checked from the
# file's header and before anything is decoded. A 200 kB PNG can declare a
# hundred-megapixel canvas, which is the cheap way to take a worker's memory.
# Forty megapixels is a 200 MP phone camera's binned output and far beyond the
# 1600 px the app sends.
MAX_PHOTO_PIXELS = 40_000_000

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
    """RGBA PNG bytes of the whole box, capped to the display size.

    For `OUTLINE` the box is the frame and the garment is where it is opaque;
    for `BOX` the picture is the box's opaque crop.
    """

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

    Refuses a photograph of more than `MAX_PHOTO_PIXELS` before decoding it.
    """
    try:
        source = Image.open(io.BytesIO(photo.data))
    except Exception as error:  # Pillow raises a wide variety here.
        raise PhotoError("the photograph could not be opened") from error

    # From the header alone: nothing has been decoded yet.
    if source.width * source.height > MAX_PHOTO_PIXELS:
        megapixels = MAX_PHOTO_PIXELS // 1_000_000
        raise PhotoError(
            f"the photograph is too large to read (over {megapixels} megapixels); "
            "send a smaller one"
        )

    try:
        if source.format == "JPEG":
            # Lets the decoder skip work when it can shrink on the way in. It
            # only ever shrinks by whole halves, and asked for 4096 px it
            # leaves any ordinary photograph at its own size.
            source.draft("RGB", (4096, 4096))
        source.load()
    except Exception as error:
        raise PhotoError("the photograph could not be opened") from error

    try:
        turned = source.getexif().get(0x0112, 1) not in (0, 1)
        upright = ImageOps.exif_transpose(source) if turned else source
        # No copy when it is RGB already, which an ordinary JPEG is.
        rgb = upright if upright.mode == "RGB" else upright.convert("RGB")
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

    solid: Image.Image
    """Mode `L`, 0 or 255: the thresholded garment, before feathering."""


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

    solid = Image.fromarray(kept.astype(np.uint8) * 255, mode="L")
    alpha = solid.filter(ImageFilter.GaussianBlur(radius=_FEATHER_RADIUS))
    return _Outline(alpha=alpha, solid=solid)


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
    box = (pixels.left, pixels.top, pixels.right, pixels.bottom)
    crop = photo.crop(box)
    out_size = _display_size(crop.size)

    colour = crop if out_size == crop.size else crop.resize(out_size, Image.Resampling.LANCZOS)
    alpha = outline.alpha.resize(out_size, Image.Resampling.BILINEAR)
    solid = np.asarray(outline.solid.resize(out_size, Image.Resampling.NEAREST)) > _THRESHOLD

    bled = _bleed_outwards(crop, np.asarray(colour, dtype=np.uint8), solid, outline)
    return _finish(bled, np.asarray(alpha), CutoutKind.OUTLINE, pixels, photo.size)


def _bleed_outwards(
    crop: Image.Image, colour: np.ndarray, solid: np.ndarray, outline: _Outline
) -> np.ndarray:
    """[colour] with everything outside [solid] replaced by the garment's edge colour.

    A normalised blur: the garment's colour blurred, divided by the garment's
    coverage blurred, which is the average of the garment pixels nearby and
    nowhere the average of anything else. It is done at working resolution, in
    floats, where the soft edge is a few pixels wide: at the output's size the
    kernel would be dozens of taps, and in 8 bits the division is noise. The
    kernel is wider than the alpha's feather, so every pixel the alpha leaves
    visible has garment pixels in reach.
    """
    size = outline.alpha.size
    source = np.asarray(crop.resize(size, Image.Resampling.BOX), dtype=np.float32)
    inside = np.asarray(outline.solid) > _THRESHOLD
    # Sourced one pixel in from the outline, where the photograph is garment
    # rather than a blend of garment and neighbour, unless that leaves nothing.
    core = np.asarray(outline.solid.filter(ImageFilter.MinFilter(3))) > _THRESHOLD
    if core.any():
        inside = core

    sigma = _FEATHER_RADIUS * 2.0
    weight = _gaussian(inside.astype(np.float32), sigma)
    spread = np.stack(
        [_gaussian(source[..., i] * inside, sigma) for i in range(3)],
        axis=-1,
    )
    nearby = np.clip(np.rint(spread / np.maximum(weight, 1e-6)[..., None]), 0, 255)
    nearby_image = Image.fromarray(nearby.astype(np.uint8), mode="RGB")
    if nearby_image.size != (colour.shape[1], colour.shape[0]):
        nearby_image = nearby_image.resize(
            (colour.shape[1], colour.shape[0]), Image.Resampling.BILINEAR
        )
    return np.where(solid[..., None], colour, np.asarray(nearby_image))


def _gaussian(values: np.ndarray, sigma: float) -> np.ndarray:
    """A separable Gaussian blur in floats, edges treated as empty."""
    reach = max(1, math.ceil(sigma * 4))
    offsets = np.arange(-reach, reach + 1)
    kernel = np.exp(-(offsets**2) / (2 * sigma**2))
    kernel /= kernel.sum()

    padded = np.pad(values, reach)
    horizontal = sum(
        weight * padded[:, reach + offset : reach + offset + values.shape[1]]
        for offset, weight in zip(offsets.tolist(), kernel.tolist(), strict=True)
    )
    vertical = sum(
        weight * horizontal[reach + offset : reach + offset + values.shape[0], :]
        for offset, weight in zip(offsets.tolist(), kernel.tolist(), strict=True)
    )
    return np.asarray(vertical, dtype=np.float32)


def _box_cut(photo: Image.Image, pixels: PixelBox) -> Cut:
    crop = photo.crop((pixels.left, pixels.top, pixels.right, pixels.bottom))
    out_size = _display_size(crop.size)
    if out_size != crop.size:
        crop = crop.resize(out_size, Image.Resampling.LANCZOS)

    # Opaque: the background is in this picture, and an alpha channel that said
    # otherwise would make it look cut out.
    opaque = np.full((out_size[1], out_size[0]), 255, dtype=np.uint8)
    return _finish(np.asarray(crop, dtype=np.uint8), opaque, CutoutKind.BOX, pixels, photo.size)


def _finish(
    colour: np.ndarray,
    alpha: np.ndarray,
    kind: CutoutKind,
    pixels: PixelBox,
    photo_size: tuple[int, int],
) -> Cut:
    rgba = np.dstack([colour, alpha])
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
        width=colour.shape[1],
        height=colour.shape[0],
    )


def _clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))
