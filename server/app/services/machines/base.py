"""What it takes to identify a washer or dryer.

Mirrors `VisionProvider` in `services/ai/base.py` — a capability, kept
separate from any particular backend — but is not that same Protocol widened
to fit: identifying a machine takes two strings and produces a completely
different result shape, and `VisionProvider`'s three methods have no image to
give it. `FakeMachineIdentifier` and `GeminiMachineIdentifier` both satisfy
this structurally.
"""

from __future__ import annotations

from typing import Protocol, runtime_checkable

from app.schemas.machines import DryerProfile, WasherProfile


@runtime_checkable
class MachineIdentifier(Protocol):
    @property
    def name(self) -> str: ...

    async def identify_washer(self, brand: str, model: str) -> WasherProfile: ...

    async def identify_dryer(self, brand: str, model: str) -> DryerProfile: ...
