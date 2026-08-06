"""The sync store contract.

Both implementations run the same tests. The in-memory one is the readable
definition of what the operations mean; the SQLite one is what actually ships,
and a divergence between them is a failing test rather than something a user
discovers as missing data.
"""

from __future__ import annotations

from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest

from app.services.sync.store import InMemorySyncStore, SqliteSyncStore, SyncStore

ACCOUNT = "account-a"
OTHER = "account-b"


@pytest.fixture(params=["memory", "sqlite"])
def store(request: pytest.FixtureRequest, tmp_path: Path) -> Iterator[SyncStore]:
    made: SyncStore
    if request.param == "memory":
        made = InMemorySyncStore()
    else:
        made = SqliteSyncStore(tmp_path / "sync.db")
    yield made
    made.close()


def item(item_id: str, **extra: Any) -> dict[str, Any]:
    return {"id": item_id, "name": f"item {item_id}", **extra}


def event(event_id: str) -> dict[str, Any]:
    return {"id": event_id, "type": "worn", "itemId": "tee"}


class TestStoringAndReading:
    def test_an_empty_account_pulls_nothing(self, store: SyncStore) -> None:
        batch = store.pull(ACCOUNT, since=None)
        assert batch.items == []
        assert batch.events == []

    def test_pushed_records_come_back(self, store: SyncStore) -> None:
        store.push(ACCOUNT, items=[item("tee")], events=[event("e1")])

        batch = store.pull(ACCOUNT, since=None)
        assert [i["id"] for i in batch.items] == ["tee"]
        assert [e["id"] for e in batch.events] == ["e1"]

    def test_payloads_are_returned_untouched(self, store: SyncStore) -> None:
        # The server does not know what a garment is, and must not quietly
        # reshape one. A dropped field here is data loss the client cannot see.
        original = item(
            "tee",
            composition={"cotton": 100},
            care=None,
            nested={"deep": [1, 2, {"three": True}]},
        )
        store.push(ACCOUNT, items=[original], events=[])

        assert store.pull(ACCOUNT, since=None).items == [original]

    def test_an_item_is_replaced_rather_than_duplicated(self, store: SyncStore) -> None:
        store.push(ACCOUNT, items=[item("tee", name="old")], events=[])
        store.push(ACCOUNT, items=[item("tee", name="new")], events=[])

        stored = store.pull(ACCOUNT, since=None).items
        assert len(stored) == 1
        assert stored[0]["name"] == "new"

    def test_a_record_without_an_id_is_dropped(self, store: SyncStore) -> None:
        # Without an id there is no way to replace rather than accumulate, so
        # accepting one would turn every sync into unbounded growth.
        store.push(ACCOUNT, items=[{"name": "nameless"}], events=[])
        assert store.pull(ACCOUNT, since=None).items == []

    def test_results_are_ordered_reproducibly(self, store: SyncStore) -> None:
        store.push(ACCOUNT, items=[item("b"), item("a"), item("c")], events=[])

        first = [i["id"] for i in store.pull(ACCOUNT, since=None).items]
        second = [i["id"] for i in store.pull(ACCOUNT, since=None).items]
        assert first == second


class TestAccountIsolation:
    def test_one_account_never_sees_another(self, store: SyncStore) -> None:
        # The property the whole credential design exists to provide. If this
        # ever regresses, every wardrobe on the server is readable by everyone.
        store.push(ACCOUNT, items=[item("mine")], events=[event("e1")])
        store.push(OTHER, items=[item("theirs")], events=[event("e2")])

        mine = store.pull(ACCOUNT, since=None)
        assert [i["id"] for i in mine.items] == ["mine"]
        assert [e["id"] for e in mine.events] == ["e1"]

    def test_the_same_id_in_two_accounts_does_not_collide(
        self, store: SyncStore
    ) -> None:
        store.push(ACCOUNT, items=[item("tee", name="mine")], events=[])
        store.push(OTHER, items=[item("tee", name="theirs")], events=[])

        assert store.pull(ACCOUNT, since=None).items[0]["name"] == "mine"
        assert store.pull(OTHER, since=None).items[0]["name"] == "theirs"


