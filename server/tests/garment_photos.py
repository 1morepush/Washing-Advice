"""Synthetic photographs that reproduce the owner's real failures.

Built rather than checked in as images so the test data is a few lines, the
correct answer is *known* (the garment polygon is the ground truth), and no
real person's wardrobe sits in the repository.

Two failures, both from clothes laid on a white board on carpet:

* `on_board`: the border is board only, but shadows and creases make the
  border-colour rule read shadow as garment, leaving a ragged shape.
* `board_on_carpet`: the board does not fill the frame, so the border is part
  board, part carpet, and the rule finds no background to subtract.
"""

from __future__ import annotations

import io

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = (480, 640)

# A t-shirt, as fractions of the frame: body, then sleeves.
_SHIRT = [
    (0.30, 0.20), (0.40, 0.17), (0.50, 0.21), (0.60, 0.17), (0.70, 0.20),
    (0.92, 0.32), (0.84, 0.44), (0.72, 0.38), (0.72, 0.80), (0.28, 0.80),
    (0.28, 0.38), (0.16, 0.44), (0.08, 0.32),
]  # fmt: skip


def shirt_polygon(size: tuple[int, int] = SIZE) -> list[tuple[float, float]]:
    return [(x * size[0], y * size[1]) for x, y in _SHIRT]


def truth_mask(size: tuple[int, int] = SIZE) -> np.ndarray:
    """Where the garment really is."""
    image = Image.new("L", size, 0)
    ImageDraw.Draw(image).polygon(shirt_polygon(size), fill=255)
    return np.asarray(image) > 127


def _textured(size: tuple[int, int], base: tuple[int, int, int], noise: float, seed: int) -> Image:
    rng = np.random.default_rng(seed)
    grain = rng.normal(0, noise, (size[1], size[0], 1))
    array = np.clip(np.array(base, dtype=np.float64) + grain, 0, 255)
    return Image.fromarray(array.astype(np.uint8), mode="RGB")


def _garment_layer(size: tuple[int, int], colour: tuple[int, int, int], seed: int) -> Image:
    layer = _textured(size, colour, 5.0, seed)
    pixels = np.asarray(layer, dtype=np.float64)
    # Creases: soft diagonal bands of slightly different brightness.
    ys, xs = np.mgrid[0 : size[1], 0 : size[0]]
    folds = 1 + 0.05 * np.sin((xs + 0.6 * ys) / 11.0)
    return Image.fromarray(np.clip(pixels * folds[..., None], 0, 255).astype(np.uint8))


def _jpeg(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


def on_board(colour: tuple[int, int, int] = (40, 48, 70), seed: int = 1) -> bytes:
    """A garment on a white board that fills the frame, with a soft shadow."""
    size = SIZE
    board = _textured(size, (244, 244, 241), 2.0, seed)

    shadow = Image.new("L", size, 0)
    ImageDraw.Draw(shadow).polygon([(x + 14, y + 18) for x, y in shirt_polygon(size)], fill=215)
    shadow = shadow.filter(ImageFilter.GaussianBlur(7))
    board = Image.composite(Image.new("RGB", size, (70, 70, 70)), board, shadow)

    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(shirt_polygon(size), fill=255)
    board.paste(
        _garment_layer(size, colour, seed + 1), mask=mask.filter(ImageFilter.GaussianBlur(0.8))
    )
    return _jpeg(board)


def board_on_carpet(colour: tuple[int, int, int] = (40, 48, 70), seed: int = 2) -> bytes:
    """The same garment on a board that leaves carpet along two edges."""
    size = SIZE
    carpet = _textured(size, (132, 112, 92), 16.0, seed)
    board = _textured((456, 612), (244, 244, 241), 2.0, seed + 5)
    carpet.paste(board, (0, 0))

    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(shirt_polygon(size), fill=255)
    carpet.paste(
        _garment_layer(size, colour, seed + 1), mask=mask.filter(ImageFilter.GaussianBlur(0.8))
    )
    return _jpeg(carpet)


def iou(alpha: np.ndarray, truth: np.ndarray) -> float:
    """Intersection over union between a cutout's opaque pixels and the truth."""
    found = alpha > 127
    union = float((found | truth).sum())
    return float((found & truth).sum()) / union if union else 0.0


# Trousers laid flat and photographed to fill the frame: the waistband runs
# off the top edge and the hems off the bottom, so the border contains garment.
_TROUSERS = [
    (0.18, 0.04), (0.82, 0.04), (0.86, 0.30), (0.92, 0.96), (0.60, 0.96),
    (0.50, 0.42), (0.40, 0.96), (0.08, 0.96), (0.14, 0.30),
]  # fmt: skip


def trousers_polygon(size: tuple[int, int] = SIZE) -> list[tuple[float, float]]:
    return [(x * size[0], y * size[1]) for x, y in _TROUSERS]


def trousers_truth(size: tuple[int, int] = SIZE) -> np.ndarray:
    image = Image.new("L", size, 0)
    ImageDraw.Draw(image).polygon(trousers_polygon(size), fill=255)
    return np.asarray(image) > 127


def trousers_on_board(colour: tuple[int, int, int] = (58, 58, 66), seed: int = 3) -> bytes:
    """Dark trousers filling the frame, on a board with carpet down the left."""
    size = SIZE
    photo = _textured(size, (244, 244, 241), 2.0, seed)
    photo.paste(_textured((60, size[1]), (150, 132, 110), 14.0, seed + 4), (0, 0))

    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).polygon(trousers_polygon(size), fill=255)
    layer = _garment_layer(size, colour, seed + 1)
    # The pale stripe and waistband that most track pants have, which also give
    # the network something to recognise.
    paint = ImageDraw.Draw(layer)
    paint.line(
        [(0.15 * size[0], 0.30 * size[1]), (0.10 * size[0], 0.99 * size[1])],
        fill=(150, 150, 155),
        width=9,
    )
    paint.rectangle(
        [0.18 * size[0], 0.01 * size[1], 0.82 * size[0], 0.07 * size[1]], fill=(80, 80, 90)
    )
    photo.paste(layer, mask=mask.filter(ImageFilter.GaussianBlur(0.8)))
    return _jpeg(photo)
