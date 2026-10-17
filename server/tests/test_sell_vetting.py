"""Which of a reader's claims reach the screen.

The most heavily tested module in the service, because it is the one that stands
between a model's word and a seller's price. A reader can number a result that
does not exist, put a price on the wrong item, copy a pound as a dollar, or call
a listing sold that is not; the vetting exists so that none of that gets as far
as the arithmetic, and so that when it is stopped the number of results stopped
for each reason is on the screen.

Every case builds the search results and the claims by hand, so each test names
the one thing that is wrong with one result and checks what happened to it. The
helpers default to a result that passes everything, which means a test that
breaks one rule is also, by construction, a test that nothing else is refusing
it.
"""

from __future__ import annotations

import math
from typing import Any

import pytest

from app.schemas.selling import Comparable, RetailReference
from app.services.selling.base import Candidate, NumberedResult
from app.services.selling.vetting import MAX_COMPARABLES, MAX_RETAIL, vet

DEPOP = "https://www.depop.com/products/seller-vintage-nike-grey-crewneck/"
PAGE = (
    "Vintage Nike grey crewneck sweatshirt, embroidered swoosh. $32.00. Size M. Used - Excellent."
)


def result(
    index: int = 0,
    *,
    url: str = DEPOP,
    title: str = "Vintage Nike grey crewneck sweatshirt",
    text: str = PAGE,
    origin: str = "listing",
    score: float = 0.5,
) -> NumberedResult:
    return NumberedResult(
        index=index,
        origin=origin,  # type: ignore[arg-type]
        title=title,
        url=url,
        text=text,
        score=score,
    )


def claim(
    index: int = 0,
    *,
    kind: str = "listing",
    price: float = 32.0,
    currency: str = "USD",
    sold: bool | None = None,
    condition: str | None = None,
    match: str = "same",
    why: str | None = "Same Nike crewneck",
) -> Candidate:
    return Candidate(
        result_index=index,
        kind=kind,  # type: ignore[arg-type]
        price=price,
        currency=currency,
        sold=sold,
        condition=condition,
        match=match,  # type: ignore[arg-type]
        why=why,
    )


def retail_result(
    index: int = 0,
    *,
    url: str = "https://www.nike.com/t/sportswear-club-fleece-crew",
    text: str = "Nike Sportswear Club Fleece Crew. $60.00. Free shipping.",
    title: str = "Nike Sportswear Club Fleece Crew",
    score: float = 0.5,
) -> NumberedResult:
    return result(index, url=url, text=text, title=title, origin="retail", score=score)


def retail_claim(index: int = 0, *, price: float = 60.0, **fields: Any) -> Candidate:
    return claim(index, kind="retail", price=price, **fields)


def counts(vetted: Any) -> tuple[int, int, int]:
    excluded = vetted.excluded
    return (excluded.not_usd, excluded.unverified_price, excluded.not_comparable)


class TestAClaimThePageBearsOut:
    def test_a_listing_is_shown_as_a_comparable(self) -> None:
        vetted = vet([claim()], [result()], brand="Nike")

        assert len(vetted.comparables) == 1
        shown = vetted.comparables[0]
        assert shown.price == 32.0
        assert shown.currency == "USD"
        assert shown.match == "same"
        assert shown.why == "Same Nike crewneck"
        assert counts(vetted) == (0, 0, 0)

    def test_a_shop_is_shown_as_a_retail_reference(self) -> None:
        vetted = vet([retail_claim()], [retail_result()], brand="Nike")

        assert len(vetted.retail) == 1
        shown = vetted.retail[0]
        assert shown.price == 60.0
        assert shown.seller == "nike.com"
        assert vetted.comparables == []
        assert counts(vetted) == (0, 0, 0)

    def test_both_kinds_together(self) -> None:
        results = [result(0), retail_result(1)]

        vetted = vet([claim(0), retail_claim(1)], results, brand="Nike")

        assert len(vetted.comparables) == 1
        assert len(vetted.retail) == 1

    def test_nothing_in_nothing_out(self) -> None:
        vetted = vet([], [])

        assert vetted.comparables == []
        assert vetted.retail == []
        assert counts(vetted) == (0, 0, 0)

    def test_a_price_in_the_title_alone_is_on_the_page(self) -> None:
        page = result(title="Nike grey crewneck - $32.00", text="Vintage grey crewneck. Size M.")

        assert len(vet([claim()], [page]).comparables) == 1

    def test_the_price_is_shown_to_the_cent(self) -> None:
        page = result(text="Nike crewneck. $28.56")

        assert vet([claim(price=28.56)], [page]).comparables[0].price == 28.56

    def test_a_dollar_price_in_any_of_the_accepted_spellings(self) -> None:
        for spelling in ("$32", "$32.00", "$ 32.00", "US$32", "32.00 USD", "USD 32"):
            page = result(text=f"Vintage Nike crewneck {spelling}")
            assert len(vet([claim()], [page]).comparables) == 1, spelling

    def test_a_four_figure_price(self) -> None:
        page = result(text="Rare Nike crewneck $1,250.00")

        shown = vet([claim(price=1250.0)], [page]).comparables

        assert [item.price for item in shown] == [1250.0]


