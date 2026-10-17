"""Reading prices off a page, and the small text rules the vetting leans on.

The module under test is the one that decides whether a number a model gave is a
number a page shows. It is tested as a table of page snippets rather than as
functions, because the way it fails is by meeting a spelling of a price nobody
thought of: `$ 25.00`, `US$25`, `25.00 USD`, a price with a non-breaking space in
it, a pound sign where a dollar was expected.

Each case is written the way a page would write it, and the expectation is one of
three answers — the page states the price in dollars, states it in something
else, or does not state it.
"""

from __future__ import annotations

import pytest

from app.services.selling import repair
from app.services.selling.brands import mentions_brand, plain, replace_brand
from app.services.selling.domains import (
    RESALE_DOMAINS,
    canonical_url,
    host_of,
    is_on,
    is_resale,
    shop_name,
)
from app.services.selling.page_text import (
    PriceCheck,
    check_price,
    first_dollar_price,
    mentions_sold,
    normalise,
    price_mentions,
    says_sold,
)

NBSP = "\N{NO-BREAK SPACE}"
ZERO_WIDTH = "\N{ZERO WIDTH SPACE}"


def checked(price: float, page: str) -> PriceCheck:
    """The answer for a page, normalised the way the service normalises it."""
    return check_price(price, normalise(page))


class TestWhatCountsAsADollarPrice:
    @pytest.mark.parametrize(
        ("price", "page"),
        [
            (25, "Vintage Nike crewneck $25"),
            (25, "Vintage Nike crewneck $25.00"),
            (25, "Vintage Nike crewneck $ 25.00"),
            (25, "Vintage Nike crewneck US$25"),
            (25, "Vintage Nike crewneck US$ 25.00"),
            (25, "Vintage Nike crewneck 25.00 USD"),
            (25, "Vintage Nike crewneck 25 USD"),
            (25, "Vintage Nike crewneck USD 25.00"),
            (25, "Vintage Nike crewneck USD25"),
            (1250, "Vintage Nike crewneck $1,250.00"),
            (1250, "Vintage Nike crewneck $1,250"),
            (1250, "Vintage Nike crewneck $1250"),
            (1250, "Vintage Nike crewneck 1,250.00 USD"),
            (25.5, "Vintage Nike crewneck $25.50"),
            (25.5, "Vintage Nike crewneck $25.5"),
            (28.56, "You get $28.56 after fees"),
            (19.99, "Only $19.99!"),
            (0.99, "Just $0.99"),
        ],
    )
    def test_the_spellings_a_page_uses(self, price: float, page: str) -> None:
        assert checked(price, page) is PriceCheck.VERIFIED

    @pytest.mark.parametrize(
        "page",
        [
            "Price: $25.",
            "Price: ($25)",
            "Price:$25",
            "**$25.00**",
            "[$25.00](https://www.depop.com/products/x)",
            "Now only $25.00 - sold",
            "$25.00",
            "was $40.00 now $25.00",
            "Nike$25",
        ],
    )
    def test_around_other_text(self, page: str) -> None:
        assert checked(25, page) is PriceCheck.VERIFIED

    def test_in_the_middle_of_a_long_page(self) -> None:
        page = ("lorem ipsum " * 300) + " Price $25.00 " + ("dolor sit amet " * 300)

        assert checked(25, page) is PriceCheck.VERIFIED

    @pytest.mark.parametrize(
        "page",
        [
            f"Price: ${NBSP}25.00",
            f"Price:{NBSP}$25.00",
            f"Price: ${ZERO_WIDTH}25.00",
            f"Price: $2{ZERO_WIDTH}5.00",
            "Price: &#36;25.00",
            "Price: &dollar;25.00",
            "Price: \\$25.00",
            "Price: \N{FULLWIDTH DOLLAR SIGN}25.00",
            "Price:\n\n   $\n25.00",
        ],
    )
    def test_however_the_page_was_extracted(self, page: str) -> None:
        # A page is not written for a regex, and a price on it should not be
        # lost to the way it was scraped.
        assert checked(25, page) is PriceCheck.VERIFIED

    def test_float_noise_does_not_lose_a_price(self) -> None:
        # 19.99 * 100 is 1998.9999999999998. Compared in cents, rounded.
        assert checked(19.99, "$19.99") is PriceCheck.VERIFIED
        assert checked(0.1 + 0.2, "$0.30") is PriceCheck.VERIFIED


