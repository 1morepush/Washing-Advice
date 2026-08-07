"""Reconciling what several stages saw.

The resolution rule must match the Dart core's `Confident.resolve` exactly. If
the two ever diverged, the same inputs would produce different advice depending
on which side happened to merge them — a bug that would be near-impossible to
reproduce from a user's report.
"""

from __future__ import annotations

import pytest

from app.schemas.care import Agitation, CareConstraint, TumbleDryHeat, WashMethod
from app.schemas.common import Confident, Provenance, resolve
from app.schemas.scan import CareTagScanResult, GarmentScanResult
from app.schemas.wardrobe import ItemType
from app.services.ai.base import StageOutcome
from app.services.ai.merger import ConfidenceMerger


def belief(value: str, confidence: float, source: Provenance) -> Confident[str]:
    return Confident[str](value=value, confidence=confidence, source=source)


class TestResolve:
    def test_stronger_provenance_wins_even_when_less_confident(self) -> None:
        """A hesitant care label still beats a breezy guess from a photograph."""
        label = belief("cold", 0.55, Provenance.TAG_SCAN)
        guess = belief("hot", 0.99, Provenance.AI_INFERENCE)

        assert resolve(label, guess).value == "cold"
        assert resolve(guess, label).value == "cold"

    def test_confidence_breaks_ties_within_one_provenance(self) -> None:
        weak = belief("a", 0.4, Provenance.AI_INFERENCE)
        strong = belief("b", 0.8, Provenance.AI_INFERENCE)

        assert resolve(weak, strong).value == "b"
        assert resolve(strong, weak).value == "b"

    def test_a_user_correction_beats_everything(self) -> None:
        user = belief("user", 0.1, Provenance.USER_EDITED)
        label = belief("label", 1.0, Provenance.TAG_SCAN)

        assert resolve(user, label).value == "user"

    def test_the_provenance_order_matches_the_dart_core(self) -> None:
        # The ordering is load-bearing on both sides; pin it explicitly.
        assert [p.value for p in Provenance] == [
            "fallbackDefault",
            "aiInference",
            "careRule",
            "tagScan",
            "userEdited",
        ]
        ranks = [p.resolution_rank for p in Provenance]
        assert ranks == sorted(ranks)

    def test_attenuation_lowers_confidence_without_changing_provenance(self) -> None:
        original = belief("x", 0.8, Provenance.TAG_SCAN)
        attenuated = original.attenuated_by(0.5)

        assert attenuated.confidence == pytest.approx(0.4)
        assert attenuated.source is Provenance.TAG_SCAN

    def test_attenuation_is_clamped(self) -> None:
        original = belief("x", 0.8, Provenance.TAG_SCAN)
        assert original.attenuated_by(5.0).confidence == pytest.approx(0.8)
        assert original.attenuated_by(-1.0).confidence == 0.0


class TestGarmentMerge:
    merger = ConfidenceMerger()

    def test_no_results_merges_to_nothing(self) -> None:
        assert self.merger.merge_garment([]) is None

    def test_fields_resolve_independently(self) -> None:
        """A stage contributes only the part it actually knew.

        One stage reads the brand confidently but guesses the type; the other is
        the reverse. The merge must take the good half of each.
        """
        first = GarmentScanResult(
            type=Confident[ItemType](
                value=ItemType.HOODIE, confidence=0.4, source=Provenance.AI_INFERENCE
            ),
            brand=belief("Nike", 0.95, Provenance.AI_INFERENCE),
        )
        second = GarmentScanResult(
            type=Confident[ItemType](
                value=ItemType.SWEATER, confidence=0.9, source=Provenance.AI_INFERENCE
            ),
            brand=belief("Adidas", 0.2, Provenance.AI_INFERENCE),
        )

        merged = self.merger.merge_garment([StageOutcome("a", first), StageOutcome("b", second)])

        assert merged is not None
        assert merged.type.value is ItemType.SWEATER
        assert merged.brand is not None and merged.brand.value == "Nike"

    def test_a_field_only_one_stage_saw_survives(self) -> None:
        with_text = GarmentScanResult(
            type=Confident[ItemType](
                value=ItemType.T_SHIRT, confidence=0.9, source=Provenance.AI_INFERENCE
            ),
            distinguishing_text="Nirvana",
        )
        without = GarmentScanResult(
            type=Confident[ItemType](
                value=ItemType.T_SHIRT, confidence=0.9, source=Provenance.AI_INFERENCE
            )
        )

        merged = self.merger.merge_garment(
            [StageOutcome("a", without), StageOutcome("b", with_text)]
        )

        assert merged is not None
        assert merged.distinguishing_text == "Nirvana"