class TestTheLinkAndTheTitleAreTheSearchResults:
    def test_the_link_is_the_one_the_search_returned(self) -> None:
        vetted = vet([claim()], [result()])

        assert vetted.comparables[0].url == DEPOP

    def test_the_title_is_the_one_the_search_returned(self) -> None:
        page = result(title="Vintage Nike grey crewneck sweatshirt")

        assert vet([claim()], [page]).comparables[0].title == page.title

    def test_a_reader_that_sends_a_link_of_its_own_has_it_ignored(self) -> None:
        # The reader is not asked for a link, and one it volunteers goes nowhere.
        invented = Candidate.model_validate(
            {
                "resultIndex": 0,
                "kind": "listing",
                "price": 32.0,
                "currency": "USD",
                "match": "same",
                "url": "https://www.depop.com/products/invented-by-the-model/",
                "title": "A title the model made up",
            }
        )

        shown = vet([invented], [result()]).comparables[0]

        assert shown.url == DEPOP
        assert shown.title == "Vintage Nike grey crewneck sweatshirt"
        assert not hasattr(invented, "url")

    def test_the_title_is_tidied_to_the_contract_and_not_rewritten(self) -> None:
        page = result(title="  Vintage   Nike\n grey crewneck  ")

        assert vet([claim()], [page]).comparables[0].title == "Vintage Nike grey crewneck"

    def test_a_long_title_is_cut_to_two_hundred(self) -> None:
        page = result(title="Vintage Nike grey crewneck " * 20)

        title = vet([claim()], [page]).comparables[0].title

        assert len(title) <= 200
        assert title.startswith("Vintage Nike grey crewneck")

    def test_a_result_with_no_title_is_named_for_its_site(self) -> None:
        assert vet([claim()], [result(title="")]).comparables[0].title == "depop.com"
        assert vet([claim()], [result(title="   ")]).comparables[0].title == "depop.com"

    def test_the_link_is_not_rewritten(self) -> None:
        url = "https://www.depop.com/products/seller-nike/?ref=search&utm_source=x"

        assert vet([claim()], [result(url=url)]).comparables[0].url == url

    def test_a_link_is_trimmed_of_the_whitespace_around_it(self) -> None:
        assert vet([claim()], [result(url=f"  {DEPOP}  ")]).comparables[0].url == DEPOP


class TestAResultThatIsNotThere:
    def test_a_claim_about_a_result_that_does_not_exist_is_dropped(self) -> None:
        # The reader numbered a result the search never returned.
        vetted = vet([claim(99)], [result(0)])

        assert vetted.comparables == []

    def test_and_the_real_result_it_failed_to_mention_is_counted_as_not_comparable(self) -> None:
        # Counted for the result that was looked at and not put forward, not
        # for the number that was made up: the excluded counts add up to what
        # the search found, never to more.
        vetted = vet([claim(99)], [result(0)])

        assert counts(vetted) == (0, 0, 1)

    def test_a_negative_index(self) -> None:
        assert vet([claim(-1)], [result(0)]).comparables == []

    def test_an_index_one_past_the_end(self) -> None:
        assert vet([claim(1)], [result(0)]).comparables == []

    def test_a_real_claim_beside_an_invented_one_is_unharmed(self) -> None:
        vetted = vet([claim(99), claim(0)], [result(0)])

        assert len(vetted.comparables) == 1
        assert counts(vetted) == (0, 0, 0)

    def test_the_index_is_the_results_own_number_not_its_place_in_the_list(self) -> None:
        results = [result(7, url="https://www.depop.com/products/seven/")]

        vetted = vet([claim(7)], results)

        assert vetted.comparables[0].url == "https://www.depop.com/products/seven/"
        assert vet([claim(0)], results).comparables == []


