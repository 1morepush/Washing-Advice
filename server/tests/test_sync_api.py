"""The sync endpoints.

The store's behaviour is covered in `test_sync_store.py` against both
implementations. What is tested here is the HTTP layer: that the credential is
actually required, that one token cannot read another's wardrobe, and that the
round trip a device performs works end to end.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import pytest
from fastapi.testclient import TestClient

from app.api.v1.dependencies import reset_wiring
from app.main import create_app

# Long enough to satisfy the minimum, and obviously fake.
TOKEN_A = "a" * 40
TOKEN_B = "b" * 40


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    # ':memory:' keeps the suite from writing a database file, and exercises
    # the branch a disposable deployment would use.
    monkeypatch.setenv("SYNC_DB_PATH", ":memory:")
    monkeypatch.setenv("SYNC_ENABLED", "true")
    reset_wiring()
    with TestClient(create_app()) as test_client:
        yield test_client
    reset_wiring()


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def push(
    client: TestClient,
    token: str,
    *,
    items: list[dict[str, Any]] | None = None,
    events: list[dict[str, Any]] | None = None,
):
    return client.post(
        "/v1/sync",
        json={"items": items or [], "events": events or []},
        headers=auth(token),
    )


class TestTheCredential:
    def test_pulling_without_a_token_is_refused(self, client: TestClient) -> None:
        response = client.get("/v1/sync")
        assert response.status_code == 401
        assert response.headers["www-authenticate"] == "Bearer"

    def test_pushing_without_a_token_is_refused(self, client: TestClient) -> None:
        assert client.post("/v1/sync", json={"items": [], "events": []}).status_code == 401

    def test_a_short_token_is_refused(self, client: TestClient) -> None:
        # The length is enforced rather than recommended: this token is the only
        # thing between a wardrobe and whoever guesses it.
        response = client.get("/v1/sync", headers=auth("short"))
        assert response.status_code == 401

    def test_a_non_bearer_scheme_is_refused(self, client: TestClient) -> None:
        response = client.get("/v1/sync", headers={"Authorization": f"Basic {TOKEN_A}"})
        assert response.status_code == 401

    def test_the_token_is_never_echoed_back(self, client: TestClient) -> None:
        # Error bodies end up in logs, bug reports and screenshots. A bearer
        # credential must not be in any of them, not even partially.
        response = client.get("/v1/sync", headers=auth("short"))
        assert "short" not in response.text

    def test_the_scheme_is_matched_case_insensitively(self, client: TestClient) -> None:
        # RFC 7235 says the scheme is case-insensitive, and some clients send
        # 'bearer'. Refusing those would be a bug that only shows up in the field.
        response = client.get("/v1/sync", headers={"Authorization": f"bearer {TOKEN_A}"})
        assert response.status_code == 200


class TestIsolation:
    def test_one_token_cannot_read_another_wardrobe(self, client: TestClient) -> None:
        push(client, TOKEN_A, items=[{"id": "mine"}])

        seen = client.get("/v1/sync", headers=auth(TOKEN_B)).json()
        assert seen["items"] == []


class TestTheRoundTrip:
    def test_pushing_then_pulling_returns_what_was_sent(self, client: TestClient) -> None:
        item = {"id": "tee", "name": "White tee", "composition": {"cotton": 100}}
        event = {"id": "e1", "type": "worn", "itemId": "tee"}

        pushed = push(client, TOKEN_A, items=[item], events=[event])
        assert pushed.status_code == 200
        assert pushed.json()["items"] == 1
        assert pushed.json()["events"] == 1

        pulled = client.get("/v1/sync", headers=auth(TOKEN_A)).json()
        assert pulled["items"] == [item]
        assert pulled["events"] == [event]

    def test_the_response_carries_the_cursor_to_store(self, client: TestClient) -> None:
        accepted_at = push(client, TOKEN_A, items=[{"id": "tee"}]).json()["acceptedAt"]

        # Exactly what a device does next: pull with the cursor it was given.
        pulled = client.get("/v1/sync", params={"since": accepted_at}, headers=auth(TOKEN_A))
        assert pulled.status_code == 200
        assert [i["id"] for i in pulled.json()["items"]] == ["tee"]

    def test_a_later_cursor_returns_nothing(self, client: TestClient) -> None:
        push(client, TOKEN_A, items=[{"id": "tee"}])
        server_time = client.get("/v1/sync", headers=auth(TOKEN_A)).json()["serverTime"]

        later = client.get("/v1/sync", params={"since": server_time}, headers=auth(TOKEN_A)).json()
        assert later["items"] == []

    def test_an_empty_push_is_accepted(self, client: TestClient) -> None:
        # The common case for a device with nothing new. It must not be an error.
        assert push(client, TOKEN_A).status_code == 200

    def test_pushing_the_same_item_twice_stores_one(self, client: TestClient) -> None:
        push(client, TOKEN_A, items=[{"id": "tee", "name": "old"}])
        push(client, TOKEN_A, items=[{"id": "tee", "name": "new"}])

        items = client.get("/v1/sync", headers=auth(TOKEN_A)).json()["items"]
        assert items == [{"id": "tee", "name": "new"}]


class TestLimits:
    def test_an_oversized_push_is_refused_rather_than_truncated(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # Truncating would let the client advance its cursor past records the
        # server never stored — data loss neither side could detect.
        monkeypatch.setenv("MAX_SYNC_RECORDS_PER_REQUEST", "3")
        reset_wiring()

        with TestClient(create_app()) as fresh:
            response = push(fresh, TOKEN_A, items=[{"id": f"i{n}"} for n in range(5)])

        assert response.status_code == 413


class TestWhenSyncIsOff:
    def test_the_endpoints_report_absence_rather_than_refusal(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # 404 rather than 401: a deployment that does not offer sync should not
        # advertise that it has wardrobes behind a credential.
        monkeypatch.setenv("SYNC_ENABLED", "false")
        reset_wiring()

        with TestClient(create_app()) as off:
            assert off.get("/v1/sync", headers=auth(TOKEN_A)).status_code == 404

        reset_wiring()
