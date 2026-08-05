"""The vision pipeline.

Runs stages in cost order and stops as soon as the answer is good enough. That
single rule produces the behaviour we actually want:

    memory (FREE)  →  on-device (ON_DEVICE)  →  cloud model (NETWORK)

A cached label reading costs nothing and answers immediately. An on-device OCR
pass — not yet built — would run next and, if it read the label cleanly, the
expensive model is never called. Only when the cheap stages fall short does the
request reach the network.

Today only the cache and cloud stages are registered, so most scans reach the
model. Nothing about that is special-cased: adding the middle stage is a
registration, not a rewrite.
"""

from __future__ import annotations

import time
from dataclasses import dataclass

from app.schemas.scan import ScanDiagnostics, ScanKind
from app.services.ai.base import (
    ScanRequest,
    ScanResult,
    StageCost,
    StageOutcome,
    VisionStage,
)
from app.services.ai.merger import ConfidenceMerger


@dataclass(frozen=True, slots=True)
class PipelineResult:
    """A scan answer plus how it was reached."""

    result: ScanResult | None
    diagnostics: ScanDiagnostics
    outcomes: list[StageOutcome]

    @property
    def answered(self) -> bool:
        return self.result is not None


class VisionPipeline:
    """Orchestrates stages to answer a scan request."""

    def __init__(
        self,
        stages: list[VisionStage],
        *,
        merger: ConfidenceMerger | None = None,
        sufficient_confidence: float = 0.85,
    ) -> None:
        # Sorted by cost so the cheapest useful answer wins. Python's sort is
        # stable, so equally-priced stages keep their registration order, which
        # lets a caller express a preference between two of the same cost.
        self._stages = sorted(stages, key=lambda stage: stage.cost)
        self._merger = merger or ConfidenceMerger()
        self._sufficient = sufficient_confidence

    @property
    def stage_names(self) -> list[str]:
        return [stage.name for stage in self._stages]

    async def run(self, request: ScanRequest) -> PipelineResult:
        started = time.perf_counter()
        outcomes: list[StageOutcome] = []
        stages_run: list[str] = []
        answered_by: str | None = None
        from_cache = False

        for stage in self._stages:
            if not stage.handles(request.kind):
                continue

            stages_run.append(stage.name)
            outcome = await stage.run(request)
            outcomes.append(outcome)

            if not outcome.contributed:
                continue

            if answered_by is None and outcome.answered:
                answered_by = stage.name
                from_cache = stage.cost is StageCost.FREE

            # Stop only on a complete answer. A partial care reading is a
            # contribution, not a conclusion — the point of gathering it is to
            # let a later stage fill what it could not.
            if outcome.answered and outcome.confidence >= self._sufficient:
                break

        merged = self._merge(request.kind, outcomes)

        return PipelineResult(
            result=merged,
            diagnostics=ScanDiagnostics(
                stages_run=stages_run,
                stage_answered=answered_by,
                served_from_cache=from_cache,
                elapsed_ms=int((time.perf_counter() - started) * 1000),
            ),
            outcomes=outcomes,
        )

    def _merge(self, kind: ScanKind, outcomes: list[StageOutcome]) -> ScanResult | None:
        match kind:
            case ScanKind.GARMENT:
                return self._merger.merge_garment(outcomes)
            case ScanKind.CARE_TAG:
                return self._merger.merge_care_tag(outcomes)
            case ScanKind.PILE:
                return self._merger.merge_pile(outcomes)
