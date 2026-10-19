# 9. Selling on Depop: a model reads, a search finds, the core prices

Status: accepted

## Context

Clothes that are no longer worn are worth more sold than kept, and listing one
on Depop well takes longer than it should: a description that buyers find
(brand, item and style words first), every field filled in because the filters
drive search, and a price that is neither a giveaway nor a listing that never
sells. Pricing well means looking up what the same thing costs new and what it
actually sells for secondhand.

The app already turns a photograph into facts about a garment, and for a
garment already in the wardrobe it knows more than any photograph shows: the
brand someone typed, the size label, the fabric off the care label, how often
it has been worn and what wear has been reported on it.

Three things about the outside world shaped the design.

- **Depop has no public API** for searching listings or creating them. Its own
  web endpoints are not offered for third-party use. So the app cannot post a
  listing, and it should not scrape Depop.
- **Google Search grounding is not free on the models this app can use.** The
  Gemini API offers Grounding with Google Search free of charge only on the 2.5
  Flash models, and Google now limits those to keys that used them before. On
  every Gemini 3 model it is a paid feature. It also carries display terms
  (Google's own search-suggestion chip, rendered as supplied, beside every
  grounded answer) that a Flutter screen would need a web view to honour.
- **The project rule is that AI usage stays free.**

## Decision

**Photographs to a draft (server, free-tier Gemini).** `POST /v1/sell/describe`
takes the photographs, and for a garment already owned, what the app knows,
and returns a draft: a title line, brand, colours, material and size only when
a label shows them, style words, visible flaws, and two search phrases — one
for Depop, one for the price new. A known fact outranks a fresh reading.

**Prices from a search the server can cite (server, Tavily).**
`POST /v1/sell/prices` runs two web searches through Tavily — a search API with
a free monthly allowance and no card — one restricted to depop.com and one that
excludes resale sites. A free-tier Gemini call then reads only those results
and says which are the same item or a similar one, and at what price. Nothing
it says is trusted on its own:

- a comparable's link is taken from the search result, never from the model;
- its price must appear in the text of that page, or it is dropped;
- anything not in US dollars is dropped rather than converted;
- what was dropped is counted and shown, so an empty list reads as "nothing
  usable" rather than "nothing looked".

Without a Tavily key the call still answers, with status `notConfigured`, and
the app falls back to links that open the same searches on Depop, eBay's sold
listings and Google Shopping, and to prices typed in by hand.

**The price is arithmetic, in the core.** Turning comparables into an asking
price, and an asking price into what the seller is paid, is deterministic,
tested Dart in `packages/wardrobe_core` — the same place every laundry
decision lives, for the same reason: it is the part someone acts on. Sold
prices outrank asking prices; an asking price is marked up to leave room for
offers only when it is built on what things sold for; a used garment is never
priced above its retail price new; the result is rounded the way listings are
priced; Depop's fees are subtracted to show the net. Every step is a sentence
on screen.

**Listings live on the phone.** A draft, its status (draft, listed, sold) and
its last price search are stored locally beside the wardrobe and are not
synced. A garment sold from the wardrobe can be marked sold there, which is a
lifecycle state the wardrobe already had.

## Consequences

- Live prices need a free Tavily key on the server. Two searches a listing is
  about five hundred listings a month on the free allowance.
- Comparables are only as good as what the search finds indexed. Depop pages
  that are not indexed are invisible to it, and a sold listing is only marked
  sold when its page says so. The links to Depop's and eBay's own search are
  always there for the cases the search misses.
- "Looks similar" is judged from a description of the photographs, not by
  image similarity. A free visual search service does not exist for this.
- The search phrases leave the server for Tavily; the photographs do not. The
  photographs go to Gemini, as every scan's do, on the same free-tier terms the
  README describes.
- Depop's fees (3.3% plus $0.45 per sale in the US, with no selling fee since
  2024) are constants in one place in the core, dated, and shown with the net
  so a change is one edit and visible when it is wrong.
- Depop's condition labels and colour names are mirrored in one table in the
  core. The app suggests and copies them; the person still picks them in Depop.
