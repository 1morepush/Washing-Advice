"""The request limit on the AI endpoints.

The limiter takes an injected clock, so window expiry is tested by moving the
clock rather than by sleeping.
"""

from __future__ import annotations

import pytest
from fastapi import Request
from fastapi.testclient import TestClient

from app.api.v1.dependencies import reset_wiring
from app.core.request_limit import (
    DAY,
    UNKNOWN_CLIENT,
    RequestLimiter,
    client_key,
    parse_forwarded_for,
)
from app.main import create_app


class Clock:
    def __init__(self) -> None:
        self.now = 1_000.0

    def __call__(self) -> float:
        return self.now


def limiter(clock: Clock, **overrides: int) -> RequestLimiter:
    settings = {"per_minute": 0, "per_day": 0, "global_per_day": 0, "max_clients": 100}
    settings.update(overrides)
    return RequestLimiter(clock=clock, **settings)


class TestPerClient:
    def test_allows_up_to_the_minute_limit_then_refuses(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=3)

        assert all(lim.check("a").allowed for _ in range(3))
        verdict = lim.check("a")

        assert not verdict.allowed
        assert verdict.scope == "client"

    def test_clients_are_independent(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=1)

        assert lim.check("a").allowed
        assert not lim.check("a").allowed
        assert lim.check("b").allowed

    def test_the_window_slides_and_expires(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=2)
        lim.check("a")
        clock.now += 30
        lim.check("a")

        assert not lim.check("a").allowed
        clock.now += 31  # the first request is now 61s old
        assert lim.check("a").allowed
        assert not lim.check("a").allowed  # the one at +30 is still inside

    def test_retry_after_is_when_the_oldest_request_leaves_the_window(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=2)
        lim.check("a")
        clock.now += 20
        lim.check("a")
        clock.now += 10

        verdict = lim.check("a")

        assert verdict.retry_after == pytest.approx(30.0)  # 60 - 30s since the first

    def test_refusals_are_not_recorded_so_hammering_does_not_extend_the_wait(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=1)
        lim.check("a")
        for _ in range(50):
            clock.now += 1
            lim.check("a")

        clock.now += 10  # 60s after the one allowed request
        assert lim.check("a").allowed

    def test_the_daily_limit_applies_across_minutes(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=2, per_day=3)
        results = []
        for _ in range(4):
            results.append(lim.check("a").allowed)
            clock.now += 61

        assert results == [True, True, True, False]
        verdict = lim.check("a")
        assert verdict.retry_after == pytest.approx(DAY - 4 * 61)

    def test_the_longer_wait_wins_when_both_limits_are_hit(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=1, per_day=1)
        lim.check("a")
        clock.now += 5

        assert lim.check("a").retry_after == pytest.approx(DAY - 5)


class TestGlobal:
    def test_caps_everyone_together(self) -> None:
        clock = Clock()
        lim = limiter(clock, global_per_day=2)

        assert lim.check("a").allowed
        assert lim.check("b").allowed
        verdict = lim.check("c")

        assert not verdict.allowed
        assert verdict.scope == "global"

    def test_a_global_refusal_does_not_spend_the_clients_quota(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=1, global_per_day=1)
        lim.check("a")
        assert lim.check("b").scope == "global"

        clock.now += DAY + 1
        assert lim.check("b").allowed

    def test_a_client_refusal_does_not_spend_the_global_allowance(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=1, global_per_day=2)
        lim.check("a")
        for _ in range(10):
            assert lim.check("a").scope == "client"

        assert lim.check("b").allowed

    def test_resets_after_a_day(self) -> None:
        clock = Clock()
        lim = limiter(clock, global_per_day=1)
        lim.check("a")
        verdict = lim.check("b")
        assert verdict.retry_after == pytest.approx(DAY)

        clock.now += DAY + 1
        assert lim.check("b").allowed


class TestDisabled:
    def test_zero_means_no_limit(self) -> None:
        lim = limiter(Clock())

        assert not lim.enabled
        assert all(lim.check("a").allowed for _ in range(1_000))
        assert lim.tracked_clients == 0

    def test_each_limit_can_be_off_on_its_own(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_day=2)

        assert lim.check("a").allowed
        assert lim.check("a").allowed
        assert not lim.check("a").allowed


