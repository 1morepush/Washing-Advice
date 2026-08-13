"""A deterministic stain adviser, for tests and for running without a key.

Not a stub that returns one canned answer. It branches on the substance the way
a real adviser does — oil is not treated like wine is not treated like blood —
because the tests that matter downstream are about the app *refusing* steps,
and a fake that never proposed a hot soak or a bleach could not exercise them.

It is also deliberately willing to propose something unsafe. `FakeVisionProvider`
is honest about what a model would really return, and a fake adviser that only
ever suggested cold water would make the whole vetting layer look untested.
"""

from __future__ import annotations

from app.schemas.stains import (
    BleachUse,
    StainAdviceRequest,
    StainAdviceResponse,
    TreatmentStep,
)
from app.services.ai.base import ScanImage

_BLOT = TreatmentStep(
    instruction="Blot the mark with a clean dry cloth, working from the outside in.",
    because="Working inward keeps the stain from spreading into clean fabric.",
    abrades=True,
)

_RINSE_COLD = TreatmentStep(
    instruction="Rinse the back of the fabric under a cold tap.",
    because="Pushing from behind lifts the stain out rather than through.",
    temperature_c=20,
)

_WASH = TreatmentStep(
    instruction="Wash as normal and check the mark before it goes anywhere near heat.",
    because="Heat sets whatever is left, and a dryer makes it permanent.",
    is_machine_wash=True,
)


def _protein() -> list[TreatmentStep]:
    """Blood, egg, dairy, sweat: cold only, and never hot."""
    return [
        _BLOT,
        _RINSE_COLD,
        TreatmentStep(
            instruction="Soak in cold water with an enzyme detergent for 30 minutes.",
            because="Enzymes break protein down. Hot water cooks it into the fibre "
            "instead, which is why the instinct to use hot water is wrong here.",
            temperature_c=20,
        ),
        _WASH,
    ]


def _greasy() -> list[TreatmentStep]:
    """Oil, butter, make-up: lift the grease before any water."""
    return [
        TreatmentStep(
            instruction="Cover the mark in cornflour or talc and leave it 15 minutes, "
            "then brush it off.",
            because="Dry powder pulls the oil out. Water at this stage spreads it.",
            abrades=True,
        ),
        TreatmentStep(
            instruction="Work a little washing-up liquid into the mark and leave it 10 minutes.",
            because="A degreaser is what shifts oil; detergent alone will not.",
            abrades=True,
        ),
        TreatmentStep(
            instruction="Rinse with warm water.",
            temperature_c=40,
        ),
        _WASH,
    ]


def _tannin() -> list[TreatmentStep]:
    """Wine, tea, coffee, fruit: flush fast, then oxygen bleach."""
    return [
        _BLOT,
        _RINSE_COLD,
        TreatmentStep(
            instruction="Soak in warm water with an oxygen-bleach powder for an hour.",
            because="Oxygen bleach breaks the colour down without stripping most dyes.",
            temperature_c=40,
            bleach=BleachUse.OXYGEN,
        ),
        _WASH,
    ]


def _stubborn() -> list[TreatmentStep]:
    """The default, and the one most likely to be refused on a delicate."""
    return [
        _BLOT,
        TreatmentStep(
            instruction="Soak in hot water with household bleach for 20 minutes.",
            because="The general-purpose answer for a mark that will not shift.",
            temperature_c=60,
            bleach=BleachUse.CHLORINE,
        ),
        _WASH,
    ]


_PROTEIN_WORDS = ("blood", "egg", "milk", "dairy", "sweat", "yoghurt", "yogurt")
_GREASY_WORDS = ("oil", "grease", "butter", "make-up", "makeup", "lipstick", "chain")
_TANNIN_WORDS = ("wine", "tea", "coffee", "juice", "berry", "berries", "cola")


class FakeStainAdviser:
    """Answers from the substance's words alone, and always the same way."""

    @property
    def name(self) -> str:
        return "fake"

    async def advise(
        self,
        request: StainAdviceRequest,
        image: ScanImage | None = None,
    ) -> StainAdviceResponse:
        substance = request.substance.lower()

        if any(word in substance for word in _PROTEIN_WORDS):
            steps, identified = _protein(), "a protein stain"
        elif any(word in substance for word in _GREASY_WORDS):
            steps, identified = _greasy(), "a greasy stain"
        elif any(word in substance for word in _TANNIN_WORDS):
            steps, identified = _tannin(), "a tannin stain"
        else:
            steps, identified = _stubborn(), None

        return StainAdviceResponse(steps=steps, identified_as=identified)