class TestAPriceThatIsNotOnThePage:
    def test_a_price_the_page_does_not_state_is_dropped_and_counted(self) -> None:
        page = result(text="Vintage Nike crewneck. $32.00. Size M.")

        vetted = vet([claim(price=45.0)], [page])

        assert vetted.comparables == []
        assert counts(vetted) == (0, 1, 0)

    def test_a_price_that_is_part_of_another_number_is_not_on_the_page(self) -> None:
        page = result(text="Vintage Nike crewneck. $320.00.")

        assert counts(vet([claim(price=32.0)], [page])) == (0, 1, 0)

    def test_a_number_with_no_currency_beside_it_is_not_a_price(self) -> None:
        page = result(text="Vintage Nike crewneck, size 32, waist 32.")

        assert counts(vet([claim(price=32.0)], [page])) == (0, 1, 0)

    @pytest.mark.parametrize("price", [0, -5, math.nan, math.inf, -math.inf, 100_001, 1e12])
    def test_a_price_that_cannot_be_a_price_is_unverified(self, price: float) -> None:
        page = result(text="Nike crewneck $0 $-5 $100001 $1000000000000")

        vetted = vet([claim(price=price)], [page])

        assert vetted.comparables == []
        assert counts(vetted) == (0, 1, 0)

    def test_a_price_that_is_a_cent_out_is_not_the_page_price(self) -> None:
        assert counts(vet([claim(price=32.01)], [result()])) == (0, 1, 0)
        assert counts(vet([claim(price=31.99)], [result()])) == (0, 1, 0)
        assert counts(vet([claim(price=32.006)], [result()])) == (0, 1, 0)

    def test_float_noise_below_a_cent_is_not_a_different_price(self) -> None:
        shown = vet([claim(price=32.004)], [result()]).comparables

        assert [item.price for item in shown] == [32.0]

    def test_a_price_on_a_retail_page_is_checked_the_same_way(self) -> None:
        page = retail_result(text="Nike Club Fleece Crew. $60.00")

        assert counts(vet([retail_claim(price=75.0)], [page])) == (0, 1, 0)

    def test_the_price_must_be_on_this_result_and_not_another(self) -> None:
        results = [
            result(0, text="Nike crewneck $32.00"),
            result(1, url="https://www.depop.com/products/other/", text="Nike crewneck $45.00"),
        ]

        vetted = vet([claim(0, price=45.0), claim(1, price=45.0)], results)

        assert [item.price for item in vetted.comparables] == [45.0]
        assert counts(vetted) == (0, 1, 0)