class TestWhatIsNotTheirPrice:
    @pytest.mark.parametrize(
        "page",
        [
            "Vintage Nike crewneck $250",
            "Vintage Nike crewneck $125",
            "Vintage Nike crewneck $2.50",
            "Vintage Nike crewneck $25,000",
            "Vintage Nike crewneck $2,500.00",
            "Vintage Nike crewneck $25.999",
            "Vintage Nike crewneck $52",
            "Vintage Nike crewneck $26.00",
            "Vintage Nike crewneck $24.99",
        ],
    )
    def test_a_different_amount_is_not_this_price(self, page: str) -> None:
        # Not a substring match: "$250" contains "25", and is not twenty-five.
        assert checked(25, page) is PriceCheck.NOT_FOUND

    @pytest.mark.parametrize(
        "page",
        [
            "Size 25",
            "Waist 25 inches",
            "25 items sold",
            "Item number 25",
            "Posted 25 days ago",
            "25%",
            "25.00",
        ],
    )
    def test_a_number_with_no_currency_beside_it_is_not_a_price(self, page: str) -> None:
        assert checked(25, page) is PriceCheck.NOT_FOUND

    def test_a_page_with_no_price_at_all(self) -> None:
        assert checked(25, "A lovely grey crewneck, worn twice, from a smoke-free home.") is (
            PriceCheck.NOT_FOUND
        )

    def test_an_empty_page(self) -> None:
        assert checked(25, "") is PriceCheck.NOT_FOUND


class TestPricesInOtherCurrencies:
    @pytest.mark.parametrize(
        "page",
        [
            "£25",
            "£25.00",
            "£ 25.00",
            "€25",
            "€25.00",
            "€25,00",
            "A$25",
            "A$25.00",
            "AU$25",
            "AU$ 25.00",
            "C$25",
            "CA$25.00",
            "NZ$25",
            "HK$25",
            "R$ 25,00",
            "¥25",
            "₹25",
            "25 GBP",
            "25.00 GBP",
            "GBP 25",
            "GBP25.00",
            "25 EUR",
            "EUR 25.00",
            "25 AUD",
            "25.00 CAD",
            "25 NZD",
            "25 gbp",
            "&pound;25.00",
            "&euro;25.00",
            "\N{POUND SIGN}25",
        ],
    )
    def test_the_amount_beside_a_foreign_marker_is_not_dollars(self, page: str) -> None:
        # Dropped rather than converted: a comparable built on an invented
        # exchange rate looks like evidence and is not.
        assert checked(25, f"Vintage Nike crewneck {page}") is PriceCheck.NOT_USD

    def test_a_pound_sign_is_beside_this_price_not_just_somewhere_on_the_page(self) -> None:
        # Shipping in pounds does not make a dollar price a pound one.
        page = "Delivery £4.99. Vintage Nike crewneck $25.00"

        assert checked(25, page) is PriceCheck.VERIFIED
        assert checked(4.99, page) is PriceCheck.NOT_USD

    def test_a_dollar_elsewhere_does_not_outvote_a_pound_beside_the_price(self) -> None:
        # The same amount in two currencies is a page this service cannot state
        # the price of. "Not converted" would be a promise it could not keep if
        # a dollar sign could outvote a pound.
        assert checked(25, "$25.00 (approx.) £25.00") is PriceCheck.NOT_USD
        assert checked(25, "£25.00 $25.00") is PriceCheck.NOT_USD
        assert checked(25, "$25.00 or 25.00 EUR") is PriceCheck.NOT_USD

    def test_a_dollar_amount_followed_by_a_foreign_code_is_not_dollars(self) -> None:
        assert checked(25, "$25 CAD") is PriceCheck.NOT_USD

    def test_us_dollars_are_dollars_however_they_are_prefixed(self) -> None:
        for page in ("US$25", "US$ 25", "USD$25", "us$25", "USD 25"):
            assert checked(25, page) is PriceCheck.VERIFIED, page

    def test_a_longer_word_before_the_dollar_sign_is_not_a_country(self) -> None:
        # "Nike$25" is not a currency called Nike; it is a dollar sign.
        assert checked(25, "Nike$25") is PriceCheck.VERIFIED

    def test_a_foreign_price_for_a_different_amount_is_not_this_price_either(self) -> None:
        # Only the amount asked about decides. The pound price here is not 25.
        assert checked(25, "£32.00") is PriceCheck.NOT_FOUND


