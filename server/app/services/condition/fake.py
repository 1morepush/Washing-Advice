"""A deterministic reader, for tests and for running without a key.

Branches on the image bytes rather than returning one canned answer, so a
downstream test that seeds two different photographs gets two different
readings — a fake that always said "moderate pilling" would make every screen
test look like it passed for the wrong reason.

Deliberately returns nothing at all for most inputs, because that is what the
real reader should do. A fake that always found something would let a screen
ship having never once been drawn in its commonest state.

It also returns one observation below the confidence floor, so the layer that
drops those is exercised by default rather than only where a test remembers to
ask for it.
"""

from __future__ import annotations

import hashlib

from app.schemas.condition import (
    ConditionScanResult,
    ObservedWear,
    WearSeverity,
    WearType,
)
from app.services.condition.base import ConditionRequest


class FakeConditionReader:
    @property
    def name(self) -> str:
        return "fake"

    async def read(self, request: ConditionRequest) -> ConditionScanResult:
        digest = hashlib.sha256(request.images[0].data).digest()
        bucket = digest[0] % 4

        if bucket == 0:
            # The commonest real answer, and the one a screen most needs to
            # have been drawn in.
            return ConditionScanResult(observed=[])

        if bucket == 1:
            return ConditionScanResult(
                observed=[
                    ObservedWear(
                        type=WearType.PILLING,
                        severity=WearSeverity.MODERATE,
                        confidence=0.86,
                        note="along the inner sleeve",
                    )
                ]
            )

        if bucket == 2:
            return ConditionScanResult(
                observed=[
                    ObservedWear(
                        type=WearType.FADING,
                        severity=WearSeverity.SLIGHT,
                        confidence=0.74,
                        note="across the shoulders",
                    ),
                    # Under the core's floor: dropped, and it should be.
                    ObservedWear(
                        type=WearType.HOLE,
                        severity=WearSeverity.SEVERE,
                        confidence=0.21,
                        note="possibly near the hem, hard to tell",
                    ),
                ]
            )

        return ConditionScanResult(
            observed=[
                ObservedWear(
                    type=WearType.LOOSE_SEAM,
                    severity=WearSeverity.SEVERE,
                    confidence=0.91,
                    note="at the left shoulder",
                )
            ]
        )