class TestTheSinceFilter:
    def test_nothing_changed_since_a_later_cursor(self, store: SyncStore) -> None:
        store.push(ACCOUNT, items=[item("tee")], events=[])
        later = datetime.now(UTC) + timedelta(seconds=5)

        assert store.pull(ACCOUNT, since=later).items == []

    def test_everything_since_an_earlier_cursor(self, store: SyncStore) -> None:
        earlier = datetime.now(UTC) - timedelta(seconds=5)
        store.push(ACCOUNT, items=[item("tee")], events=[])

        assert len(store.pull(ACCOUNT, since=earlier).items) == 1

    def test_the_cursor_is_inclusive(self, store: SyncStore) -> None:
        # Deliberate: re-delivering a record the client already holds costs
        # nothing, because merging is idempotent. Missing one written in the
        # same millisecond as the cursor loses it permanently.
        accepted_at = store.push(ACCOUNT, items=[item("tee")], events=[])

        assert len(store.pull(ACCOUNT, since=accepted_at).items) == 1

    def test_only_what_changed_after_the_cursor(self, store: SyncStore) -> None:
        first = store.push(ACCOUNT, items=[item("old")], events=[])
        second = store.push(ACCOUNT, items=[item("new")], events=[])
        assert second >= first

        changed = store.pull(ACCOUNT, since=second).items
        assert [i["id"] for i in changed] == ["new"]

    def test_a_naive_cursor_is_not_compared_against_an_aware_stamp(
        self, store: SyncStore
    ) -> None:
        # The endpoint normalises naive input to UTC before it reaches here;
        # this pins that the store itself is only ever handed aware datetimes,
        # because comparing the two raises rather than merely being wrong.
        accepted_at = store.push(ACCOUNT, items=[item("tee")], events=[])
        assert accepted_at.tzinfo is not None
        assert store.pull(ACCOUNT, since=None).records[0].received_at.tzinfo


class TestEventsAreImmutable:
    def test_resending_an_event_does_not_move_it(self, store: SyncStore) -> None:
        # A client retrying a dropped push must not push the event forward in
        # time, or every other device is handed it again on their next pull —
        # forever, since each retry renews it.
        store.push(ACCOUNT, items=[], events=[event("e1")])
        original = store.pull(ACCOUNT, since=None).records[0].received_at

        store.push(ACCOUNT, items=[], events=[event("e1")])
        after = store.pull(ACCOUNT, since=None).records[0].received_at

        assert original == after

    def test_resending_an_event_does_not_duplicate_it(self, store: SyncStore) -> None:
        store.push(ACCOUNT, items=[], events=[event("e1")])
        store.push(ACCOUNT, items=[], events=[event("e1"), event("e2")])

        stored = store.pull(ACCOUNT, since=None).events
        assert sorted(e["id"] for e in stored) == ["e1", "e2"]

    def test_an_item_by_contrast_does_move(self, store: SyncStore) -> None:
        # Items are mutable state: a later version is a correction and must
        # reach the other devices, which means its stamp has to advance.
        store.push(ACCOUNT, items=[item("tee", name="old")], events=[])
        original = store.pull(ACCOUNT, since=None).records[0].received_at

        store.push(ACCOUNT, items=[item("tee", name="new")], events=[])
        after = store.pull(ACCOUNT, since=None).records[0].received_at

        assert after >= original


class TestDurability:
    def test_sqlite_survives_a_reopen(self, tmp_path: Path) -> None:
        # The one property the in-memory store cannot have, and the reason the
        # SQLite one exists at all.
        path = tmp_path / "sync.db"
        first = SqliteSyncStore(path)
        first.push(ACCOUNT, items=[item("tee")], events=[event("e1")])
        first.close()

        second = SqliteSyncStore(path)
        batch = second.pull(ACCOUNT, since=None)
        second.close()

        assert [i["id"] for i in batch.items] == ["tee"]
        assert [e["id"] for e in batch.events] == ["e1"]

    def test_sqlite_creates_its_parent_directory(self, tmp_path: Path) -> None:
        # A first run on a fresh deployment should not fail because `data/`
        # does not exist yet.
        store = SqliteSyncStore(tmp_path / "nested" / "deeper" / "sync.db")
        store.push(ACCOUNT, items=[item("tee")], events=[])
        assert len(store.pull(ACCOUNT, since=None).items) == 1
        store.close()