class TestCareTagMerge:
    merger = ConfidenceMerger()

    def test_no_input_merges_to_nothing(self) -> None:
        assert self.merger.merge_care_tag([]) is None

    def test_a_partial_reading_fills_gaps_in_a_complete_one(self) -> None:
        """The on-device-OCR scenario the pipeline is built for.

        One stage recovers the temperature while the symbols stay illegible;
        the model stage reads the symbols but not the small print. Both halves
        must survive.
        """
        partial = StageOutcome("ocr", partial_care=CareConstraint(max_temp_c=30), confidence=0.8)
        model = StageOutcome(
            "gemini",
            CareTagScanResult(
                instructions=CareConstraint(
                    method=WashMethod.MACHINE,
                    tumble_dry_heat=TumbleDryHeat.LOW,
                ),
                confidence=0.9,
            ),
            confidence=0.9,
        )

        merged = self.merger.merge_care_tag([partial, model])

        assert merged is not None
        assert merged.instructions.max_temp_c == 30
        assert merged.instructions.method is WashMethod.MACHINE
        assert merged.instructions.tumble_dry_heat is TumbleDryHeat.LOW

    def test_an_unstated_field_stays_unstated(self) -> None:
        """Merging must never invent a value nobody read.

        The absent field is what tells the core to fall back to its rule table.
        """
        merged = self.merger.merge_care_tag(
            [
                StageOutcome(
                    "a",
                    CareTagScanResult(
                        instructions=CareConstraint(method=WashMethod.MACHINE),
                        confidence=0.9,
                    ),
                    confidence=0.9,
                )
            ]
        )

        assert merged is not None
        assert merged.instructions.tumble_dry_allowed is None
        assert "tumbleDryAllowed" not in merged.instructions.to_wire()

    def test_the_better_reading_wins_the_unreadable_count(self) -> None:
        """A stage that decoded a symbol another could not has read more."""
        worse = StageOutcome(
            "a",
            CareTagScanResult(
                instructions=CareConstraint(), confidence=0.5, unreadable_symbol_count=3
            ),
            confidence=0.5,
        )
        better = StageOutcome(
            "b",
            CareTagScanResult(
                instructions=CareConstraint(), confidence=0.8, unreadable_symbol_count=1
            ),
            confidence=0.8,
        )

        merged = self.merger.merge_care_tag([worse, better])
        assert merged is not None
        assert merged.unreadable_symbol_count == 1

    def test_partials_alone_still_produce_a_reading(self) -> None:
        merged = self.merger.merge_care_tag(
            [
                StageOutcome(
                    "ocr",
                    partial_care=CareConstraint(agitation=Agitation.NORMAL),
                    confidence=0.6,
                )
            ]
        )

        assert merged is not None
        assert merged.instructions.agitation is Agitation.NORMAL
        assert merged.confidence == pytest.approx(0.6)


class TestCareConstraintMerge:
    def test_the_receiver_wins_on_a_field_both_state(self) -> None:
        first = CareConstraint(max_temp_c=30)
        second = CareConstraint(max_temp_c=40)

        assert first.merged_with(second).max_temp_c == 30

    def test_warnings_accumulate_from_both_sides(self) -> None:
        from app.schemas.care import CareWarning

        first = CareConstraint(warnings=[CareWarning.WASH_INSIDE_OUT])
        second = CareConstraint(warnings=[CareWarning.USE_MESH_BAG])

        merged = first.merged_with(second)
        assert set(merged.warnings) == {
            CareWarning.WASH_INSIDE_OUT,
            CareWarning.USE_MESH_BAG,
        }

    def test_states_nothing_detects_an_empty_constraint(self) -> None:
        assert CareConstraint().states_nothing
        assert not CareConstraint(max_temp_c=30).states_nothing

    def test_stated_fields_lists_only_what_was_set(self) -> None:
        constraint = CareConstraint(method=WashMethod.HAND, max_temp_c=30)
        assert constraint.stated_fields == {"method", "max_temp_c"}