class TestAPriceThatIsNotInDollars:
    def test_a_reader_that_says_pounds_is_dropped_and_counted(self) -> None:
        vetted = vet([claim(currency="GBP")], [result()])

        assert vetted.comparables == []
        assert counts(vetted) == (1, 0, 0)

    @pytest.mark.parametrize("currency", ["GBP", "gbp", "£", "EUR", "€", "AUD", "A$", "CAD", "NZD"])
    def test_whatever_other_currency_it_names(self, currency: str) -> None:
        assert counts(vet([claim(currency=currency)], [result()])) == (1, 0, 0)

    @pytest.mark.parametrize("currency", ["USD", "usd", " USD ", "US$", "$", "US Dollars"])
    def test_however_it_says_dollars(self, currency: str) -> None:
        assert len(vet([claim(currency=currency)], [result()]).comparables) == 1

    def test_a_reader_that_says_nothing_about_the_currency_is_left_to_the_page(self) -> None:
        assert len(vet([claim(currency="")], [result()]).comparables) == 1

        pounds = result(text="Nike crewneck £32.00")
        assert counts(vet([claim(currency="")], [pounds])) == (1, 0, 0)

    @pytest.mark.parametrize("sign", ["£", "€", "A$", "AU$", "C$", "CA$", "NZ$"])
    def test_a_page_that_shows_a_foreign_sign_beside_the_price_is_dropped(self, sign: str) -> None:
        # The reader said dollars. The page says otherwise, and the page wins.
        page = result(text=f"Vintage Nike crewneck {sign}32.00. Size M.")

        vetted = vet([claim(currency="USD")], [page])

        assert vetted.comparables == []
        assert counts(vetted) == (1, 0, 0)

    @pytest.mark.parametrize("code", ["GBP", "EUR", "AUD", "CAD"])
    def test_a_page_that_shows_a_foreign_code_beside_the_price_is_dropped(self, code: str) -> None:
        page = result(text=f"Vintage Nike crewneck 32.00 {code}. Size M.")

        assert counts(vet([claim(currency="USD")], [page])) == (1, 0, 0)

    def test_a_foreign_sign_beside_another_amount_does_not_matter(self) -> None:
        page = result(text="Vintage Nike crewneck $32.00 + £4.99 postage")

        assert len(vet([claim(currency="USD")], [page]).comparables) == 1

    def test_a_pound_price_on_a_retail_page_is_dropped_too(self) -> None:
        page = retail_result(text="Nike Club Fleece Crew £60.00")

        assert counts(vet([retail_claim(currency="USD")], [page])) == (1, 0, 0)

    def test_a_pound_price_the_reader_copied_as_dollars_is_caught_by_the_page(self) -> None:
        page = result(text="Vintage Nike crewneck £32")

        vetted = vet([claim(price=32.0, currency="USD")], [page])

        assert vetted.comparables == []
        assert counts(vetted) == (1, 0, 0)


class TestAComparableIsADepopListing:
    @pytest.mark.parametrize(
        "url",
        [
            "https://www.depop.com/products/x/",
            "https://depop.com/products/x/",
            "https://uk.depop.com/products/x/",
            "https://shop.depop.com/products/x/",
            "https://www.depop.com:443/products/x/",
        ],
    )
    def test_depop_and_its_subdomains_are_comparable(self, url: str) -> None:
        assert len(vet([claim()], [result(url=url)]).comparables) == 1

    @pytest.mark.parametrize(
        "url",
        [
            "https://www.ebay.com/itm/123456",
            "https://www.poshmark.com/listing/x",
            "https://www.nike.com/t/club-fleece-crew",
            "https://www.vinted.co.uk/items/1",
            "https://notdepop.com/products/x",
            "https://depop.com.evil.example/products/x",
            "https://evil.example/?u=depop.com",
            "https://evil.example/depop.com/products/x",
            "https://depop.com@evil.example/products/x",
            "https://depop.co.uk/products/x",
            "https://www.depop.community/products/x",
        ],
    )
    def test_anywhere_else_is_not_comparable(self, url: str) -> None:
        vetted = vet([claim()], [result(url=url)])

        assert vetted.comparables == []
        assert counts(vetted) == (0, 0, 1)

    @pytest.mark.parametrize(
        "url",
        [
            "http://www.depop.com/products/x/",
            "ftp://www.depop.com/products/x/",
            "www.depop.com/products/x/",
            "//www.depop.com/products/x/",
            "javascript:alert(1)",
            "",
            "https://",
        ],
    )
    def test_a_link_that_is_not_https_is_not_comparable(self, url: str) -> None:
        vetted = vet([claim()], [result(url=url)])

        assert vetted.comparables == []
        assert counts(vetted) == (0, 0, 1)

    def test_a_link_with_whitespace_in_it_is_not_one_to_show(self) -> None:
        assert counts(vet([claim()], [result(url="https://www.depop.com/products/a b/")])) == (
            0,
            0,
            1,
        )

    def test_a_link_longer_than_the_contract_allows_is_not_shown(self) -> None:
        assert counts(vet([claim()], [result(url="https://www.depop.com/" + "a" * 2100)])) == (
            0,
            0,
            1,
        )

    def test_a_reader_that_calls_a_shop_a_listing_is_overruled(self) -> None:
        page = retail_result()

        vetted = vet([claim(0, kind="listing", price=60.0)], [page])

        assert vetted.comparables == []
        assert counts(vetted) == (0, 0, 1)

    def test_the_site_is_checked_before_the_currency(self) -> None:
        # A page that was never a candidate is not reported as one in pounds.
        page = result(url="https://www.ebay.co.uk/itm/1", text="Nike crewneck £32.00")

        assert counts(vet([claim(currency="GBP")], [page])) == (0, 0, 1)


