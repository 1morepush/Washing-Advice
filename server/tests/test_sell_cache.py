"""The price-search cache: what it keys on, how long it keeps, and what it refuses.

Time is a number the test moves, not something it sleeps through, so the lifetime
is tested at its edge rather than near it.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from app.schemas.selling import (
    ExcludedCounts,
    PriceSearch,
    PriceSearchRequest,
    PriceSearchStatus,
    SearchQueries,
)
from app.services.selling.cache import PriceCache, cache_key
from tests.selling_support import price_request


class Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def search(status: PriceSearchStatus = PriceSearchStatus.OK, **fields: Any) -> PriceSearch:
    values: dict[str, Any] = {
        "status": status,
        "queries": SearchQueries(depop="nike crewneck", retail="nike crew"),
        "comparables": [],
        "retail": [],
        "excluded": ExcludedCounts.zero(),
        "searched_at": datetime(2026, 10, 17, 14, 5, tzinfo=UTC),
    }
    values.update(fields)
    return PriceSearch(**values)


def request(**overrides: Any) -> PriceSearchRequest:
    return PriceSearchRequest.model_validate(price_request(**overrides))


def cache(clock: Clock | None = None, *, ttl: float = 100, entries: int = 3) -> PriceCache:
    return PriceCache(ttl_seconds=ttl, max_entries=entries, clock=clock or Clock())


class TestWhatASearchIs:
    def test_the_same_request_is_the_same_search(self) -> None:
        assert cache_key(request()) == cache_key(request())

    def test_case_and_spacing_do_not_make_a_different_search(self) -> None:
        loud = request(
            queries={
                "depop": "  NIKE   Vintage Crewneck   sweatshirt GREY ",
                "retail": "nike CLUB fleece crew   sweatshirt grey",
            },
            brand="  NIKE ",
        )

        assert cache_key(loud) == cache_key(request())

    def test_a_different_phrase_is_a_different_search(self) -> None:
        other_depop = request(queries={"depop": "Nike crewneck", "retail": "x crew"})
        same_depop = request(
            queries={"depop": "Nike vintage crewneck sweatshirt grey", "retail": "different"}
        )

        assert cache_key(other_depop) != cache_key(request())
        assert cache_key(same_depop) != cache_key(request())

    def test_a_different_item_type_is_a_different_search(self) -> None:
        assert cache_key(request(itemType="hoodie")) != cache_key(request())

    def test_a_different_brand_is_a_different_search(self) -> None:
        assert cache_key(request(brand="Adidas")) != cache_key(request())

    def test_no_brand_is_not_the_same_as_a_brand(self) -> None:
        assert cache_key(request(brand=None)) != cache_key(request())

    def test_the_title_and_the_colours_do_not_make_a_different_search(self) -> None:
        # They decide nothing about what the search finds, and correcting a
        # typo in a title should not cost two more searches.
        edited = request(title="Nike crewneck, corrected", colors=["Grey", "Navy"])

        assert cache_key(edited) == cache_key(request())


class TestRemembering:
    def test_an_answer_is_given_back(self) -> None:
        kept = cache()
        found = search()

        kept.put(cache_key(request()), found)

        assert kept.get(cache_key(request())) is found

    def test_an_answer_for_another_search_is_not(self) -> None:
        kept = cache()
        kept.put(cache_key(request()), search())

        assert kept.get(cache_key(request(brand="Adidas"))) is None

    def test_an_empty_cache_has_nothing(self) -> None:
        assert cache().get(cache_key(request())) is None
        assert len(cache()) == 0

    def test_the_time_it_was_searched_is_kept(self) -> None:
        kept = cache()
        found = search(searched_at=datetime(2026, 10, 17, 9, 30, tzinfo=UTC))
        kept.put(cache_key(request()), found)

        again = kept.get(cache_key(request()))

        assert again is not None
        assert again.searched_at == datetime(2026, 10, 17, 9, 30, tzinfo=UTC)


class TestForgetting:
    def test_an_answer_lasts_for_its_lifetime(self) -> None:
        clock = Clock()
        kept = cache(clock, ttl=100)
        kept.put(cache_key(request()), search())

        clock.now += 99.9

        assert kept.get(cache_key(request())) is not None

    def test_and_not_a_moment_longer(self) -> None:
        clock = Clock()
        kept = cache(clock, ttl=100)
        kept.put(cache_key(request()), search())

        clock.now += 100

        assert kept.get(cache_key(request())) is None

    def test_an_expired_answer_is_removed_not_just_hidden(self) -> None:
        clock = Clock()
        kept = cache(clock, ttl=100)
        kept.put(cache_key(request()), search())

        clock.now += 500
        kept.get(cache_key(request()))

        assert len(kept) == 0

    def test_putting_clears_out_what_has_expired(self) -> None:
        clock = Clock()
        kept = cache(clock, ttl=100, entries=10)
        kept.put(cache_key(request(brand="A")), search())
        kept.put(cache_key(request(brand="B")), search())
        clock.now += 150

        kept.put(cache_key(request(brand="C")), search())

        assert len(kept) == 1

    def test_the_lifetime_runs_from_when_it_was_stored_not_when_it_was_last_read(self) -> None:
        clock = Clock()
        kept = cache(clock, ttl=100)
        kept.put(cache_key(request()), search())

        clock.now += 60
        assert kept.get(cache_key(request())) is not None
        clock.now += 60

        assert kept.get(cache_key(request())) is None

    def test_a_search_stored_again_starts_its_lifetime_again(self) -> None:
        clock = Clock()
        kept = cache(clock, ttl=100)
        kept.put(cache_key(request()), search())
        clock.now += 90
        kept.put(cache_key(request()), search())
        clock.now += 90

        assert kept.get(cache_key(request())) is not None


class TestBeingBounded:
    def test_the_oldest_is_dropped_first(self) -> None:
        kept = cache(entries=2)
        for brand in ("A", "B", "C"):
            kept.put(cache_key(request(brand=brand)), search())

        assert kept.get(cache_key(request(brand="A"))) is None
        assert kept.get(cache_key(request(brand="B"))) is not None
        assert kept.get(cache_key(request(brand="C"))) is not None
        assert len(kept) == 2

    def test_what_was_read_lately_is_kept_over_what_was_not(self) -> None:
        kept = cache(entries=2)
        kept.put(cache_key(request(brand="A")), search())
        kept.put(cache_key(request(brand="B")), search())

        kept.get(cache_key(request(brand="A")))
        kept.put(cache_key(request(brand="C")), search())

        assert kept.get(cache_key(request(brand="A"))) is not None
        assert kept.get(cache_key(request(brand="B"))) is None

    def test_it_never_holds_more_than_it_was_told_to(self) -> None:
        kept = cache(entries=5)

        for number in range(50):
            kept.put(cache_key(request(brand=f"Brand{number}")), search())

        assert len(kept) == 5


class TestOnlyAnswersAreKept:
    def test_a_search_that_failed_is_never_stored(self) -> None:
        kept = cache()

        for status in (
            PriceSearchStatus.UNAVAILABLE,
            PriceSearchStatus.QUOTA_EXCEEDED,
            PriceSearchStatus.NOT_CONFIGURED,
        ):
            kept.put(cache_key(request()), search(status, searched_at=None))

        assert len(kept) == 0
        assert kept.get(cache_key(request())) is None

    def test_a_search_that_found_nothing_is_an_answer(self) -> None:
        kept = cache()
        kept.put(cache_key(request()), search())

        assert kept.get(cache_key(request())) is not None


class TestBeingTurnedOff:
    def test_a_lifetime_of_nothing_keeps_nothing(self) -> None:
        kept = cache(ttl=0)

        kept.put(cache_key(request()), search())

        assert not kept.enabled
        assert len(kept) == 0
        assert kept.get(cache_key(request())) is None

    def test_a_size_of_nothing_keeps_nothing(self) -> None:
        kept = cache(entries=0)

        kept.put(cache_key(request()), search())

        assert not kept.enabled
        assert len(kept) == 0

    def test_otherwise_it_is_on(self) -> None:
        assert cache().enabled
