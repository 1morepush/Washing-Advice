"""The search client: what it sends, what it keeps, and how each failure is named.

A search costs a credit from a free allowance and a key that must not leak, so
most of what is worth asserting is on the request side — one credit and not two,
the key in the header and nowhere else, the domains the policy says — and on the
failure side, where every way a search can go wrong has to become one of three
statuses and never an exception, a log line with the key in it, or a request that
was never needed.

Faked at the transport: the real client builds the real request.
"""

from __future__ import annotations

import logging
from typing import Any

import httpx
import pytest

from app.config import Settings
from app.schemas.selling import PriceSearchStatus
from app.services.selling.base import SearchError, SearchRequest, WebSearch
from app.services.selling.tavily import MAX_RAW_CONTENT_CHARS, TavilySearch
from tests.selling_support import KEY, Recorder, Tavily, answer, hit, status

DEPOP = SearchRequest(
    query="Nike vintage crewneck sweatshirt grey",
    include_domains=("depop.com",),
    max_results=10,
)
RETAIL = SearchRequest(
    query="Nike Club Fleece crew sweatshirt grey price",
    exclude_domains=("depop.com", "ebay.com"),
    max_results=8,
)


async def search(tavily: Tavily, request: SearchRequest = DEPOP, **settings: Any) -> Any:
    return await tavily.search(**settings).search(request)


class TestTheRequest:
    async def test_it_posts_json_to_the_search_endpoint(self) -> None:
        tavily = Tavily(answer())

        await search(tavily)

        request = tavily.requests[0]
        assert request.method == "POST"
        assert str(request.url) == "https://api.tavily.com/search"
        assert request.headers["content-type"] == "application/json"

    async def test_the_key_is_a_bearer_token_in_the_header(self) -> None:
        tavily = Tavily(answer())

        await search(tavily)

        assert tavily.requests[0].headers["authorization"] == f"Bearer {KEY}"

    async def test_the_key_is_nowhere_else(self) -> None:
        tavily = Tavily(answer())

        await search(tavily)

        request = tavily.requests[0]
        assert KEY not in str(request.url)
        assert KEY.encode() not in request.content
        others = {name: value for name, value in request.headers.items() if name != "authorization"}
        assert KEY not in str(others)

    async def test_the_depop_search_is_basic_depth_and_only_depop(self) -> None:
        tavily = Tavily(answer())

        await search(tavily, DEPOP)

        assert tavily.bodies()[0] == {
            "query": "Nike vintage crewneck sweatshirt grey",
            "search_depth": "basic",
            "max_results": 10,
            "include_raw_content": "text",
            "topic": "general",
            "country": "united states",
            "include_domains": ["depop.com"],
        }

    async def test_the_retail_search_is_basic_depth_and_leaves_the_resale_sites_out(self) -> None:
        tavily = Tavily(retail=answer())

        await search(tavily, RETAIL)

        assert tavily.bodies()[0] == {
            "query": "Nike Club Fleece crew sweatshirt grey price",
            "search_depth": "basic",
            "max_results": 8,
            "include_raw_content": "text",
            "topic": "general",
            "country": "united states",
            "exclude_domains": ["depop.com", "ebay.com"],
        }

    async def test_the_depth_is_never_advanced_and_the_service_never_picks_it(self) -> None:
        # `advanced` is two credits a search, and `auto_parameters` lets the
        # service choose the depth itself: either quietly doubles the bill.
        tavily = Tavily(answer(), answer())

        await search(tavily, DEPOP)
        await search(tavily, RETAIL)

        for body in tavily.bodies():
            assert body["search_depth"] == "basic"
            assert "auto_parameters" not in body

    async def test_an_empty_domain_list_is_left_out_not_sent_empty(self) -> None:
        tavily = Tavily(retail=answer())

        await search(tavily, SearchRequest(query="nike crew", max_results=3))

        body = tavily.bodies()[0]
        assert "include_domains" not in body
        assert "exclude_domains" not in body

    async def test_the_base_address_is_the_one_configured(self) -> None:
        tavily = Tavily(answer())

        await search(tavily, base_url="https://search.example.test/v2/")

        assert str(tavily.requests[0].url) == "https://search.example.test/v2/search"

    async def test_it_is_built_from_the_settings(self) -> None:
        settings = Settings(
            tavily_api_key=f" {KEY}\n",
            tavily_base_url="https://search.example.test",
            tavily_timeout_seconds=7.5,
        )

        built = TavilySearch.from_settings(settings)

        assert built.configured
        assert built.name == "tavily"
        assert built._base_url == "https://search.example.test"
        assert built._timeout == 7.5
        assert built._api_key == KEY
        await built.aclose()

    def test_it_is_a_web_search(self) -> None:
        assert isinstance(TavilySearch(KEY), WebSearch)