class TestFindingEveryPrice:
    def test_the_prices_come_in_page_order(self) -> None:
        mentions = price_mentions(normalise("Was $40 now 32 USD, ships for £4.99"))

        assert [(m.cents, m.usd) for m in mentions] == [(4000, True), (3200, True), (499, False)]

    def test_the_first_dollar_price_skips_other_currencies(self) -> None:
        assert first_dollar_price(normalise("£10 off. Now $32.00, was $40")) == 32.0

    def test_the_first_dollar_price_is_the_first_on_the_page(self) -> None:
        assert first_dollar_price(normalise("Was $40 now $32")) == 40.0

    def test_no_dollar_price_is_none(self) -> None:
        assert first_dollar_price(normalise("Only £10 or €12")) is None
        assert first_dollar_price("") is None

    def test_cents_are_exact(self) -> None:
        assert [m.cents for m in price_mentions("$0.05 $0.5 $5 $5.05 $1,000.10")] == [
            5,
            50,
            500,
            505,
            100010,
        ]


class TestNormalising:
    def test_whitespace_is_collapsed_and_trimmed(self) -> None:
        assert normalise("  a \n\n b\t\tc  ") == "a b c"

    def test_entities_are_decoded(self) -> None:
        assert normalise("Nike &amp; Co &#36;25 &pound;4") == "Nike & Co $25 £4"

    def test_width_forms_are_folded(self) -> None:
        assert normalise("\N{FULLWIDTH DOLLAR SIGN}\N{FULLWIDTH DIGIT TWO}5") == "$25"

    def test_the_non_breaking_space_becomes_a_space(self) -> None:
        assert normalise(f"$25{NBSP}USD") == "$25 USD"

    def test_invisible_characters_are_removed(self) -> None:
        assert normalise(f"$2{ZERO_WIDTH}5") == "$25"

    def test_a_markdown_escaped_dollar_is_unescaped(self) -> None:
        assert normalise("\\$25") == "$25"

    def test_nothing_is_nothing(self) -> None:
        assert normalise("") == ""
        assert normalise("   ") == ""


class TestSold:
    @pytest.mark.parametrize(
        "page",
        [
            "Sold",
            "SOLD",
            "This item has sold.",
            "Sold!",
            "Vintage crewneck - Sold - $32",
            "sold out",
        ],
    )
    def test_the_word_is_found(self, page: str) -> None:
        assert mentions_sold(page)

    @pytest.mark.parametrize(
        "page",
        ["Unsold stock", "resold twice", "sold-out style", "soldier", "Buy now", ""],
    )
    def test_other_words_are_not_it(self, page: str) -> None:
        assert not mentions_sold(page)

    @pytest.mark.parametrize(
        "page",
        ["Sold", "SOLD", "This item has sold.", "Sold!", "Vintage crewneck $32 Sold", "Sold: $32"],
    )
    def test_a_clear_marker(self, page: str) -> None:
        assert says_sold(normalise(page))

    @pytest.mark.parametrize(
        "page",
        [
            "52 sold",
            "1,200 sold",
            "Seller: 52 sold, 4.9 stars",
            "Sold by Depop seller maria",
            "Unsold",
            "Buy now",
        ],
    )
    def test_not_a_clear_marker_when_it_is_a_tally_or_boilerplate(self, page: str) -> None:
        # The word where it is not about this item having gone.
        assert not says_sold(normalise(page))