class TestMemoryBound:
    def test_tracked_clients_are_capped_and_the_oldest_evicted(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=1, max_clients=3)
        for name in ("a", "b", "c", "d"):
            lim.check(name)

        assert lim.tracked_clients == 3
        assert lim.check("a").allowed  # evicted, so it starts over
        assert not lim.check("d").allowed  # still tracked

    def test_a_recently_seen_client_is_kept(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_minute=1, max_clients=2)
        lim.check("a")
        lim.check("b")
        lim.check("a")  # refused, but seen again
        lim.check("c")  # evicts b, not a

        assert not lim.check("a").allowed

    def test_each_client_holds_at_most_the_daily_limit_of_timestamps(self) -> None:
        clock = Clock()
        lim = limiter(clock, per_day=5)
        for _ in range(500):
            lim.check("a")

        assert len(lim._clients["a"]) == 5


class TestForwardedFor:
    @pytest.mark.parametrize(
        ("header", "expected"),
        [
            ("203.0.113.7", "203.0.113.7"),
            ("203.0.113.7, 10.0.0.1, 10.0.0.2", "203.0.113.7"),
            ("  203.0.113.7  ,10.0.0.1", "203.0.113.7"),
            ("203.0.113.7:51234", "203.0.113.7"),
            ("2001:db8::1", "2001:db8::/64"),
            ("[2001:db8::1]:443", "2001:db8::/64"),
            ("2001:db8:0:0:1:2:3:4, 1.2.3.4", "2001:db8::/64"),
            ("::ffff:203.0.113.7", "203.0.113.7"),
        ],
    )
    def test_reads_the_first_address(self, header: str, expected: str) -> None:
        assert parse_forwarded_for(header) == expected

    def test_addresses_in_one_ipv6_prefix_share_a_key(self) -> None:
        assert parse_forwarded_for("2001:db8::1") == parse_forwarded_for("2001:db8::ffff")

    @pytest.mark.parametrize(
        "header",
        [None, "", "   ", ",1.2.3.4", "garbage", "999.1.1.1", "[2001:db8::1", "a:b:c", "1.2.3"],
    )
    def test_garbage_is_not_an_address(self, header: str | None) -> None:
        assert parse_forwarded_for(header) is None

    @staticmethod
    def _request(headers: dict[str, str], peer: str | None) -> Request:
        scope = {
            "type": "http",
            "headers": [(k.lower().encode(), v.encode()) for k, v in headers.items()],
            "client": (peer, 1234) if peer else None,
        }
        return Request(scope)

    def test_uses_the_header_when_trusted(self) -> None:
        request = self._request({"X-Forwarded-For": "203.0.113.7"}, "10.0.0.1")

        assert client_key(request, trust_forwarded_for=True) == "203.0.113.7"

    def test_ignores_the_header_when_not_trusted(self) -> None:
        request = self._request({"X-Forwarded-For": "203.0.113.7"}, "10.0.0.1")

        assert client_key(request, trust_forwarded_for=False) == "10.0.0.1"

    def test_falls_back_to_the_peer_on_garbage(self) -> None:
        request = self._request({"X-Forwarded-For": "garbage"}, "10.0.0.1")

        assert client_key(request, trust_forwarded_for=True) == "10.0.0.1"

    def test_with_no_address_at_all_everyone_shares_one_key(self) -> None:
        assert client_key(self._request({}, None), trust_forwarded_for=True) == UNKNOWN_CLIENT


