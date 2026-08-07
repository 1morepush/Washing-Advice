"""The provider registry — the plugin seam.

Providers register by name; the pipeline is assembled from names in
configuration. Swapping Gemini for another model, or running a local model in
development and a hosted one in production, becomes a config change rather than
an edit to any call site.
"""

from __future__ import annotations

from collections.abc import Callable

from app.services.ai.base import VisionProvider

ProviderFactory = Callable[[], VisionProvider]


class ProviderRegistry:
    """Maps provider names to factories.

    Factories rather than instances, so a provider that holds a network client
    is constructed only when actually selected. Importing a provider module must
    never open a connection or require an API key.
    """

    def __init__(self) -> None:
        self._factories: dict[str, ProviderFactory] = {}

    def register(self, name: str, factory: ProviderFactory) -> None:
        if name in self._factories:
            raise ValueError(f"provider {name!r} is already registered")
        self._factories[name] = factory

    def create(self, name: str) -> VisionProvider:
        try:
            factory = self._factories[name]
        except KeyError:
            available = ", ".join(sorted(self._factories)) or "none"
            raise KeyError(f"unknown vision provider {name!r}; registered: {available}") from None
        return factory()

    def is_registered(self, name: str) -> bool:
        return name in self._factories

    @property
    def names(self) -> list[str]:
        return sorted(self._factories)


registry = ProviderRegistry()
"""The process-wide registry.

Populated by importing `app.services.ai.providers`, which registers every
provider for its side effects.
"""
