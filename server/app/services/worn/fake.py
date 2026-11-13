"""A deterministic scanner, for tests and for running with no credentials.

It reads the photograph's bytes for a seed, like the fake vision provider, so
the same photograph always finds the same outfit and different ones differ. It
returns two or three pieces (a top, trousers, and shoes when the seed says so)
with **real** masks, drawn small and in Gemini's own wire form, `data:` prefix
included, so the app and the tests exercise the cutting for real rather than a
canned picture.

The outlines are simple shapes, which is the point: they are known, so a test
can say which pixel must be opaque. Two of them are worth a note. The shoes'
mask is two separate shapes, so the rule that a pair is two regions is on the
default path. And on every third photograph the *last* detection comes back
with no mask at all, which is what a model that cannot draw them does, so the
box-crop fallback is also something the app sees by default rather than only in
a test that remembers to ask for it.
"""

from __future__ import annotations

import base64
import hashlib
import io

from PIL import Image, ImageDraw

from app.schemas.common import Confident, Provenance
from app.schemas.scan import GarmentScanResult
from app.schemas.wardrobe import ColorPalette, ItemColor, ItemType, Pattern
from app.services.ai.base import ScanImage
from app.services.worn.base import RawDetection
from app.services.worn.cutting import NormalisedBox

_TOPS: tuple[ItemType, ...] = (ItemType.T_SHIRT, ItemType.HOODIE, ItemType.JACKET)
_BOTTOMS: tuple[ItemType, ...] = (ItemType.JEANS, ItemType.CHINOS, ItemType.TROUSERS)
_SHOES: tuple[ItemType, ...] = (ItemType.SNEAKERS, ItemType.BOOTS)

_COLORS: tuple[tuple[str, float, float, float], ...] = (
    ("White", 96.5, 0.1, 0.6),
    ("Black", 18.0, 0.0, 0.0),
    ("Navy", 24.1, 2.3, -8.7),
    ("Gray", 63.7, 0.0, 0.0),
    ("Red", 53.2, 80.1, 67.2),
)

_MASK_EDGE = 64
"""The fakes' masks are this many pixels square whatever their box is: the
cutting resizes a mask to its box, which is also what it does for a real one."""


class FakeWornScanner:
    @property
    def name(self) -> str:
        return "fake"

    async def read(self, image: ScanImage) -> list[RawDetection]:
        seed = int.from_bytes(hashlib.sha256(image.data).digest()[:4], "big")
        has_shoes = seed % 2 == 0
        without_mask = seed % 3 == 0

        pieces = [
            (_TOPS[seed % len(_TOPS)], NormalisedBox(0.22, 0.18, 0.78, 0.50), _blob_mask),
            (
                _BOTTOMS[(seed // 3) % len(_BOTTOMS)],
                NormalisedBox(0.28, 0.50, 0.72, 0.88),
                _trousers_mask,
            ),
        ]
        if has_shoes:
            pieces.append(
                (
                    _SHOES[(seed // 5) % len(_SHOES)],
                    NormalisedBox(0.22, 0.88, 0.78, 0.98),
                    _pair_mask,
                )
            )

        detections: list[RawDetection] = []
        for index, (item_type, box, draw) in enumerate(pieces):
            name, lightness, a, b = _COLORS[(seed // 7 + index * 2) % len(_COLORS)]
            is_last = index == len(pieces) - 1
            detections.append(
                RawDetection(
                    scan=GarmentScanResult(
                        type=Confident[ItemType](
                            value=item_type,
                            confidence=0.9 - index * 0.05,
                            source=Provenance.AI_INFERENCE,
                        ),
                        colors=Confident[ColorPalette](
                            value=ColorPalette(
                                [ItemColor(l=lightness, a=a, b=b, coverage=1.0, name=name)]
                            ),
                            confidence=0.85,
                            source=Provenance.AI_INFERENCE,
                        ),
                        pattern=Confident[Pattern](
                            value=Pattern.SOLID, confidence=0.8, source=Provenance.AI_INFERENCE
                        ),
                        suggested_name=f"{name} {item_type.value}",
                    ),
                    box=box,
                    detection_confidence=0.9 - index * 0.06,
                    mask=None if (without_mask and is_last) else draw(),
                )
            )
        return detections


def _encode(mask: Image.Image) -> str:
    buffer = io.BytesIO()
    mask.save(buffer, format="PNG")
    # Gemini's own form, prefix and all, so that is what the cutting is tested on.
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


def _canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    mask = Image.new("L", (_MASK_EDGE, _MASK_EDGE), 0)
    return mask, ImageDraw.Draw(mask)


def _blob_mask() -> str:
    """A top: one rounded shape most of the way to the box edges."""
    mask, draw = _canvas()
    draw.rounded_rectangle([6, 4, 58, 60], radius=14, fill=255)
    return _encode(mask)


def _trousers_mask() -> str:
    """Trousers: a waistband and two legs, joined, with a gap between."""
    mask, draw = _canvas()
    draw.rectangle([8, 2, 56, 18], fill=255)
    draw.rectangle([8, 18, 29, 62], fill=255)
    draw.rectangle([35, 18, 56, 62], fill=255)
    return _encode(mask)


def _pair_mask() -> str:
    """Shoes: two shapes that do not touch. Both must survive the cutting."""
    mask, draw = _canvas()
    draw.ellipse([2, 14, 28, 50], fill=255)
    draw.ellipse([36, 14, 62, 50], fill=255)
    return _encode(mask)
