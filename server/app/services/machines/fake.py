"""A deterministic machine identifier, for tests and for running with no
credentials.

The same reasoning as `FakeVisionProvider`: derives its answer from a hash of
the brand and model text, so the same input always answers the same way and
different inputs answer differently — enough to exercise every caller without
a network call or an API key.
"""

from __future__ import annotations

import hashlib

from app.schemas.care import Agitation, TumbleDryHeat
from app.schemas.machines import (
    DryerProfile,
    DrynessControl,
    DryProgram,
    DryProgramKind,
    FabricClass,
    WasherProfile,
    WashProgram,
    WashProgramKind,
)


def _seed(brand: str, model: str) -> int:
    digest = hashlib.sha256(f"{brand}\0{model}".encode()).digest()
    return int.from_bytes(digest[:4], "big")


def _slug(brand: str, model: str) -> str:
    kept = "".join(ch.lower() if ch.isalnum() else "-" for ch in f"{brand}-{model}")
    return "-".join(part for part in kept.split("-") if part) or "machine"


class FakeMachineIdentifier:
    """Deterministic answers derived from the brand and model text."""

    @property
    def name(self) -> str:
        return "fake"

    async def identify_washer(self, brand: str, model: str) -> WasherProfile:
        seed = _seed(brand, model)
        profile_id = f"ai.washer.{_slug(brand, model)}"

        return WasherProfile(
            id=profile_id,
            brand=brand,
            model=model,
            capacity_kg=7.0 + (seed % 5),
            programs=[
                WashProgram(
                    id=f"{profile_id}.program-0",
                    display_name="Cotton",
                    kind=WashProgramKind.COTTON,
                    available_temps_c=[0, 30, 40, 60],
                    default_temp_c=40,
                    agitation=Agitation.NORMAL,
                    spin_speeds_rpm=[0, 600, 800, 1200],
                    suitable_for=[FabricClass.NORMAL, FabricClass.HEAVY],
                    typical_duration_minutes=120,
                ),
                WashProgram(
                    id=f"{profile_id}.program-1",
                    display_name="Delicates",
                    kind=WashProgramKind.DELICATES,
                    available_temps_c=[0, 20, 30],
                    default_temp_c=30,
                    agitation=Agitation.VERY_MILD,
                    spin_speeds_rpm=[0, 400, 600],
                    suitable_for=[FabricClass.DELICATE],
                    max_load_fraction=0.5,
                    typical_duration_minutes=55,
                ),
                WashProgram(
                    id=f"{profile_id}.program-2",
                    display_name="Quick Wash",
                    kind=WashProgramKind.QUICK,
                    available_temps_c=[0, 30],
                    default_temp_c=30,
                    agitation=Agitation.MILD,
                    spin_speeds_rpm=[0, 600, 800],
                    suitable_for=[FabricClass.NORMAL],
                    typical_duration_minutes=30,
                ),
            ],
            is_verified_model=False,
        )

    async def identify_dryer(self, brand: str, model: str) -> DryerProfile:
        seed = _seed(brand, model)
        profile_id = f"ai.dryer.{_slug(brand, model)}"

        return DryerProfile(
            id=profile_id,
            brand=brand,
            model=model,
            capacity_kg=7.0 + (seed % 4),
            programs=[
                DryProgram(
                    id=f"{profile_id}.program-0",
                    display_name="Normal",
                    kind=DryProgramKind.NORMAL,
                    available_heats=[TumbleDryHeat.LOW, TumbleDryHeat.MEDIUM, TumbleDryHeat.HIGH],
                    default_heat=TumbleDryHeat.MEDIUM,
                    suitable_for=[FabricClass.NORMAL, FabricClass.HEAVY],
                    typical_duration_minutes=60,
                ),
                DryProgram(
                    id=f"{profile_id}.program-1",
                    display_name="Delicates",
                    kind=DryProgramKind.DELICATES,
                    available_heats=[TumbleDryHeat.NO_HEAT, TumbleDryHeat.LOW],
                    default_heat=TumbleDryHeat.LOW,
                    suitable_for=[FabricClass.DELICATE],
                    max_load_fraction=0.5,
                    typical_duration_minutes=40,
                ),
                DryProgram(
                    id=f"{profile_id}.program-2",
                    display_name="Air Fluff",
                    kind=DryProgramKind.AIR_FLUFF,
                    available_heats=[TumbleDryHeat.NO_HEAT],
                    default_heat=TumbleDryHeat.NO_HEAT,
                    suitable_for=[FabricClass.DELICATE, FabricClass.NORMAL, FabricClass.HEAVY],
                    control=DrynessControl.TIMED,
                    typical_duration_minutes=20,
                ),
            ],
            is_verified_model=False,
        )