class TestWithNoKey:
    async def test_no_key_is_not_configured_and_no_call_is_made(self) -> None:
        tavily = Tavily(answer())

        with pytest.raises(SearchError) as raised:
            await search(tavily, key=None)

        assert raised.value.status is PriceSearchStatus.NOT_CONFIGURED
        assert tavily.requests == []

    async def test_a_blank_key_is_no_key(self) -> None:
        tavily = Tavily(answer())

        with pytest.raises(SearchError) as raised:
            await search(tavily, key="")

        assert raised.value.status is PriceSearchStatus.NOT_CONFIGURED
        assert tavily.requests == []

    def test_whether_there_is_a_key_is_visible_without_asking(self) -> None:
        assert TavilySearch(KEY).configured
        assert not TavilySearch(None).configured
        assert not TavilySearch("").configured

    def test_from_settings_without_a_key_is_unconfigured(self) -> None:
        assert not TavilySearch.from_settings(Settings(tavily_api_key=None)).configured


class TestWhatComesBack:
    async def test_the_results_with_the_fields_the_service_gave(self) -> None:
        tavily = Tavily(
            answer(
                hit(
                    "https://www.depop.com/products/a/",
                    title="Nike crewneck",
                    content="a snippet",
                    raw="the page",
                    score=0.87,
                ),
                hit("https://www.depop.com/products/b/", title="Another", score=0.2),
            )
        )

        hits = await search(tavily)

        assert [(h.title, h.url, h.content, h.raw_content, h.score) for h in hits] == [
            ("Nike crewneck", "https://www.depop.com/products/a/", "a snippet", "the page", 0.87),
            ("Another", "https://www.depop.com/products/b/", "", "", 0.2),
        ]

    async def test_no_results_is_an_answer(self) -> None:
        assert await search(Tavily(answer())) == []

    async def test_a_page_is_cut_to_four_thousand_characters_on_arrival(self) -> None:
        # Before it is stored, passed on or put in a prompt.
        tavily = Tavily(answer(hit("https://www.depop.com/products/a/", raw="x" * 20_000)))

        (found,) = await search(tavily)

        assert MAX_RAW_CONTENT_CHARS == 4_000
        assert len(found.raw_content) == 4_000

    async def test_a_page_already_short_enough_is_whole(self) -> None:
        tavily = Tavily(answer(hit("https://www.depop.com/products/a/", raw="y" * 4_000)))

        (found,) = await search(tavily)

        assert found.raw_content == "y" * 4_000

    async def test_a_snippet_and_a_title_are_bounded_too(self) -> None:
        tavily = Tavily(
            answer(hit("https://www.depop.com/products/a/", title="t" * 5_000, content="c" * 9_000))
        )

        (found,) = await search(tavily)

        assert len(found.title) <= 300
        assert len(found.content) <= 2_000

    async def test_a_missing_or_null_page_is_empty_text(self) -> None:
        tavily = Tavily(
            answer(
                hit("https://www.depop.com/products/a/", raw=None),
                {"url": "https://www.depop.com/products/b/"},
            )
        )

        hits = await search(tavily)

        assert [(h.title, h.content, h.raw_content, h.score) for h in hits] == [
            ("", "", "", 0.5),
            ("", "", "", 0.0),
        ]

    async def test_a_result_with_no_link_is_skipped(self) -> None:
        tavily = Tavily(
            answer(
                hit("", title="no link"),
                {"title": "also no link"},
                hit("   ", title="blank link"),
                {"url": 5, "title": "a number"},
                hit("https://www.depop.com/products/a/"),
            )
        )

        hits = await search(tavily)

        assert [h.url for h in hits] == ["https://www.depop.com/products/a/"]

    async def test_an_entry_that_is_not_an_object_is_skipped(self) -> None:
        reply = httpx.Response(
            200, json={"results": ["text", 5, None, hit("https://www.depop.com/products/a/")]}
        )

        hits = await search(Tavily(reply))

        assert len(hits) == 1

    async def test_a_score_that_is_not_a_number_is_zero(self) -> None:
        reply = answer(
            {"url": "https://a.example/x", "score": "high"},
            {"url": "https://b.example/x", "score": True},
            {"url": "https://c.example/x", "score": 1},
        )

        hits = await search(Tavily(reply))

        assert [h.score for h in hits] == [0.0, 0.0, 1.0]

    async def test_a_link_is_trimmed(self) -> None:
        hits = await search(Tavily(answer(hit("  https://www.depop.com/products/a/  "))))

        assert hits[0].url == "https://www.depop.com/products/a/"