class TestHosts:
    @pytest.mark.parametrize(
        ("url", "host"),
        [
            ("https://www.depop.com/products/nike-grey-crewneck/", "www.depop.com"),
            ("https://depop.com/products/x", "depop.com"),
            ("HTTPS://WWW.DEPOP.COM/products/x", "www.depop.com"),
            ("https://uk.depop.com/products/x", "uk.depop.com"),
            ("https://www.depop.com:443/products/x", "www.depop.com"),
            ("https://depop.com./products/x", "depop.com"),
            ("  https://www.nike.com/t/x  ", "www.nike.com"),
            ("https://depop.com@evil.example/products/x", "evil.example"),
        ],
    )
    def test_the_host_of_a_link(self, url: str, host: str) -> None:
        assert host_of(url) == host

    @pytest.mark.parametrize(
        "url",
        [
            "",
            "   ",
            "http://www.depop.com/products/x",
            "ftp://www.depop.com/products/x",
            "//www.depop.com/products/x",
            "www.depop.com/products/x",
            "https://",
            "https:///products/x",
            "javascript:alert(1)",
            "https://www.depop.com/products/a b",
            "https://www.depop.com/products/a\nb",
            "https://[::1/products",
            "https://www.depop.com/" + "a" * 2048,
        ],
    )
    def test_a_link_that_is_not_one_to_follow(self, url: str) -> None:
        assert host_of(url) is None

    def test_a_link_exactly_at_the_limit_is_fine(self) -> None:
        url = "https://www.depop.com/" + "a" * (2048 - len("https://www.depop.com/"))

        assert host_of(url) == "www.depop.com"

    def test_the_domain_itself_and_its_subdomains_are_on_it(self) -> None:
        assert is_on("depop.com", "depop.com")
        assert is_on("www.depop.com", "depop.com")
        assert is_on("uk.shop.depop.com", "depop.com")

    @pytest.mark.parametrize(
        "host",
        [
            "notdepop.com",
            "depop.com.evil.example",
            "evil-depop.com",
            "depop.co.uk",
            "evil.example",
            "depop.community",
            "",
        ],
    )
    def test_a_lookalike_is_not_on_it(self, host: str) -> None:
        assert not is_on(host, "depop.com")

    @pytest.mark.parametrize(
        "host",
        [
            "depop.com",
            "www.depop.com",
            "ebay.com",
            "www.ebay.com",
            "www.ebay.co.uk",
            "ebay.com.au",
            "poshmark.com",
            "m.poshmark.com",
            "mercari.com",
            "grailed.com",
            "vinted.com",
            "www.vinted.co.uk",
            "thredup.com",
            "therealreal.com",
            "vestiairecollective.com",
            "etsy.com",
            "www.etsy.com",
            "m.facebook.com",
            "facebook.com",
        ],
    )
    def test_the_resale_sites_in_any_country(self, host: str) -> None:
        assert is_resale(host)

    @pytest.mark.parametrize(
        "host",
        ["www.nike.com", "nike.com", "www.amazon.com", "www.zara.com", "shop.levi.com", "hm.com"],
    )
    def test_shops_are_not(self, host: str) -> None:
        assert not is_resale(host)

    def test_every_site_the_search_excludes_is_one_the_vetting_refuses(self) -> None:
        # The two lists are one list. If they were written twice they would
        # drift, and a resale listing would be shown as what a shop charges new.
        for domain in RESALE_DOMAINS:
            assert is_resale(domain), domain
            assert is_resale(f"www.{domain}"), domain

    def test_the_search_excludes_exactly_these_sites(self) -> None:
        assert RESALE_DOMAINS == (
            "depop.com",
            "ebay.com",
            "poshmark.com",
            "mercari.com",
            "grailed.com",
            "vinted.com",
            "thredup.com",
            "therealreal.com",
            "vestiairecollective.com",
            "etsy.com",
            "facebook.com",
        )

    def test_amazon_is_not_excluded(self) -> None:
        assert not any("amazon" in domain for domain in RESALE_DOMAINS)

    def test_a_shop_is_named_by_its_domain(self) -> None:
        assert shop_name("www.nike.com") == "nike.com"
        assert shop_name("nike.com") == "nike.com"
        assert shop_name("shop.levi.com") == "shop.levi.com"


class TestTheSameLinkTwice:
    @pytest.mark.parametrize(
        "variant",
        [
            "https://www.depop.com/products/nike-grey/",
            "https://www.depop.com/products/nike-grey",
            "https://depop.com/products/nike-grey/",
            "https://WWW.DEPOP.COM/products/nike-grey/",
            "https://www.depop.com/products/nike-grey/#photos",
            "https://www.depop.com/products/nike-grey/?utm_source=google&utm_medium=cpc",
            "https://www.depop.com/products/nike-grey/?fbclid=abc123",
            "http://www.depop.com/products/nike-grey/",
        ],
    )
    def test_one_page_under_many_spellings(self, variant: str) -> None:
        assert canonical_url(variant) == canonical_url("https://www.depop.com/products/nike-grey/")

    def test_a_different_page_is_different(self) -> None:
        assert canonical_url("https://www.depop.com/products/nike-grey/") != canonical_url(
            "https://www.depop.com/products/nike-black/"
        )

    def test_a_parameter_that_picks_the_item_is_kept(self) -> None:
        assert canonical_url("https://shop.example/p?id=1") != canonical_url(
            "https://shop.example/p?id=2"
        )

    def test_the_order_of_parameters_does_not_matter(self) -> None:
        assert canonical_url("https://shop.example/p?a=1&b=2") == canonical_url(
            "https://shop.example/p?b=2&a=1"
        )

    def test_a_link_that_cannot_be_parsed_still_has_a_key(self) -> None:
        assert canonical_url("https://[::1/x") == "https://[::1/x"


