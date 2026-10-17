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


class TestTheSearchKey:
    """The Tavily key is typed into the same dashboard, and picks up the same mess."""

    @pytest.mark.parametrize(
        "raw",
        ["tvly-abc", " tvly-abc", "tvly-abc ", "  tvly-abc  ", "\ttvly-abc\n"],
    )
    def test_the_key_is_trimmed(self, raw: str) -> None:
        # Untrimmed, a pasted newline goes into the Authorization header and
        # every search reads as "key rejected" while the dashboard looks right.
        assert Settings(tavily_api_key=raw).tavily_api_key == "tvly-abc"

    @pytest.mark.parametrize("raw", ["", "   ", "\n"])
    def test_a_blank_key_is_no_key(self, raw: str) -> None:
        # An unset dashboard field arrives as "", which must not count as
        # configured and make a call that can only fail.
        settings = Settings(tavily_api_key=raw)

        assert settings.tavily_api_key is None
        assert not settings.tavily_configured

    def test_there_is_no_key_by_default(self) -> None:
        settings = Settings()

        assert settings.tavily_api_key is None
        assert not settings.tavily_configured

    def test_a_key_is_configured(self) -> None:
        assert Settings(tavily_api_key="tvly-abc").tavily_configured

    def test_the_key_is_read_from_the_environment(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("TAVILY_API_KEY", " tvly-from-the-dashboard\n")

        assert Settings().tavily_api_key == "tvly-from-the-dashboard"

    def test_the_summary_says_whether_it_is_set_and_never_what_it_is(self) -> None:
        summary = Settings(tavily_api_key="tvly-very-secret").describe()

        assert summary["tavily_configured"] is True
        assert "tvly-very-secret" not in str(summary)

    def test_the_summary_says_when_it_is_not_set(self) -> None:
        assert Settings().describe()["tavily_configured"] is False

    def test_the_key_stays_out_of_the_settings_repr(self) -> None:
        # The other way a key reaches a log: the whole settings object, in a
        # traceback or an f-string.
        settings = Settings(tavily_api_key="tvly-very-secret")

        assert "tvly-very-secret" not in repr(settings)
        assert "tvly-very-secret" not in str(settings)


class TestTheSearchDefaults:
    def test_the_service_address_is_trimmed(self) -> None:
        settings = Settings(tavily_base_url=" https://search.example.test ")

        assert settings.tavily_base_url == "https://search.example.test"

    def test_the_defaults_are_the_documented_ones(self) -> None:
        settings = Settings()

        assert settings.tavily_base_url == "https://api.tavily.com"
        assert settings.tavily_timeout_seconds == 20.0
        # Six hours, and 200 answers: a listing reopened this evening should
        # not spend two more of the month's free searches.
        assert settings.price_search_cache_seconds == 6 * 60 * 60
        assert settings.price_search_cache_entries == 200

    def test_the_cache_can_be_turned_off(self) -> None:
        settings = Settings(price_search_cache_seconds=0, price_search_cache_entries=0)

        assert settings.price_search_cache_seconds == 0
        assert settings.price_search_cache_entries == 0

    def test_a_negative_lifetime_is_refused(self) -> None:
        with pytest.raises(ValueError):
            Settings(price_search_cache_seconds=-1)