class TestTheAllowanceIsUsedUp:
    @pytest.mark.parametrize("code", [432, 433, 429])
    async def test_the_codes_that_mean_the_allowance_are_quota_exceeded(self, code: int) -> None:
        with pytest.raises(SearchError) as raised:
            await search(Tavily(status(code)))

        assert raised.value.status is PriceSearchStatus.QUOTA_EXCEEDED

    async def test_it_is_logged_without_the_key(self, caplog: pytest.LogCaptureFixture) -> None:
        caplog.set_level(logging.DEBUG)

        with pytest.raises(SearchError):
            await search(Tavily(status(432)))

        assert "allowance used up" in caplog.text
        assert KEY not in caplog.text


class TestTheKeyIsRefused:
    @pytest.mark.parametrize("code", [401, 403])
    async def test_a_refused_key_is_unavailable(self, code: int) -> None:
        with pytest.raises(SearchError) as raised:
            await search(Tavily(status(code)))

        assert raised.value.status is PriceSearchStatus.UNAVAILABLE

    @pytest.mark.parametrize("code", [401, 403])
    async def test_it_says_the_key_was_rejected_and_never_what_the_key_is(
        self, code: int, caplog: pytest.LogCaptureFixture
    ) -> None:
        caplog.set_level(logging.DEBUG)

        with pytest.raises(SearchError) as raised:
            await search(Tavily(status(code)))

        assert "search key rejected" in caplog.text
        assert KEY not in caplog.text
        assert KEY not in str(raised.value)
        for record in caplog.records:
            assert KEY not in record.getMessage()
            assert KEY not in str(record.args)

    async def test_a_reply_that_echoes_the_request_does_not_leak_it_either(
        self, caplog: pytest.LogCaptureFixture
    ) -> None:
        caplog.set_level(logging.DEBUG)
        echoing = httpx.Response(401, json={"detail": {"error": f"Invalid API key {KEY}"}})

        with pytest.raises(SearchError) as raised:
            await search(Tavily(echoing))

        assert KEY not in caplog.text
        assert KEY not in str(raised.value)


class TestAKeyThatCannotBeSent:
    @pytest.mark.parametrize(
        "key",
        [
            "tvly-\N{CYRILLIC SMALL LETTER KA}\N{CYRILLIC SMALL LETTER EL}",
            "tvly-\N{LEFT DOUBLE QUOTATION MARK}quoted\N{RIGHT DOUBLE QUOTATION MARK}",
            "tvly-\x00nul",
            "tvly-line\nbreak",
        ],
    )
    async def test_it_is_unavailable_and_nothing_is_sent(
        self, key: str, caplog: pytest.LogCaptureFixture
    ) -> None:
        # A paste with a curly quote in it. The HTTP client's own error for it
        # is not an HTTP error, and would have come out as a 400 from an
        # endpoint that promises never to have one.
        caplog.set_level(logging.DEBUG)
        tavily = Tavily(answer())

        with pytest.raises(SearchError) as raised:
            await search(tavily, key=key)

        assert raised.value.status is PriceSearchStatus.UNAVAILABLE
        assert tavily.requests == []
        assert "search key unusable" in caplog.text
        assert key not in caplog.text
        assert key not in str(raised.value)

    async def test_an_ordinary_key_is_sent(self) -> None:
        tavily = Tavily(answer())

        await search(tavily, key="tvly-AbC123_-xyz")

        assert len(tavily.requests) == 1


