"""What the seller already knows, laid over what the photographs showed.

A garment in the wardrobe has facts no photograph can match: the brand somebody
typed, the size off the label, the fabric off the care label. They go into the
prompt as given, but a prompt is a request and a model is free to disagree with
it, so they are also laid over the reading afterwards. The seller's word is not
a candidate the model gets to weigh against its own.

Each known fact becomes `userEdited` at full confidence — the strongest
provenance there is, which is how the rest of the system already treats a value
a person typed — so nothing downstream is tempted to ask "is this really Nike?"
of a brand the seller wrote.

The title and the search phrases are the one place a fact can be contradicted
without being overwritten. A model that read an Adidas logo on a garment the
seller says is Nike will have written "Adidas" into both, and a draft whose
brand field says Nike and whose title says Adidas is worse than either.
"""

from __future__ import annotations

from app.schemas.common import Confident, Provenance
from app.schemas.limits import clamp
from app.schemas.selling import KnownFacts, ListingFacts, SearchQueries
from app.services.selling.brands import mentions_brand, replace_brand

_TITLE_LIMIT = 80
_PHRASE_LIMIT = 120
_SHORTEST_LINE = 3


def apply_known(facts: ListingFacts, known: KnownFacts | None) -> ListingFacts:
    """The reading with every known fact in place of what the model made of it."""
    if known is None:
        return facts

    brand = facts.brand
    title = facts.title
    queries = facts.search_queries
    if known.brand:
        brand = Confident[str](
            value=known.brand,
            confidence=1.0,
            source=Provenance.USER_EDITED,
        )
        model_brand = facts.brand.value if facts.brand else None
        title = _naming(title, model_brand, known.brand, limit=_TITLE_LIMIT)
        queries = SearchQueries(
            depop=_naming(queries.depop, model_brand, known.brand, limit=_PHRASE_LIMIT),
            retail=_naming(queries.retail, model_brand, known.brand, limit=_PHRASE_LIMIT),
        )

    size = facts.size_on_tag
    if known.size_label:
        size = Confident[str](
            value=known.size_label,
            confidence=1.0,
            source=Provenance.USER_EDITED,
        )

    return ListingFacts(
        title=title,
        item_type=known.item_type or facts.item_type,
        brand=brand,
        colors=known.colors or facts.colors,
        material=known.material or facts.material,
        size_on_tag=size,
        style_words=facts.style_words,
        era=facts.era,
        visible_flaws=facts.visible_flaws,
        search_queries=queries,
    )


def _naming(line: str, model_brand: str | None, known_brand: str, *, limit: int) -> str:
    """[line] made to name the seller's brand, and not another one.

    Left alone when it already does. Otherwise the brand the model read is taken
    out wherever it stood and the seller's put at the front, which is where a
    title keeps its brand: it is the first word a buyer's search weighs, and a
    brand at the front is never the part that gets cut when the line is long.
    """
    if mentions_brand(line, known_brand):
        return line

    rest = line
    if model_brand:
        removed = replace_brand(line, model_brand, "")
        if removed is not None:
            rest = " ".join(removed.split())

    named = f"{known_brand} {rest}".strip()
    if len(named) < _SHORTEST_LINE:
        # The line was only the wrong brand, and the right one is two letters.
        named = f"{known_brand} {line}"

    # Cut at a word boundary if putting the brand in made it too long; the tail
    # is the search words, the least important part to lose.
    return clamp(named, limit) or line
