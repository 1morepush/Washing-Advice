"""Application settings.

Everything the service needs to run, resolved once from the environment. The
Gemini key is deliberately optional: the whole service must be runnable, and its
full test suite passable, with no credentials at all — otherwise nobody can work
on it without a billing account, and CI cannot run.
"""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field
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
    gemini_model: str = "gemini-2.5-flash"
    gemini_base_url: str = "https://generativelanguage.googleapis.com/v1beta"
    gemini_timeout_seconds: float = 45.0

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

    # --- Request limits -----------------------------------------------------

    max_image_bytes: int = Field(
        default=8 * 1024 * 1024,
        description="Per-image cap. Phone cameras produce 3-6 MB JPEGs.",
    )
    max_images_per_request: int = 6

    @property
    def gemini_configured(self) -> bool:
        return bool(self.gemini_api_key)

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
            "knowledge_cache_enabled": self.knowledge_cache_enabled,
            "sufficient_confidence": self.sufficient_confidence,
        }


@lru_cache
def get_settings() -> Settings:
    """Cached settings, so the environment is read once per process."""
    return Settings()
