"""A deterministic provider, for tests and for running with no credentials.

Not a stub that returns one canned answer. It derives its output from a hash of
the image bytes, so different images produce different-but-stable results — the
same image always yields the same answer, which is what makes cache behaviour
and pipeline ordering testable at all.

It is also the default provider, so `uv run uvicorn app.main:app` works with an
empty environment. A service that cannot start without a billing account is a
service nobody can contribute to.
"""

from __future__ import annotations

import hashlib

from app.schemas.care import (
    Agitation,
    BleachAllowance,
    CareConstraint,
    CareWarning,
    IronTemperature,
    TumbleDryHeat,
    WashMethod,
    WashTemperature,
)
from app.schemas.common import BoundingBox, Confident, Provenance
from app.schemas.scan import (
    CareTagScanResult,
    DetectedItem,
    GarmentScanResult,
    PileScanResult,
)
from app.schemas.wardrobe import (
    ColorPalette,
    FabricComposition,
    Fiber,
    ItemColor,
    ItemType,
    Pattern,
    Season,
    SleeveLength,
)
from app.services.ai.base import ScanImage

_TYPES: tuple[ItemType, ...] = (
    ItemType.T_SHIRT,
    ItemType.HOODIE,
    ItemType.JEANS,
    ItemType.SWEATER,
    ItemType.DRESS_SHIRT,
    ItemType.BATH_TOWEL,
)

_COLORS: tuple[tuple[str, float, float, float], ...] = (
    ("White", 96.5, 0.1, 0.6),
    ("Black", 18.0, 0.0, 0.0),
    ("Navy", 24.1, 2.3, -8.7),
    ("Gray", 63.7, 0.0, 0.0),
    ("Red", 53.2, 80.1, 67.2),
)

_BRANDS: tuple[str, ...] = ("Nike", "Uniqlo", "Levi's", "Adidas")


class FakeVisionProvider:
    """Deterministic answers derived from the image bytes."""

    @property
    def name(self) -> str:
        return "fake"

    def _seed(self, image: ScanImage) -> int:
        return int.from_bytes(hashlib.sha256(image.data).digest()[:4], "big")

    async def scan_garment(self, images: list[ScanImage]) -> GarmentScanResult:
        seed = self._seed(images[0])
        item_type = _TYPES[seed % len(_TYPES)]
        name, lightness, a, b = _COLORS[(seed // 7) % len(_COLORS)]
        brand = _BRANDS[(seed // 13) % len(_BRANDS)]

        return GarmentScanResult(
            type=Confident[ItemType](
                value=item_type, confidence=0.93, source=Provenance.AI_INFERENCE
            ),
            colors=Confident[ColorPalette](
                value=ColorPalette([ItemColor(l=lightness, a=a, b=b, coverage=1.0, name=name)]),
                confidence=0.88,
                source=Provenance.AI_INFERENCE,
            ),
            composition=Confident[FabricComposition](
                value=FabricComposition({Fiber.COTTON: 80, Fiber.POLYESTER: 20}),
                confidence=0.72,
                source=Provenance.AI_INFERENCE,
            ),
            brand=Confident[str](value=brand, confidence=0.81, source=Provenance.AI_INFERENCE),
            pattern=Confident[Pattern](
                value=Pattern.SOLID, confidence=0.9, source=Provenance.AI_INFERENCE
            ),
            sleeve_length=Confident[SleeveLength](
                value=SleeveLength.SHORT_SLEEVE,
                confidence=0.85,
                source=Provenance.AI_INFERENCE,
            ),
            seasons=[Season.ALL_SEASON],
            suggested_name=f"{name} {item_type.value}",
        )

    async def scan_care_tag(self, images: list[ScanImage]) -> CareTagScanResult:
        # Seeded from the first photograph so a second side does not change the
        # answer for a label the tests already pin.
        seed = self._seed(images[0])
        # Every third label comes back with an unreadable symbol, so the
        # "part of this label could not be read" path is exercised by default
        # rather than only in a test that remembers to ask for it.
        unreadable = 1 if seed % 3 == 0 else 0
        # Every fifth label is French, for the same reason every third has an
        # unreadable symbol: the interesting path should be exercised by
        # default rather than only where a test remembers to ask for it. The
        # symbols are ISO 3758 and identical, so the structured answer is the
        # same one — only the words the user is shown differ.
        french = seed % 5 == 0

        return CareTagScanResult(
            instructions=CareConstraint(
                method=WashMethod.MACHINE,
                max_temp_c=30,
                # A US label: the word is what is printed, the number is the
                # convention it stands for. Both, so the app can show the
                # manufacturer's wording and still drive a machine.
                wash_temperature=WashTemperature.COLD,
                # A bar-less tub means normal, and the scan says so explicitly.
                agitation=Agitation.NORMAL,
                bleach=BleachAllowance.NONE,
                # Left unstated when a symbol was unreadable, so the core's rule
                # table fills the gap instead of reading silence as permission.
                tumble_dry_allowed=None if unreadable else True,
                tumble_dry_heat=None if unreadable else TumbleDryHeat.LOW,
                iron_temperature=IronTemperature.LOW,
                # A printed tee: ironable fabric, un-ironable graphic. Both
                # warnings are here so the whole pipeline — schema, wire,
                # Dart enum, care language — carries a prohibition that is
                # narrower than "do not iron" without a test having to ask.
                warnings=[
                    CareWarning.WASH_INSIDE_OUT,
                    CareWarning.DO_NOT_IRON_DECORATION,
                ],
                # Only ever stated by a label; no fibre rule infers it. Until
                # the Dart constraint carried a `solvent` field this was
                # decoded into nothing on arrival.
                do_not_dry_clean=True,
            ),
            confidence=0.7 if unreadable else 0.92,
            composition=Confident[FabricComposition](
                value=FabricComposition({Fiber.COTTON: 95, Fiber.ELASTANE: 5}),
                confidence=0.96,
                source=Provenance.TAG_SCAN,
            ),
            symbols_found=["wash.30", "bleach.none", "iron.low"],
            unreadable_symbol_count=unreadable,
            # Never translated. It is what the user reads to check the app
            # against the tag in their hand, and a translation would make that
            # impossible.
            raw_text=(
                "95% COTON 5% ÉLASTHANNE / LAVER À FROID / LAVER À L'ENVERS"
                if french
                else "95% COTTON 5% ELASTANE / MACHINE WASH COLD"
            ),
            language="fr" if french else "en",
        )

    async def scan_pile(self, image: ScanImage) -> PileScanResult:
        seed = self._seed(image)
        count = 2 + (seed % 3)

        items: list[DetectedItem] = []
        for index in range(count):
            item_type = _TYPES[(seed + index * 5) % len(_TYPES)]
            name, lightness, a, b = _COLORS[(seed + index * 3) % len(_COLORS)]
            items.append(
                DetectedItem(
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
                        suggested_name=f"{name} {item_type.value}",
                    ),
                    bounding_box=BoundingBox(
                        left=min(0.05 + index * 0.22, 0.9),
                        top=min(0.1 + index * 0.18, 0.9),
                        width=0.2,
                        height=0.18,
                    ),
                    detection_confidence=0.88 - index * 0.06,
                )
            )

        return PileScanResult(items=items, partially_obscured_count=seed % 2)
