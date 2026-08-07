"""The orchestrator's behaviour.

The claims worth testing here are about *ordering and stopping*, not about any
individual stage: cheap stages run first, an expensive stage is skipped when a
cheap one already answered well enough, and one stage failing does not take the
pipeline down with it.
"""

from __future__ import annotations

import pytest

from app.schemas.care import Agitation, CareConstraint, WashMethod
from app.schemas.common import Confident, Provenance
from app.schemas.scan import CareTagScanResult, GarmentScanResult, ScanKind
from app.schemas.wardrobe import ItemType
from app.services.ai.base import (
    ProviderError,
    ScanRequest,
    StageCost,
    StageOutcome,
)
from app.services.ai.pipeline import VisionPipeline
from tests.conftest import scan_image


class RecordingStage:
    """A stage that records that it ran and returns whatever it was given."""

    def __init__(
        self,
        name: str,
        cost: StageCost,
        *,
        result: object = None,
        confidence: float = 0.0,
        partial_care: CareConstraint | None = None,
        handles_kinds: set[ScanKind] | None = None,
        raises: bool = False,
    ) -> None:
        self._name = name
        self._cost = cost
        self._result = result
        self._confidence = confidence
        self._partial = partial_care
        self._kinds = handles_kinds
        self._raises = raises
        self.ran = False

    @property
    def name(self) -> str:
        return self._name

    @property
    def cost(self) -> StageCost:
        return self._cost

    def handles(self, kind: ScanKind) -> bool:
        return self._kinds is None or kind in self._kinds

    async def run(self, request: ScanRequest) -> StageOutcome:
        self.ran = True
        if self._raises:
            return StageOutcome.declined(self._name, "unavailable")
        return StageOutcome(
            stage=self._name,
            result=self._result,  # type: ignore[arg-type]
            confidence=self._confidence,
            partial_care=self._partial,
        )


def garment(confidence: float = 0.9) -> GarmentScanResult:
    return GarmentScanResult(
        type=Confident[ItemType](
            value=ItemType.HOODIE,
            confidence=confidence,
            source=Provenance.AI_INFERENCE,
        )
    )


def care(confidence: float, **fields: object) -> CareTagScanResult:
    return CareTagScanResult(
        instructions=CareConstraint(**fields),  # type: ignore[arg-type]
        confidence=confidence,
    )


async def test_stages_run_in_cost_order_regardless_of_registration() -> None:
    expensive = RecordingStage("network", StageCost.NETWORK, result=garment())
    free = RecordingStage("memory", StageCost.FREE)
    on_device = RecordingStage("device", StageCost.ON_DEVICE)

    pipeline = VisionPipeline([expensive, on_device, free])

    assert pipeline.stage_names == ["memory", "device", "network"]

    outcome = await pipeline.run(ScanRequest(kind=ScanKind.GARMENT, images=[scan_image()]))
    assert outcome.diagnostics.stages_run == ["memory", "device", "network"]


async def test_a_confident_cheap_answer_skips_the_expensive_stage() -> None:
    """The whole point of the design: memory answers, the model is never called."""
    free = RecordingStage("memory", StageCost.FREE, result=garment(), confidence=0.95)
    expensive = RecordingStage("network", StageCost.NETWORK, result=garment())

    pipeline = VisionPipeline([free, expensive], sufficient_confidence=0.85)
    outcome = await pipeline.run(ScanRequest(kind=ScanKind.GARMENT, images=[scan_image()]))

    assert free.ran
    assert not expensive.ran
    assert outcome.diagnostics.stages_run == ["memory"]
    assert outcome.diagnostics.served_from_cache is True


async def test_an_unconfident_cheap_answer_still_consults_the_model() -> None:
    free = RecordingStage("memory", StageCost.FREE, result=garment(0.4), confidence=0.4)
    expensive = RecordingStage("network", StageCost.NETWORK, result=garment(0.95), confidence=0.95)

    pipeline = VisionPipeline([free, expensive], sufficient_confidence=0.85)
    outcome = await pipeline.run(ScanRequest(kind=ScanKind.GARMENT, images=[scan_image()]))

    assert expensive.ran
    assert outcome.diagnostics.stages_run == ["memory", "network"]
    # The more confident belief wins the merge.
    assert isinstance(outcome.result, GarmentScanResult)
    assert outcome.result.type.confidence == 0.95


async def test_a_stage_that_declines_does_not_stop_the_pipeline() -> None:
    broken = RecordingStage("broken", StageCost.FREE, raises=True)
    working = RecordingStage("network", StageCost.NETWORK, result=garment(), confidence=0.9)

    pipeline = VisionPipeline([broken, working])
    outcome = await pipeline.run(ScanRequest(kind=ScanKind.GARMENT, images=[scan_image()]))

    assert outcome.answered
    assert outcome.diagnostics.stage_answered == "network"


async def test_stages_that_do_not_handle_a_kind_are_skipped() -> None:
    care_only = RecordingStage("care-only", StageCost.FREE, handles_kinds={ScanKind.CARE_TAG})
    general = RecordingStage("general", StageCost.NETWORK, result=garment(), confidence=0.9)

    pipeline = VisionPipeline([care_only, general])
    outcome = await pipeline.run(ScanRequest(kind=ScanKind.GARMENT, images=[scan_image()]))

    assert not care_only.ran
    assert outcome.diagnostics.stages_run == ["general"]


async def test_a_partial_care_reading_does_not_stop_the_pipeline() -> None:
    """A partial reading is a contribution, not a conclusion.

    The point of gathering one is to let a later stage fill what it could not,
    so a high-confidence *partial* must never short-circuit the way a
    high-confidence complete answer does.
    """
    partial = RecordingStage(
        "ocr",
        StageCost.ON_DEVICE,
        partial_care=CareConstraint(max_temp_c=30),
        confidence=0.99,
    )
    model = RecordingStage(
        "network",
        StageCost.NETWORK,
        result=care(0.9, method=WashMethod.MACHINE, agitation=Agitation.NORMAL),
        confidence=0.9,
    )

    pipeline = VisionPipeline([partial, model], sufficient_confidence=0.85)
    outcome = await pipeline.run(ScanRequest(kind=ScanKind.CARE_TAG, images=[scan_image()]))

    assert model.ran, "a partial reading must not short-circuit the pipeline"
    assert isinstance(outcome.result, CareTagScanResult)
    # Both contributions survive: the temperature from OCR, the method from the model.
    assert outcome.result.instructions.max_temp_c == 30
    assert outcome.result.instructions.method is WashMethod.MACHINE


async def test_no_stage_answering_yields_no_result() -> None:
    pipeline = VisionPipeline([RecordingStage("nothing", StageCost.FREE)])
    outcome = await pipeline.run(ScanRequest(kind=ScanKind.GARMENT, images=[scan_image()]))

    assert outcome.result is None
    assert not outcome.answered
    assert outcome.diagnostics.stage_answered is None


async def test_a_request_with_no_images_is_rejected_at_construction() -> None:
    with pytest.raises(ValueError, match="at least one image"):
        ScanRequest(kind=ScanKind.GARMENT, images=[])


def test_scan_image_repr_never_contains_the_bytes() -> None:
    """repr() reaches tracebacks and log lines, where image data must not go."""
    image = scan_image()
    rendered = repr(image)

    assert "image/png" in rendered
    assert str(image.size_bytes) in rendered
    assert "\\x89PNG" not in rendered
    assert str(image.data) not in rendered


def test_provider_error_names_the_provider() -> None:
    error = ProviderError("gemini", "boom")
    assert error.provider == "gemini"
    assert "gemini: boom" in str(error)