class TestTheServiceIsUnwell:
    @pytest.mark.parametrize("code", [400, 404, 422, 500, 502, 503, 504])
    async def test_any_other_status_is_unavailable(self, code: int) -> None:
        with pytest.raises(SearchError) as raised:
            await search(Tavily(status(code)))

        assert raised.value.status is PriceSearchStatus.UNAVAILABLE

    @pytest.mark.parametrize(
        "failure",
        [
            httpx.ConnectTimeout("connect timed out"),
            httpx.ReadTimeout("read timed out"),
            httpx.WriteTimeout("write timed out"),
            httpx.PoolTimeout("pool timed out"),
            httpx.ConnectError("no route to host"),
            httpx.ReadError("connection reset"),
            httpx.RemoteProtocolError("server disconnected"),
            httpx.LocalProtocolError("bad header"),
            httpx.TooManyRedirects("loop"),
        ],
    )
    async def test_a_timeout_or_a_network_error_is_unavailable(self, failure: Exception) -> None:
        def fail(request: httpx.Request) -> httpx.Response:
            raise failure

        with pytest.raises(SearchError) as raised:
            await search(Tavily(fail))

        assert raised.value.status is PriceSearchStatus.UNAVAILABLE

    async def test_a_failure_is_logged_by_kind_and_not_by_message(
        self, caplog: pytest.LogCaptureFixture
    ) -> None:
        caplog.set_level(logging.DEBUG)

        def fail(request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError(f"cannot reach https://api.tavily.com with {KEY}")

        with pytest.raises(SearchError) as raised:
            await search(Tavily(fail))

        assert "ConnectError" in caplog.text
        assert KEY not in caplog.text
        assert KEY not in str(raised.value)

    @pytest.mark.parametrize(
        "reply",
        [
            httpx.Response(200, content=b"<html>Bad gateway</html>"),
            httpx.Response(200, content=b""),
            httpx.Response(200, json=["not", "an", "object"]),
            httpx.Response(200, json="text"),
            httpx.Response(200, json=None),
            httpx.Response(200, json={}),
            httpx.Response(200, json={"results": None}),
            httpx.Response(200, json={"results": "none"}),
            httpx.Response(200, json={"results": {"url": "https://a.example/x"}}),
            httpx.Response(200, json={"detail": "ok but no results"}),
        ],
    )
    async def test_a_reply_that_is_not_a_result_list_is_unavailable(
        self, reply: httpx.Response
    ) -> None:
        with pytest.raises(SearchError) as raised:
            await search(Tavily(reply))

        assert raised.value.status is PriceSearchStatus.UNAVAILABLE

    async def test_nothing_but_a_search_error_ever_comes_out(self) -> None:
        # The caller catches exactly that, so anything else would be a 500 on an
        # endpoint that promises never to have one.
        cases: list[Any] = [
            status(500),
            httpx.Response(200, content=b"not json"),
            httpx.ReadTimeout("slow"),
            status(432),
            status(401),
        ]
        for case in cases:

            def respond(request: httpx.Request, case: Any = case) -> httpx.Response:
                if isinstance(case, Exception):
                    raise case
                return case

            with pytest.raises(SearchError):
                await search(Tavily(respond))


class TestTheClient:
    async def test_a_client_it_was_given_is_not_closed(self) -> None:
        client = httpx.AsyncClient(transport=httpx.MockTransport(Recorder(answer())))
        searcher = TavilySearch(KEY, client=client)

        await searcher.search(DEPOP)
        await searcher.aclose()

        assert not client.is_closed
        await client.aclose()

    async def test_a_client_it_made_is_closed(self) -> None:
        searcher = TavilySearch(KEY)
        made = searcher._http()

        await searcher.aclose()

        assert made.is_closed

    async def test_closing_with_nothing_open_is_fine(self) -> None:
        await TavilySearch(KEY).aclose()
