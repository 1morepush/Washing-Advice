"""Provider registration.

Importing this module registers every available provider. Nothing here
constructs a client or reads a credential — the registry holds factories, so a
provider that needs an API key fails only if it is actually selected.
"""

from __future__ import annotations

from app.services.ai.providers.fake import FakeVisionProvider
from app.services.ai.providers.gemini import GeminiVisionProvider
from app.services.ai.registry import registry


def register_all() -> None:
    """Registers the built-in providers, idempotently.

    Idempotent because tests build the application repeatedly in one process,
    and a second registration of the same name would otherwise raise.
    """
    if not registry.is_registered("fake"):
        registry.register("fake", FakeVisionProvider)
    if not registry.is_registered("gemini"):
        registry.register("gemini", GeminiVisionProvider.from_settings)


register_all()

__all__ = ["FakeVisionProvider", "GeminiVisionProvider", "register_all"]