class TestBrands:
    def test_a_brand_in_a_title(self) -> None:
        assert mentions_brand("Vintage Nike grey crewneck", "Nike")

    def test_case_does_not_matter(self) -> None:
        assert mentions_brand("VINTAGE NIKE GREY CREWNECK", "nike")

    def test_punctuation_in_a_brand_does_not_matter(self) -> None:
        assert mentions_brand("Levis 501 jeans", "Levi's")
        assert mentions_brand("Levi's 501 jeans", "Levis")
        assert mentions_brand("Levi\N{RIGHT SINGLE QUOTATION MARK}s 501 jeans", "Levi's")
        assert mentions_brand("J.Crew wool coat", "JCrew")

    def test_a_multi_word_brand(self) -> None:
        assert mentions_brand("Vintage Polo Ralph Lauren sweater", "Ralph Lauren")

    def test_a_brand_inside_a_longer_word_is_not_named(self) -> None:
        assert not mentions_brand("Red hoodie", "Ed")
        assert not mentions_brand("Nikea crewneck", "Nike")
        assert not mentions_brand("Anike", "Nike")

    def test_another_brand_is_not_named(self) -> None:
        assert not mentions_brand("Adidas grey crewneck", "Nike")

    def test_a_blank_brand_names_nothing(self) -> None:
        assert not mentions_brand("Nike grey crewneck", "")
        assert not mentions_brand("Nike grey crewneck", "  ")

    def test_a_brand_with_regex_characters_is_taken_literally(self) -> None:
        assert mentions_brand("Abercrombie + Fitch tee", "Abercrombie + Fitch")
        assert not mentions_brand("Abercrombie Fitch tee", "Abercrombie + Fitch")
        assert mentions_brand("H&M basic tee", "H&M")
        assert not mentions_brand("anything", ".*")

    def test_replacing_one_brand_with_another(self) -> None:
        assert replace_brand("Vintage Adidas crewneck", "Adidas", "Nike") == "Vintage Nike crewneck"

    def test_replacing_ignores_case_and_keeps_the_rest(self) -> None:
        assert replace_brand("vintage ADIDAS Crewneck", "adidas", "") == "vintage  Crewneck"

    def test_only_the_first_mention_is_replaced(self) -> None:
        assert replace_brand("Adidas by Adidas", "Adidas", "Nike") == "Nike by Adidas"

    def test_replacing_a_brand_that_is_not_there_says_so(self) -> None:
        assert replace_brand("Vintage crewneck", "Adidas", "Nike") is None
        assert replace_brand("Vintage crewneck", "", "Nike") is None

    def test_replacing_does_not_touch_the_inside_of_a_word(self) -> None:
        assert replace_brand("Adidasx crewneck", "Adidas", "Nike") is None

    def test_plain_folds_case_and_apostrophes(self) -> None:
        assert plain("Levi's") == "levis"


class TestRepairingWhatAModelWrote:
    def test_a_string_is_one_trimmed_line(self) -> None:
        assert repair.text("  Nike\n  crewneck  ", 80) == "Nike crewneck"

    def test_anything_else_is_nothing(self) -> None:
        assert repair.text(None, 80) is None
        assert repair.text(5, 80) is None
        assert repair.text(["a"], 80) is None
        assert repair.text("   ", 80) is None

    def test_a_string_over_the_limit_is_cut_at_a_word(self) -> None:
        cut = repair.text("one two three four five", 12)

        assert cut == "one two"

    def test_a_string_under_the_minimum_is_nothing(self) -> None:
        assert repair.text("ab", 80, minimum=3) is None
        assert repair.text("abc", 80, minimum=3) == "abc"

    def test_a_list_is_trimmed_deduplicated_and_counted(self) -> None:
        assert repair.texts(["Grey", " grey ", "Navy", "", None, 5, "Red"], limit=30, count=3) == [
            "Grey",
            "Navy",
            "Red",
        ]

    def test_an_entry_with_nothing_in_it_but_punctuation_is_nothing(self) -> None:
        assert repair.texts(["-", "...", "ok"], limit=30, count=3) == ["ok"]

    def test_what_is_excluded_is_excluded_however_it_is_spelt(self) -> None:
        assert repair.texts(["Levi's", "denim"], limit=30, count=3, exclude=["levis"]) == ["denim"]

    def test_a_list_that_is_not_a_list_is_empty(self) -> None:
        assert repair.texts("Grey", limit=30, count=3) == []
        assert repair.texts(None, limit=30, count=3) == []

    @pytest.mark.parametrize(
        ("value", "default", "expected"),
        [
            (0.5, 0.9, 0.5),
            (1, 0.9, 1.0),
            (0, 0.9, 0.0),
            (1.4, 0.9, 1.0),
            (-3, 0.9, 0.0),
            (None, 0.9, 0.9),
            ("high", 0.9, 0.9),
            (True, 0.9, 0.9),
        ],
    )
    def test_a_confidence_is_clamped_and_a_missing_one_takes_the_default(
        self, value: object, default: float, expected: float
    ) -> None:
        assert repair.confidence(value, default) == expected
