"""Bounds on the free text a model puts in somebody's wardrobe.

Reported from a real scan. A garment came back named with its actual name and
then the model talking to itself about JSON formatting until it ran out of
tokens — four hundred characters that filled the review screen and pushed every
other reading off the bottom of the phone.

Every other field a scan produces is checked by its own shape: an enum refuses
a value that is not one of its members, a confidence outside 0 to 1 fails. The
free-text fields had no shape at all, so whatever the model wrote was drawn on
a screen and written to a database.

What is tested here is the *shape of the repair* rather than the numbers. A
degenerate answer breaks at its tail and is correct at its head, so it is
trimmed rather than refused: refusing would throw away a good identification
over a bad string and cost the user the scan.
"""

from __future__ import annotations

from typing import Any

from app.schemas.limits import MAX_NAME, clamp
from app.schemas.scan import CareTagScanResult, GarmentScanResult

# The name that was actually returned, abbreviated only in the middle.
DEGENERATE = (
    "Black t-shirt with Koshi no Kanbai pocket print & petals graphic design "
    "pattern context details sample color code analysis complete output "
    "formatting standard strict mode syntax structure layout parsing clear "
    "summary validation success check finished payload result object format "
    "output payload JSON structure complete string result correctly formatted "
    "JSON string structure validate output string result strictly JSON "
    "formatted correctly standard payload array single object item parsed "
    "successfully properly encoded standard JSON format response output "
    "validated correctly schema compliant JSON string format valid standard "
    "payload result complete"
)


def _garment(**extra: Any) -> GarmentScanResult:
    fields: dict[str, Any] = {
        "type": {"value": "tShirt", "confidence": 0.9, "source": "aiInference"}
    }
    fields.update(extra)
    return GarmentScanResult.model_validate(fields)


class TestClamping:
    def test_a_short_value_is_left_exactly_alone(self) -> None:
        assert clamp("Grey Nike hoodie", MAX_NAME) == "Grey Nike hoodie"

    def test_a_long_value_is_cut(self) -> None:
        assert len(clamp(DEGENERATE, MAX_NAME) or "") <= MAX_NAME

    def test_it_cuts_at_a_word_boundary(self) -> None:
        # A name is going to sit in a text field the user may keep as it
        # stands. Cutting mid-word gives them something to tidy up.
        cut = clamp(DEGENERATE, MAX_NAME) or ""

        assert not cut.endswith(" ")
        assert DEGENERATE.startswith(cut)

    def test_the_head_of_a_runaway_is_the_real_answer(self) -> None:
        # Why this trims rather than refuses. The degeneration is at the tail;
        # the front of that string is the name somebody would have typed.
        cut = clamp(DEGENERATE, MAX_NAME) or ""

        assert cut.startswith("Black t-shirt with Koshi no Kanbai")
        assert "JSON" not in cut

    def test_no_ellipsis_is_added(self) -> None:
        # "Black tee…" is not a name, and a trailing character that has to be
        # deleted before the field is usable is this function making its own
        # mess to clean up.
        assert not (clamp(DEGENERATE, MAX_NAME) or "").endswith("…")

    def test_whitespace_only_becomes_nothing(self) -> None:
        # Rather than an empty string, which would reach the app as though the
        # model had said something.
        assert clamp("   ", MAX_NAME) is None

    def test_none_stays_none(self) -> None:
        assert clamp(None, MAX_NAME) is None

    def test_an_unbroken_run_is_still_cut(self) -> None:
        # No word boundary to find. It must still be bounded rather than
        # passed through because it could not be trimmed politely.
        run = "x" * 500

        assert len(clamp(run, MAX_NAME) or "") == MAX_NAME


class TestTheGarmentContract:
    def test_a_runaway_name_is_trimmed_at_the_boundary(self) -> None:
        # At the contract rather than in the Gemini provider, so it covers
        # every provider and holds where the app's trust in the field begins.
        result = _garment(suggestedName=DEGENERATE)

        assert result.suggested_name is not None
        assert len(result.suggested_name) <= MAX_NAME
        assert result.suggested_name.startswith("Black t-shirt")

    def test_an_ordinary_name_is_untouched(self) -> None:
        assert _garment(suggestedName="Grey Nike hoodie").suggested_name == ("Grey Nike hoodie")

    def test_a_runaway_brand_is_trimmed_and_keeps_its_confidence(self) -> None:
        result = _garment(brand={"value": DEGENERATE, "confidence": 0.7, "source": "aiInference"})

        assert result.brand is not None
        assert len(result.brand.value) <= 48
        assert result.brand.confidence == 0.7

    def test_a_blank_brand_becomes_no_brand(self) -> None:
        # Otherwise the item screen draws an empty chip.
        result = _garment(brand={"value": "   ", "confidence": 0.7, "source": "aiInference"})

        assert result.brand is None

    def test_printed_text_may_be_longer_than_a_name(self) -> None:
        # A slogan on a shirt genuinely runs longer than a name does. The
        # limits are set by what each field is for.
        slogan = "A" * 150
        result = _garment(distinguishingText=slogan)

        assert result.distinguishing_text == slogan

    def test_but_not_unbounded(self) -> None:
        result = _garment(distinguishingText=DEGENERATE * 5)

        assert len(result.distinguishing_text or "") <= 200


class TestTheCareTagContract:
    def _tag(self, **extra: Any) -> CareTagScanResult:
        fields: dict[str, Any] = {"instructions": {}, "confidence": 0.9}
        fields.update(extra)
        return CareTagScanResult.model_validate(fields)

    def test_a_runaway_country_is_trimmed(self) -> None:
        # This one is filtered and sorted on rather than merely displayed: a
        # runaway becomes a permanent row in the insights chart and an entry in
        # the filter sheet matching one garment forever.
        result = self._tag(
            countryOfOrigin={
                "value": DEGENERATE,
                "confidence": 0.8,
                "source": "tagScan",
            }
        )

        assert result.country_of_origin is not None
        assert len(result.country_of_origin.value) <= 56

    def test_a_real_country_survives_whole(self) -> None:
        # The longest UN member name is 56 characters, which is the limit.
        longest = "The United Kingdom of Great Britain and Northern Ireland"
        result = self._tag(
            countryOfOrigin={
                "value": longest,
                "confidence": 0.8,
                "source": "tagScan",
            }
        )

        assert result.country_of_origin is not None
        assert result.country_of_origin.value == longest

    def test_a_transcript_may_be_a_paragraph(self) -> None:
        # A real label is a paragraph, in three languages. This field is the
        # one that should not be held to a name's standard.
        label = "Wash at 30. " * 40
        result = self._tag(rawText=label)

        assert result.raw_text == label.strip()

    def test_but_not_a_novel(self) -> None:
        result = self._tag(rawText="x" * 10_000)

        assert len(result.raw_text or "") <= 2000
