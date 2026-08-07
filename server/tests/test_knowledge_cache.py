"""The knowledge cache — what the system remembers, and what it refuses to."""

from __future__ import annotations

from app.schemas.care import CareConstraint, TumbleDryHeat, WashMethod
from app.schemas.scan import CareTagScanResult, ScanKind
from app.schemas.wardrobe import FabricComposition, Fiber, ItemType
from app.services.ai.base import ScanRequest
from app.services.ai.knowledge_cache import (
    InMemoryKnowledgeCache,
    KnowledgeCacheStage,
    brand_key,
    image_signature,
)
from tests.conftest import scan_image


def reading(*, complete: bool = True, confidence: float = 0.9) -> CareTagScanResult:
    return CareTagScanResult(
        instructions=CareConstraint(
            method=WashMethod.MACHINE,
            max_temp_c=30,
            tumble_dry_heat=TumbleDryHeat.LOW,
        ),
        confidence=confidence,
        unreadable_symbol_count=0 if complete else 2,
    )


async def test_remembers_and_returns_a_complete_reading() -> None:
    cache = InMemoryKnowledgeCache()
    signature = image_signature(scan_image(1))

    assert await cache.care_for_signature(signature) is None

    await cache.remember_care(signature, reading())
    remembered = await cache.care_for_signature(signature)

    assert remembered is not None
    assert remembered.instructions.max_temp_c == 30


async def test_refuses_to_remember_an_incomplete_reading() -> None:
    """Caching a poor scan would make it permanent.

    A reading that already admits it could not decode part of the label must not
    be cached, or the user is locked out of ever getting a better answer by
    taking a better photograph.
    """
    cache = InMemoryKnowledgeCache()
    signature = image_signature(scan_image(2))

    await cache.remember_care(signature, reading(complete=False))

    assert await cache.care_for_signature(signature) is None


async def test_different_images_do_not_collide() -> None:
    cache = InMemoryKnowledgeCache()
    first, second = image_signature(scan_image(1)), image_signature(scan_image(2))

    await cache.remember_care(first, reading())

    assert await cache.care_for_signature(first) is not None
    assert await cache.care_for_signature(second) is None


async def test_evicts_least_recently_used_entries() -> None:
    cache = InMemoryKnowledgeCache(max_entries=2)

    for index in range(3):
        await cache.remember_care(f"sig-{index}", reading())

    assert cache.size == 2
    assert await cache.care_for_signature("sig-0") is None
    assert await cache.care_for_signature("sig-2") is not None


async def test_reading_an_entry_keeps_it_alive() -> None:
    cache = InMemoryKnowledgeCache(max_entries=2)
    await cache.remember_care("a", reading())
    await cache.remember_care("b", reading())

    # Touch "a" so "b" becomes the least recently used.
    await cache.care_for_signature("a")
    await cache.remember_care("c", reading())

    assert await cache.care_for_signature("a") is not None
    assert await cache.care_for_signature("b") is None


class TestCompositionPrior:
    async def test_no_prior_without_observations(self) -> None:
        cache = InMemoryKnowledgeCache()
        assert await cache.composition_prior("Nike", ItemType.HOODIE) is None

    async def test_confidence_grows_with_consistent_observations(self) -> None:
        cache = InMemoryKnowledgeCache()
        blend = FabricComposition({Fiber.COTTON: 80, Fiber.POLYESTER: 20})

        await cache.observe_composition("Nike", ItemType.HOODIE, blend)
        after_one = await cache.composition_prior("Nike", ItemType.HOODIE)

        for _ in range(4):
            await cache.observe_composition("Nike", ItemType.HOODIE, blend)
        after_five = await cache.composition_prior("Nike", ItemType.HOODIE)

        assert after_one is not None and after_five is not None
        assert after_five.confidence > after_one.confidence
        # Never asserted as certain: a prior is a starting point, not a fact.
        assert after_five.confidence <= 0.8

    async def test_disagreement_lowers_confidence(self) -> None:
        cache = InMemoryKnowledgeCache()
        cotton = FabricComposition({Fiber.COTTON: 100})
        blend = FabricComposition({Fiber.COTTON: 80, Fiber.POLYESTER: 20})

        for _ in range(3):
            await cache.observe_composition("Uniqlo", ItemType.T_SHIRT, cotton)
        consistent = await cache.composition_prior("Uniqlo", ItemType.T_SHIRT)

        for _ in range(3):
            await cache.observe_composition("Uniqlo", ItemType.T_SHIRT, blend)
        mixed = await cache.composition_prior("Uniqlo", ItemType.T_SHIRT)

        assert consistent is not None and mixed is not None
        assert mixed.confidence < consistent.confidence

    async def test_returns_the_most_common_rather_than_an_average(self) -> None:
        """Averaging percentages would invent a blend nobody manufactures."""
        cache = InMemoryKnowledgeCache()
        cotton = FabricComposition({Fiber.COTTON: 100})
        blend = FabricComposition({Fiber.COTTON: 50, Fiber.POLYESTER: 50})

        for _ in range(3):
            await cache.observe_composition("Levi's", ItemType.JEANS, cotton)
        await cache.observe_composition("Levi's", ItemType.JEANS, blend)

        prior = await cache.composition_prior("Levi's", ItemType.JEANS)
        assert prior is not None
        assert prior.value.root == {Fiber.COTTON: 100}

    async def test_implausible_compositions_are_ignored(self) -> None:
        cache = InMemoryKnowledgeCache()
        # Totals nowhere near 100 — almost certainly a misread label.
        await cache.observe_composition(
            "Nike", ItemType.HOODIE, FabricComposition({Fiber.COTTON: 40})
        )
        assert await cache.composition_prior("Nike", ItemType.HOODIE) is None

    def test_brand_keys_are_case_and_space_insensitive(self) -> None:
        assert brand_key("  Nike ", ItemType.HOODIE) == brand_key("nike", ItemType.HOODIE)
        assert brand_key("Nike", ItemType.HOODIE) != brand_key("Nike", ItemType.T_SHIRT)


class TestCacheStage:
    def test_only_handles_care_tags(self) -> None:
        stage = KnowledgeCacheStage(InMemoryKnowledgeCache())

        assert stage.handles(ScanKind.CARE_TAG)
        # A garment photo varies too much between shots for a byte hash to hit,
        # and a pile is never the same twice — caching either is dead weight.
        assert not stage.handles(ScanKind.GARMENT)
        assert not stage.handles(ScanKind.PILE)

    async def test_declines_on_a_miss(self) -> None:
        stage = KnowledgeCacheStage(InMemoryKnowledgeCache())
        outcome = await stage.run(ScanRequest(kind=ScanKind.CARE_TAG, images=[scan_image()]))

        assert not outcome.answered
        assert "no cached reading" in outcome.notes[0]

    async def test_answers_on_a_hit(self) -> None:
        cache = InMemoryKnowledgeCache()
        image = scan_image(5)
        await cache.remember_care(image_signature(image), reading(confidence=0.93))

        stage = KnowledgeCacheStage(cache)
        outcome = await stage.run(ScanRequest(kind=ScanKind.CARE_TAG, images=[image]))

        assert outcome.answered
        assert outcome.confidence == 0.93
        assert "no model call" in outcome.notes[0]
