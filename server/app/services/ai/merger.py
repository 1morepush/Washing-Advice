"""Combining what several stages saw.

When two stages both have an opinion about a field — an on-device OCR pass and a
cloud model reading the same care label — the results have to be reconciled. The
rule mirrors the Dart core's `Confident.resolve`: stronger provenance wins
outright, and confidence breaks ties within the same provenance.

That symmetry matters. If the server merged one way and the app another, the
same inputs would produce different advice depending on where the merge ran.
"""

from __future__ import annotations

from typing import TypeVar

from app.schemas.common import Confident, resolve
from app.schemas.scan import CareTagScanResult, GarmentScanResult, PileScanResult
from app.services.ai.base import StageOutcome

T = TypeVar("T")


def _merge_optional(a: Confident[T] | None, b: Confident[T] | None) -> Confident[T] | None:
    """Resolves two optional beliefs, keeping whichever exists."""
    if a is None:
        return b
    if b is None:
        return a
    return resolve(a, b)


class ConfidenceMerger:
    """Folds stage outcomes into one answer."""

    def merge_garment(self, outcomes: list[StageOutcome]) -> GarmentScanResult | None:
        """Merges garment scans field by field.

        Each field resolves independently, so a stage that reads the brand
        confidently but only guesses at fibre content contributes just the part
        it actually knew.
        """
        results = [
            outcome.result for outcome in outcomes if isinstance(outcome.result, GarmentScanResult)
        ]
        if not results:
            return None

        merged = results[0]
        for candidate in results[1:]:
            merged = GarmentScanResult(
                type=resolve(merged.type, candidate.type),
                colors=_merge_optional(merged.colors, candidate.colors),
                composition=_merge_optional(merged.composition, candidate.composition),
                brand=_merge_optional(merged.brand, candidate.brand),
                pattern=_merge_optional(merged.pattern, candidate.pattern),
                sleeve_length=_merge_optional(merged.sleeve_length, candidate.sleeve_length),
                fit=_merge_optional(merged.fit, candidate.fit),
                style_cut=_merge_optional(merged.style_cut, candidate.style_cut),
                seasons=merged.seasons or candidate.seasons,
                suggested_name=merged.suggested_name or candidate.suggested_name,
                distinguishing_text=(merged.distinguishing_text or candidate.distinguishing_text),
            )
        return merged

    def merge_care_tag(self, outcomes: list[StageOutcome]) -> CareTagScanResult | None:
        """Merges care-label readings, including partial ones.

        Partials matter more here than anywhere else: an on-device OCR stage may
        recover the fibre percentages while the wash symbols stay illegible, and
        a later stage then fills only what is still missing. Earlier stages win
        on any field both state, because the pipeline runs them in order of
        increasing cost and a cheaper stage that was confident enough to answer
        has already proved itself.
        """
        results = [
            outcome.result for outcome in outcomes if isinstance(outcome.result, CareTagScanResult)
        ]
        partials = [o.partial_care for o in outcomes if o.partial_care is not None]

        if not results and not partials:
            return None

        if not results:
            instructions = partials[0]
            for extra in partials[1:]:
                instructions = instructions.merged_with(extra)
            return CareTagScanResult(
                instructions=instructions,
                confidence=max(
                    (o.confidence for o in outcomes if o.partial_care is not None),
                    default=0.0,
                ),
            )

        merged = results[0]
        instructions = merged.instructions
        for extra in partials:
            instructions = instructions.merged_with(extra)

        for candidate in results[1:]:
            instructions = instructions.merged_with(candidate.instructions)
            merged = CareTagScanResult(
                instructions=instructions,
                confidence=max(merged.confidence, candidate.confidence),
                composition=_merge_optional(merged.composition, candidate.composition),
                symbols_found=sorted({*merged.symbols_found, *candidate.symbols_found}),
                # The lower count is the better reading: a stage that decoded a
                # symbol another could not has genuinely left less unread.
                unreadable_symbol_count=min(
                    merged.unreadable_symbol_count,
                    candidate.unreadable_symbol_count,
                ),
                raw_text=merged.raw_text or candidate.raw_text,
            )

        if instructions != merged.instructions:
            merged = merged.model_copy(update={"instructions": instructions})
        return merged

    def merge_pile(self, outcomes: list[StageOutcome]) -> PileScanResult | None:
        """Takes the first real pile answer.

        Pile detections are positional, so combining two stages would mean
        resolving overlapping boxes rather than reconciling fields — a different
        problem, and one worth solving only once a second pile-capable stage
        actually exists.
        """
        for outcome in outcomes:
            if isinstance(outcome.result, PileScanResult):
                return outcome.result
        return None
