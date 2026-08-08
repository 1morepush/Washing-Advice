"""Configuration is read from a web form, and forms produce untidy values.

Both normalisations here exist because of real production failures. A
`VISION_PROVIDER` that picked up a stray word reported "unknown vision
provider", and a `GEMINI_MODEL` carrying the `models/` prefix that Google's own
documentation shows produced a bare `HTTP 404` — a service that looked broken
when the dashboard looked right.
"""

from __future__ import annotations

import pytest

from app.config import Settings


class TestWhitespace:
    """A trailing space is invisible in a dashboard field and survives paste."""

    @pytest.mark.parametrize("raw", ["gemini", " gemini", "gemini ", "  gemini  ", "\tgemini\n"])
    def test_the_provider_name_is_trimmed(self, raw: str) -> None:
        assert Settings(vision_provider=raw).vision_provider == "gemini"

    def test_the_model_name_is_trimmed(self) -> None:
        # A space here becomes %20 in the request path and returns a 404.
        assert Settings(gemini_model="  gemini-3.6-flash  ").gemini_model == "gemini-3.6-flash"

    def test_the_base_url_is_trimmed(self) -> None:
        settings = Settings(gemini_base_url=" https://example.test/v1beta ")
        assert settings.gemini_base_url == "https://example.test/v1beta"


class TestModelPrefix:
    """`models/gemini-3.6-flash` is how Google names its own models."""

    @pytest.mark.parametrize(
        "raw",
        ["gemini-3.6-flash", "models/gemini-3.6-flash", " models/gemini-3.6-flash "],
    )
    def test_the_prefix_is_accepted_and_removed(self, raw: str) -> None:
        # The request path supplies `models/` itself, so keeping it here would
        # double it and produce .../models/models/gemini-3.6-flash -> 404.
        assert Settings(gemini_model=raw).gemini_model == "gemini-3.6-flash"

    def test_a_name_merely_containing_models_is_untouched(self) -> None:
        """Only a leading prefix is a mistake; the word elsewhere is a name."""
        assert Settings(gemini_model="my-models-tuned").gemini_model == "my-models-tuned"

    def test_the_default_is_already_bare(self) -> None:
        assert Settings().gemini_model == "gemini-3.6-flash"