@pytest.fixture
def limited(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    """An app with a per-minute limit of 2, per client, and nothing else."""
    monkeypatch.setenv("RATE_LIMIT_PER_MINUTE", "2")
    reset_wiring()
    return TestClient(create_app())


def _chat(client: TestClient, ip: str = "203.0.113.7") -> int:
    # An empty body: the limiter answers before validation does, so an allowed
    # request is a 422 and a refused one a 429, and no model is involved.
    return client.post("/v1/chat/ask", json={}, headers={"X-Forwarded-For": ip}).status_code


class TestOverTheWire:
    def test_refuses_with_a_429_in_the_error_envelope_and_retry_after(
        self, limited: TestClient
    ) -> None:
        assert [_chat(limited), _chat(limited)] == [422, 422]

        response = limited.post("/v1/chat/ask", json={}, headers={"X-Forwarded-For": "203.0.113.7"})

        assert response.status_code == 429
        body = response.json()
        assert body["error"] == "rate_limited"
        assert body["detail"] == "Too many requests from this network."
        assert body["hint"].startswith("Try again in about ")
        assert 1 <= int(response.headers["retry-after"]) <= 60

    def test_a_different_address_is_unaffected(self, limited: TestClient) -> None:
        for _ in range(3):
            _chat(limited, "203.0.113.7")

        assert _chat(limited, "198.51.100.9") == 422

    def test_the_limit_is_shared_across_ai_endpoints(self, limited: TestClient) -> None:
        _chat(limited)
        limited.post("/v1/style/outfits", json={}, headers={"X-Forwarded-For": "203.0.113.7"})

        assert _chat(limited) == 429

    def test_a_global_refusal_says_so(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("RATE_LIMIT_GLOBAL_PER_DAY", "1")
        reset_wiring()
        client = TestClient(create_app())
        _chat(client, "203.0.113.7")

        response = client.post("/v1/chat/ask", json={}, headers={"X-Forwarded-For": "198.51.100.9"})

        assert response.status_code == 429
        assert response.json()["detail"] == "The service has reached its daily limit."
        assert int(response.headers["retry-after"]) > 60

    def test_health_and_sync_are_exempt(self, limited: TestClient) -> None:
        for _ in range(5):
            _chat(limited)

        for _ in range(5):
            assert limited.get("/v1/health").status_code == 200
            assert limited.get("/v1/sync").status_code != 429
            assert limited.post("/v1/sync", json={}).status_code != 429

    def test_cutout_is_not_counted_against_the_ai_limit(self, limited: TestClient) -> None:
        # It has its own limit: a wardrobe-wide redo must not eat the scan
        # quota, and scans using theirs up must not refuse a cutout.
        for _ in range(5):
            _chat(limited)

        assert limited.post("/v1/image/cutout").status_code == 422

    def test_cutouts_have_their_own_limit(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("CUTOUT_RATE_LIMIT_PER_MINUTE", "2")
        reset_wiring()
        client = TestClient(create_app())
        headers = {"X-Forwarded-For": "203.0.113.7"}

        codes = [client.post("/v1/image/cutout", headers=headers).status_code for _ in range(3)]

        assert codes == [422, 422, 429]
        refused = client.post("/v1/image/cutout", headers=headers)
        assert int(refused.headers["retry-after"]) >= 1
        # Scans are unaffected by the cutout limit being spent.
        assert _chat(client) == 422

    def test_a_different_client_has_its_own_cutout_quota(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("CUTOUT_RATE_LIMIT_PER_MINUTE", "1")
        reset_wiring()
        client = TestClient(create_app())

        client.post("/v1/image/cutout", headers={"X-Forwarded-For": "203.0.113.7"})
        client.post("/v1/image/cutout", headers={"X-Forwarded-For": "203.0.113.7"})
        other = client.post("/v1/image/cutout", headers={"X-Forwarded-For": "198.51.100.9"})

        assert other.status_code == 422

    def test_a_forwarded_header_is_ignored_when_untrusted(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("RATE_LIMIT_PER_MINUTE", "1")
        monkeypatch.setenv("RATE_LIMIT_TRUST_FORWARDED_FOR", "false")
        reset_wiring()
        client = TestClient(create_app())
        _chat(client, "203.0.113.7")

        assert _chat(client, "198.51.100.9") == 429  # same socket peer

    def test_off_by_default_in_the_suite(self, client: TestClient) -> None:
        assert all(_chat(client) == 422 for _ in range(50))