class TestARetailPriceIsNotFromAResaleSite:
    @pytest.mark.parametrize(
        "url",
        [
            "https://www.nike.com/t/club-fleece-crew",
            "https://www.amazon.com/dp/B0EXAMPLE",
            "https://www.zappos.com/p/nike-club-fleece",
            "https://shop.levi.com/product",
            "https://www.dickssportinggoods.com/p/nike-crew",
        ],
    )
    def test_shops_are_fine(self, url: str) -> None:
        page = retail_result(url=url)

        assert len(vet([retail_claim()], [page]).retail) == 1

    @pytest.mark.parametrize(
        "url",
        [
            "https://www.depop.com/products/x/",
            "https://www.ebay.com/itm/1",
            "https://www.ebay.co.uk/itm/1",
            "https://www.ebay.com.au/itm/1",
            "https://www.poshmark.com/listing/x",
            "https://poshmark.com/listing/x",
            "https://www.mercari.com/us/item/m1/",
            "https://www.grailed.com/listings/1",
            "https://www.vinted.com/items/1",
            "https://www.vinted.co.uk/items/1",
            "https://www.thredup.com/product/women/x",
            "https://www.therealreal.com/products/x",
            "https://www.vestiairecollective.com/women-clothing/x",
            "https://www.etsy.com/listing/1",
            "https://www.facebook.com/marketplace/item/1",
            "https://m.facebook.com/marketplace/item/1",
        ],
    )
    def test_resale_sites_are_not_a_price_new(self, url: str) -> None:
        vetted = vet([retail_claim()], [retail_result(url=url)])

        assert vetted.retail == []
        assert counts(vetted) == (0, 0, 1)

    def test_a_reader_that_calls_a_listing_retail_is_overruled(self) -> None:
        # A Depop listing offered as what a shop charges new would put a used
        # asking price in the slot a used item is capped by.
        vetted = vet([retail_claim(0, price=32.0)], [result(0)])

        assert vetted.retail == []
        assert counts(vetted) == (0, 0, 1)

    def test_a_retail_link_must_be_https_too(self) -> None:
        page = retail_result(url="http://www.nike.com/t/club-fleece-crew")

        assert counts(vet([retail_claim()], [page])) == (0, 0, 1)

    def test_the_seller_is_the_shops_domain_without_www(self) -> None:
        assert vet([retail_claim()], [retail_result()]).retail[0].seller == "nike.com"
        page = retail_result(url="https://shop.levi.com/product", text="Levi's 501 $60.00")
        assert vet([retail_claim()], [page]).retail[0].seller == "shop.levi.com"


class TestSold:
    def test_a_sale_the_page_mentions_stands(self) -> None:
        page = result(text="Vintage Nike crewneck $32.00 Sold")

        assert vet([claim(sold=True)], [page]).comparables[0].sold is True

    def test_a_sale_the_page_never_mentions_is_not_repeated(self) -> None:
        # A comparable marked sold outweighs every asking price beside it, so
        # the word has to be on the page.
        page = result(text="Vintage Nike crewneck $32.00 Buy now")

        shown = vet([claim(sold=True)], [page]).comparables

        assert len(shown) == 1
        assert shown[0].sold is None
        assert "sold" not in shown[0].to_wire()

    def test_still_for_sale_is_kept_as_it_is_not_a_claim_of_a_sale(self) -> None:
        assert vet([claim(sold=False)], [result()]).comparables[0].sold is False

    def test_not_saying_is_not_saying(self) -> None:
        assert vet([claim(sold=None)], [result()]).comparables[0].sold is None

    def test_a_word_that_merely_contains_sold_is_not_a_sale(self) -> None:
        page = result(text="Vintage Nike crewneck $32.00 Unsold stock, resold twice")

        assert vet([claim(sold=True)], [page]).comparables[0].sold is None

    def test_the_title_counts_as_the_page(self) -> None:
        page = result(title="SOLD - Nike crewneck", text="Vintage Nike crewneck $32.00")

        assert vet([claim(sold=True)], [page]).comparables[0].sold is True

    def test_a_shop_has_no_sold(self) -> None:
        shown = vet([retail_claim(sold=True)], [retail_result(text="Nike $60.00 sold out")]).retail

        assert "sold" not in shown[0].to_wire()


