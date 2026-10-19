"""Application settings.

Everything the service needs to run, resolved once from the environment. The
Gemini key is deliberately optional: the whole service must be runnable, and its
full test suite passable, with no credentials at all — otherwise nobody can work
on it without a billing account, and CI cannot run.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "washing-advice-server"
    debug: bool = False

    # --- Vision -------------------------------------------------------------

    vision_provider: str = Field(
        default="fake",
        description=(
            "Which registered provider to use. Defaults to 'fake' so the "
            "service starts and every test runs without credentials."
        ),
    )

    gemini_api_key: str | None = Field(
        default=None,
        description="Set to enable the Gemini provider. Never logged.",
    )
    # gemini-2.5-flash was the default until Google stopped issuing it to new
    # API keys — a deprecation on Google's side, not a name this app got
    # wrong; ai.google.dev/gemini-api/docs/latest-model names the current
    # generally-available replacement.
    gemini_model: str = "gemini-3.6-flash"
    gemini_base_url: str = "https://generativelanguage.googleapis.com/v1beta"
    gemini_timeout_seconds: float = 45.0

    @field_validator(
        "vision_provider",
        "gemini_model",
        "gemini_base_url",
        "tavily_base_url",
        mode="before",
    )
    @classmethod
    def _trim(cls, value: object) -> object:
        """Strips surrounding whitespace from values typed into a dashboard.

        These arrive from a web form, where a trailing space is invisible and
        survives a copy-paste. Untrimmed, `VISION_PROVIDER=" gemini"` misses an
        exact dict lookup and reports "unknown vision provider", and a space in
        the model name becomes `%20` in a URL and returns a 404 — both of which
        read as "the service is broken" rather than "there is a stray space".
        """
        return value.strip() if isinstance(value, str) else value

    @field_validator("gemini_model", mode="after")
    @classmethod
    def _bare_model_name(cls, value: str) -> str:
        """Accepts a model name with or without the `models/` prefix.

        Google's documentation and its own ListModels response both name models
        as `models/gemini-2.5-flash`, so that is the form anyone copying from
        either will paste. The request path already supplies `models/`, so the
        prefix would be doubled and the API answers 404 — naming a model that
        looks right in the dashboard and is wrong only in the URL.
        """
        return value.removeprefix("models/").strip("/")

    # --- Pipeline -----------------------------------------------------------

    sufficient_confidence: float = Field(
        default=0.85,
        ge=0.0,
        le=1.0,
        description=(
            "Confidence at which the pipeline stops and skips remaining, more expensive stages."
        ),
    )

    knowledge_cache_enabled: bool = True
    knowledge_cache_max_entries: int = 2_048

    # --- Sync ---------------------------------------------------------------

    sync_enabled: bool = Field(
        default=True,
        description=(
            "Serve the sync endpoints. Off makes them 404 rather than 401, so "
            "a deployment that does not offer sync does not advertise it."
        ),
    )

    sync_db_path: str = Field(
        default="data/sync.db",
        description="Where synced records are kept. ':memory:' for a disposable server.",
    )

    max_sync_records_per_request: int = Field(
        default=2_000,
        description=(
            "Cap on one push. Exceeding it is refused rather than truncated: a "
            "truncated push would advance the client's cursor past records the "
            "server never stored."
        ),
    )

    # --- Selling ------------------------------------------------------------

    tavily_api_key: str | None = Field(
        default=None,
        # Out of `repr()` as well as `describe()`: a settings object that ends
        # up in a log line, a traceback or a debugger pane would otherwise print
        # the key it was built to keep out of them.
        repr=False,
        description=(
            "Set to enable live prices in the Sell tab; free at tavily.com. "
            "Without it the price search answers 'notConfigured'. Never logged."
        ),
    )
    tavily_base_url: str = "https://api.tavily.com"
    tavily_timeout_seconds: float = Field(
        default=20.0,
        gt=0,
        description=(
            "Per search. Two run at once, so this is also the longest the "
            "search half of a price lookup can take."
        ),
    )

    price_search_cache_seconds: int = Field(
        default=6 * 60 * 60,
        ge=0,
        description=(
            "How long an answered price search is remembered. Every search "
            "spends free-allowance credits, and a listing is reopened far more "
            "often than the market for a grey sweatshirt moves. 0 turns it off."
        ),
    )
    price_search_cache_entries: int = Field(
        default=200,
        ge=0,
        description="How many answered searches are kept; the least recently used go first.",
    )

    @field_validator("tavily_api_key", mode="before")
    @classmethod
    def _trim_search_key(cls, value: object) -> object:
        """Trims the key, and reads a blank one as no key.

        A secret pasted into a dashboard picks up a newline or a trailing space
        as readily as anything else, and an untrimmed one goes into an
        `Authorization` header as a key the service has never issued: every
        search then reads as "the search key was rejected" while the dashboard
        looks right. A field left empty arrives as `""`, which would otherwise
        count as configured and make a call that can only fail.
        """
        if isinstance(value, str):
            return value.strip() or None
        return value

    # --- Request limits -----------------------------------------------------

    max_image_bytes: int = Field(
        default=8 * 1024 * 1024,
        description="Per-image cap. Phone cameras produce 3-6 MB JPEGs.",
    )
    max_images_per_request: int = 6

    # --- CORS -----------------------------------------------------------

    cors_allowed_origins: str = Field(
        default="https://1morepush.github.io",
        description=(
            "Comma-separated browser origins allowed to call this API. "
            "Local development origins (http://localhost:*) are always allowed "
            "in addition to this list."
        ),
    )

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_allowed_origins.split(",") if origin.strip()]

    @property
    def gemini_configured(self) -> bool:
        return bool(self.gemini_api_key)

    @property
    def tavily_configured(self) -> bool:
        return bool(self.tavily_api_key)

    def describe(self) -> dict[str, object]:
        """A safe-to-log summary.

        Reports whether a credential is present, never its value — this is the
        function that gets called on startup and in the health endpoint.
        """
        return {
            "app_name": self.app_name,
            "vision_provider": self.vision_provider,
            "gemini_configured": self.gemini_configured,
            "gemini_model": self.gemini_model if self.gemini_configured else None,
            "tavily_configured": self.tavily_configured,
            "knowledge_cache_enabled": self.knowledge_cache_enabled,
            "sufficient_confidence": self.sufficient_confidence,
        }


@lru_cache
def get_settings() -> Settings:
    """Cached settings, so the environment is read once per process."""
    return Settings()
