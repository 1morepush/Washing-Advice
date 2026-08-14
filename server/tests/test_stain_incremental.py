"""The partial-JSON reader, fed the way a stream actually feeds it.

A step is emitted on its closing brace and never before. That rule is what
keeps a half-received step off the screen, and a half-received step is not a
cosmetic problem: `temperatureC` missing reads as "this step names no
temperature", which is exactly what the safety check treats as harmless.
"""

from __future__ import annotations

from app.services.stains.incremental import complete_steps, identified_as

_DOC = (
    '{"identifiedAs": "red wine", "steps": ['
    '{"instruction": "Blot it, do not rub.", "because": "Rubbing spreads it.",'
    ' "temperatureC": null, "bleach": null, "isMachineWash": false,'
    ' "abrades": false},'
    '{"instruction": "Flush from behind with cold water.", "because": null,'
    ' "temperatureC": 20, "bleach": null, "isMachineWash": false,'
    ' "abrades": false}'
    "]}"
)


def _feed(document: str, size: int) -> list[list[dict[str, object]]]:
    """What the reader sees after each chunk of `size` characters."""
    return [complete_steps(document[:end]) for end in range(size, len(document) + size, size)]


class TestCompleteSteps:
    def test_nothing_before_the_array_opens(self) -> None:
        assert complete_steps('{"identifiedAs": "red wi') == []

    def test_nothing_from_a_half_written_step(self) -> None:
        partial = '{"steps": [{"instruction": "Flush from behind with co'
        assert complete_steps(partial) == []

    def test_a_step_appears_on_its_closing_brace(self) -> None:
        upto = _DOC.index("}") + 1
        assert len(complete_steps(_DOC[:upto])) == 1

    def test_the_whole_document_yields_every_step(self) -> None:
        steps = complete_steps(_DOC)
        assert [step["instruction"] for step in steps] == [
            "Blot it, do not rub.",
            "Flush from behind with cold water.",
        ]

    def test_the_count_never_goes_backwards(self) -> None:
        # The caller emits the tail it has not sent yet, so a reader that ever
        # returned fewer would re-send steps the user has already started on.
        for size in (1, 3, 7, 64):
            counts = [len(seen) for seen in _feed(_DOC, size)]
            assert counts == sorted(counts), f"chunk size {size}"
            assert counts[-1] == 2

    def test_a_brace_inside_an_instruction_is_text(self) -> None:
        # Structure is only structure outside a string. Getting this wrong
        # would close a step early and emit one missing its checkable fields.
        document = (
            '{"steps": [{"instruction": "Use a {tiny} amount of detergent",'
            ' "isMachineWash": false, "abrades": true}]}'
        )
        steps = complete_steps(document)
        assert len(steps) == 1
        assert steps[0]["abrades"] is True

    def test_an_escaped_quote_does_not_end_the_string(self) -> None:
        document = (
            '{"steps": [{"instruction": "Dab with a 3\\" square of cloth",'
            ' "isMachineWash": false, "abrades": false}]}'
        )
        steps = complete_steps(document)
        assert len(steps) == 1
        assert steps[0]["instruction"] == 'Dab with a 3" square of cloth'

    def test_a_field_after_the_array_is_not_read_as_a_step(self) -> None:
        document = _DOC[: _DOC.rindex("]")] + '], "identifiedAs": "red wine"}'
        assert len(complete_steps(document)) == 2


class TestIdentifiedAs:
    def test_absent_until_its_closing_quote(self) -> None:
        assert identified_as('{"identifiedAs": "red wi') is None

    def test_read_as_soon_as_it_is_complete(self) -> None:
        assert identified_as('{"identifiedAs": "red wine", "steps": [') == "red wine"

    def test_an_escaped_quote_is_unescaped(self) -> None:
        assert identified_as('{"identifiedAs": "a \\"greasy\\" mark"}') == 'a "greasy" mark'

    def test_null_is_not_a_name(self) -> None:
        # The schema allows null, and the pattern only matches a quoted value,
        # so this must simply not match rather than yield the string "null".
        assert identified_as('{"identifiedAs": null, "steps": []}') is None