class TestCondition:
    def test_a_condition_the_page_states_is_kept_verbatim(self) -> None:
        shown = vet([claim(condition="Used - Excellent")], [result()]).comparables[0]

        assert shown.condition == "Used - Excellent"

    def test_a_condition_matches_ignoring_case(self) -> None:
        page = result(text="Nike crewneck $32.00 USED - EXCELLENT")

        assert vet([claim(condition="Used - Excellent")], [page]).comparables[0].condition == (
            "Used - Excellent"
        )

    def test_a_paraphrase_is_dropped_but_the_comparable_stays(self) -> None:
        shown = vet([claim(condition="excellent shape")], [result()]).comparables

        assert len(shown) == 1
        assert shown[0].condition is None

    def test_a_condition_the_page_does_not_mention_is_dropped(self) -> None:
        page = result(text="Nike crewneck $32.00")

        assert vet([claim(condition="Like new")], [page]).comparables[0].condition is None

    def test_a_condition_longer_than_the_contract_allows_is_dropped(self) -> None:
        long = "Used - Excellent " * 5
        page = result(text=f"Nike crewneck $32.00 {long}")

        assert vet([claim(condition=long)], [page]).comparables[0].condition is None

    @pytest.mark.parametrize("condition", [None, "", "   "])
    def test_nothing_stated_is_nothing_shown(self, condition: str | None) -> None:
        assert vet([claim(condition=condition)], [result()]).comparables[0].condition is None


class TestSameAndSimilar:
    def test_same_is_kept_when_the_page_names_the_brand(self) -> None:
        assert vet([claim(match="same")], [result()], brand="Nike").comparables[0].match == "same"

    def test_same_becomes_similar_when_the_page_does_not_name_the_brand(self) -> None:
        # Two same-item sales are enough, in the arithmetic that follows, to
        # price above every asking price. "Same" has to mean something a
        # pattern can see.
        page = result(title="Vintage grey crewneck", text="Vintage Adidas grey crewneck $32.00")

        assert vet([claim(match="same")], [page], brand="Nike").comparables[0].match == "similar"

    def test_the_brand_is_recognised_however_it_is_spelt(self) -> None:
        page = result(title="Vintage jeans", text="Vintage LEVIS 501 jeans $32.00")

        assert vet([claim(match="same")], [page], brand="Levi's").comparables[0].match == "same"

    def test_the_brand_in_the_title_alone_is_the_brand(self) -> None:
        page = result(title="Nike grey crewneck", text="Vintage grey crewneck $32.00")

        assert vet([claim(match="same")], [page], brand="Nike").comparables[0].match == "same"

    def test_the_brand_inside_another_word_is_not_the_brand(self) -> None:
        page = result(title="Vintage grey crewneck", text="Vintage Nikea grey crewneck $32.00")

        assert vet([claim(match="same")], [page], brand="Nike").comparables[0].match == "similar"

    def test_with_no_brand_to_hold_it_to_the_readers_word_stands(self) -> None:
        page = result(text="Vintage grey crewneck $32.00")

        assert vet([claim(match="same")], [page], brand=None).comparables[0].match == "same"
        assert vet([claim(match="same")], [page], brand="").comparables[0].match == "same"

    def test_similar_is_never_upgraded(self) -> None:
        shown = vet([claim(match="similar")], [result()], brand="Nike").comparables[0]

        assert shown.match == "similar"

    def test_a_retail_same_is_held_to_the_brand_too(self) -> None:
        page = retail_result(title="Essentials Crew", text="Adidas Essentials Crew. $60.00")

        shown = vet([retail_claim(match="same")], [page], brand="Nike").retail[0]

        assert shown.match == "similar"


class TestWhy:
    def test_the_readers_reason_is_kept(self) -> None:
        assert vet([claim(why="Same 90s Nike crewneck")], [result()]).comparables[0].why == (
            "Same 90s Nike crewneck"
        )

    def test_a_reason_over_the_limit_is_trimmed_not_refused(self) -> None:
        shown = vet([claim(why="Same Nike crewneck, also grey. " * 20)], [result()]).comparables

        assert len(shown) == 1
        assert shown[0].why is not None and len(shown[0].why) <= 160

    @pytest.mark.parametrize("why", [None, "", "   "])
    def test_no_reason_is_no_reason(self, why: str | None) -> None:
        assert vet([claim(why=why)], [result()]).comparables[0].why is None


