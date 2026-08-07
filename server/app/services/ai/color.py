"""sRGB to CIELAB conversion.

Vision models answer far more reliably in hex than in CIELAB — asking one for
`L*a*b*` directly produces plausible-looking numbers that are frequently wrong.
So providers request hex and this converts, which also means the conversion is
exercised by every scan rather than trusted to the model.

Mirrors `ItemColor.fromRgb` in the Dart core exactly (sRGB → linear → XYZ under
D65 → CIELAB). The two implementations are checked against each other by the
contract fixtures.
"""

from __future__ import annotations

import re

_HEX_PATTERN = re.compile(r"^#?([0-9a-fA-F]{6})$")

# D65 reference white.
_XN, _YN, _ZN = 0.95047, 1.0, 1.08883
_DELTA = 6.0 / 29.0


def _to_linear(channel: int) -> float:
    value = channel / 255.0
    if value <= 0.04045:
        return value / 12.92
    return float(((value + 0.055) / 1.055) ** 2.4)


def _f(t: float) -> float:
    if t > _DELTA**3:
        return float(t ** (1.0 / 3.0))
    return t / (3 * _DELTA**2) + 4.0 / 29.0


def rgb_to_lab(red: int, green: int, blue: int) -> tuple[float, float, float]:
    """Converts 8-bit sRGB to CIELAB (D65), returning `(L*, a*, b*)`."""
    r, g, b = _to_linear(red), _to_linear(green), _to_linear(blue)

    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

    fx, fy, fz = _f(x / _XN), _f(y / _YN), _f(z / _ZN)

    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def hex_to_lab(value: str) -> tuple[float, float, float]:
    """Converts `#RRGGBB` or `RRGGBB` to CIELAB.

    Raises `ValueError` on anything else. A model that returns "navy blue"
    instead of a hex code is a prompt bug to surface, not to guess around.
    """
    match = _HEX_PATTERN.match(value.strip())
    if match is None:
        raise ValueError(f"expected a 6-digit hex colour, got {value!r}")

    packed = int(match.group(1), 16)
    return rgb_to_lab((packed >> 16) & 0xFF, (packed >> 8) & 0xFF, packed & 0xFF)