class TestTheSamePageTwice:
    def test_one_page_found_twice_is_shown_once(self) -> None:
        results = [
            result(0, url="https://www.depop.com/products/nike-grey/"),
            result(1, url="https://depop.com/products/nike-grey?utm_source=google"),
        ]

        vetted = vet([claim(0), claim(1)], results)

        assert len(vetted.comparables) == 1
        # Neither refused nor "found": the duplicate is not counted anywhere.
        assert counts(vetted) == (0, 0, 0)

    def test_a_refused_duplicate_does_not_hide_a_good_one(self) -> None:
        url = "https://www.depop.com/products/nike-grey/"
        results = [
            result(0, url=url, text="Nike crewneck $45.00"),
            result(1, url=url, text="Nike crewneck $32.00"),
        ]

        vetted = vet([claim(0, price=32.0), claim(1, price=32.0)], results)

        assert len(vetted.comparables) == 1
        assert counts(vetted) == (0, 1, 0)

    def test_the_first_of_two_good_duplicates_is_the_one_shown(self) -> None:
        url = "https://www.depop.com/products/nike-grey/"
        results = [
            result(0, url=url, text="Nike crewneck $32.00", title="first"),
            result(1, url=url, text="Nike crewneck $32.00", title="second"),
        ]

        shown = vet([claim(0), claim(1)], results).comparables

        assert [item.title for item in shown] == ["first"]

    def test_two_different_pages_with_one_price_are_two_comparables(self) -> None:
        results = [
            result(0, url="https://www.depop.com/products/a/"),
            result(1, url="https://www.depop.com/products/b/"),
        ]

        assert len(vet([claim(0), claim(1)], results).comparables) == 2

    def test_one_claim_per_result_the_first(self) -> None:
        # A reader that lists a page twice has not found two comparables.
        vetted = vet(
            [claim(0, price=32.0), claim(0, price=45.0)], [result(0, text="$32.00 $45.00")]
        )

        assert [item.price for item in vetted.comparables] == [32.0]

    def test_the_first_claim_wins_even_when_it_is_the_bad_one(self) -> None:
        vetted = vet([claim(0, price=99.0), claim(0, price=32.0)], [result(0)])

        assert vetted.comparables == []
        assert counts(vetted) == (0, 1, 0)


class TestWhatIsLeftOutIsCounted:
    def test_a_result_the_reader_did_not_put_forward_is_not_comparable(self) -> None:
        results = [result(0), result(1, url="https://www.depop.com/products/other/")]

        vetted = vet([claim(0)], results)

        assert len(vetted.comparables) == 1
        assert counts(vetted) == (0, 0, 1)

    def test_every_result_is_in_exactly_one_place(self) -> None:
        results = [
            result(0, url="https://www.depop.com/products/ok/"),
            result(1, url="https://www.depop.com/products/pounds/", text="Nike crewneck £32.00"),
            result(2, url="https://www.depop.com/products/nope/", text="Nike crewneck"),
            result(3, url="https://www.ebay.com/itm/1", text="Nike crewneck $32.00"),
            result(4, url="https://www.depop.com/products/unmentioned/"),
            retail_result(5),
            retail_result(6, url="https://www.ebay.com/itm/2", text="Nike crew $60.00"),
        ]
        claims = [claim(0), claim(1), claim(2), claim(3), retail_claim(5), retail_claim(6)]

        vetted = vet(claims, results)

        shown = len(vetted.comparables) + len(vetted.retail)
        assert shown == 2
        assert counts(vetted) == (1, 1, 3)
        assert shown + sum(counts(vetted)) == len(results)

    def test_a_vetting_never_raises_whatever_the_reader_sent(self) -> None:
        results = [
            result(0, url="https://[::1/products/x"),
            result(1, url="https://www.depop.com/products/x/", text=""),
            result(2, title="", text=""),
        ]
        claims = [claim(0), claim(1, price=math.nan), claim(2, price=1e308)]

        vetted = vet(claims, results)

        assert vetted.comparables == []
        assert sum(counts(vetted)) == 3


class TestWhatIsShownFirstAndHowMuchOfIt:
    def results(self, count: int, *, prefix: str = "https://www.depop.com/products/") -> list[Any]:
        return [result(n, url=f"{prefix}item-{n}/", score=n / 100) for n in range(count)]

    def test_same_comes_before_similar(self) -> None:
        results = self.results(4)
        claims = [
            claim(0, match="similar"),
            claim(1, match="same"),
            claim(2, match="similar"),
            claim(3, match="same"),
        ]

        shown = vet(claims, results).comparables

        assert [item.match for item in shown] == ["same", "same", "similar", "similar"]

    def test_then_the_more_relevant_search_result_first(self) -> None:
        results = self.results(4)

        shown = vet([claim(n) for n in range(4)], results).comparables

        # Scores rise with the index here, so the last is the most relevant.
        assert [item.url.rsplit("/", 2)[1] for item in shown] == [
            "item-3",
            "item-2",
            "item-1",
            "item-0",
        ]

    def test_results_the_search_ranked_alike_keep_the_order_it_gave(self) -> None:
        results = [
            result(n, url=f"https://www.depop.com/products/i{n}/", score=0.5) for n in range(5)
        ]

        shown = vet([claim(n) for n in range(5)], results).comparables

        assert [item.url.rsplit("/", 2)[1] for item in shown] == ["i0", "i1", "i2", "i3", "i4"]

    def test_at_most_twelve_comparables(self) -> None:
        results = self.results(MAX_COMPARABLES + 5)

        vetted = vet([claim(n) for n in range(len(results))], results)

        assert len(vetted.comparables) == 12

    def test_the_twelve_kept_are_the_best_twelve(self) -> None:
        results = self.results(15)
        # The three oldest-ranked are "same", and must survive the cut over
        # twelve "similar" results with a better search score.
        claims = [claim(n, match="same" if n < 3 else "similar") for n in range(15)]

        shown = vet(claims, results).comparables

        assert len(shown) == 12
        assert [item.match for item in shown[:3]] == ["same"] * 3
        kept = {item.url.rsplit("/", 2)[1] for item in shown}
        assert {"item-0", "item-1", "item-2"} <= kept

    def test_at_most_six_retail(self) -> None:
        results = [
            retail_result(n, url=f"https://shop{n}.example.com/crew", score=n / 100)
            for n in range(MAX_RETAIL + 4)
        ]

        vetted = vet([retail_claim(n) for n in range(len(results))], results)

        assert len(vetted.retail) == 6

    def test_what_is_cut_by_the_cap_is_not_counted_as_refused(self) -> None:
        # They were usable, just not needed. "Not comparable" would be a lie.
        results = self.results(15)

        vetted = vet([claim(n) for n in range(15)], results)

        assert counts(vetted) == (0, 0, 0)

    def test_retail_is_ordered_the_same_way(self) -> None:
        results = [
            retail_result(0, url="https://a.example.com/crew", score=0.9),
            retail_result(1, url="https://b.example.com/crew", score=0.1),
            retail_result(2, url="https://c.example.com/crew", score=0.5),
        ]
        claims = [
            retail_claim(0, match="similar"),
            retail_claim(1, match="same"),
            retail_claim(2, match="same"),
        ]

        shown = vet(claims, results, brand="Nike").retail

        assert [item.seller for item in shown] == [
            "c.example.com",
            "b.example.com",
            "a.example.com",
        ]


class TestWhatItReturnsIsTheContract:
    def test_everything_shown_is_a_valid_comparable_or_reference(self) -> None:
        results = [result(0, text=f"{PAGE} Sold"), retail_result(1)]

        vetted = vet([claim(0, sold=True, condition="Used - Excellent"), retail_claim(1)], results)

        assert all(isinstance(item, Comparable) for item in vetted.comparables)
        assert all(isinstance(item, RetailReference) for item in vetted.retail)
        assert vetted.comparables[0].sold is True
        assert vetted.comparables[0].condition == "Used - Excellent"

    def test_the_result_serialises_without_nulls(self) -> None:
        vetted = vet([claim(why=None)], [result()])

        wire = vetted.comparables[0].to_wire()

        assert None not in wire.values()
        assert wire["currency"] == "USD"
        assert set(wire) == {"title", "url", "price", "currency", "match"}
