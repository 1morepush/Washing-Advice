"""A deterministic stylist, for tests and for running without a key.

Not a stub returning one canned outfit. It pairs real garments from the
wardrobe it is given, so the vetting downstream has something with structure to
check — and it deliberately produces one *bad* proposal when it can, because a
fake that only ever returned valid outfits would make the checking layer look
tested when nothing had exercised it.
"""

from __future__ import annotations

from app.schemas.style import ProposedOutfit, StyleCandidate, StyleRequest


def _of(wardrobe: list[StyleCandidate], category: str) -> list[StyleCandidate]:
    return [item for item in wardrobe if item.category == category]


class FakeStylist:
    """Pairs tops with bottoms in order, and always the same way."""

    @property
    def name(self) -> str:
        return "fake"

    async def propose(self, request: StyleRequest) -> list[ProposedOutfit]:
        tops = _of(request.wardrobe, "Tops")
        bottoms = _of(request.wardrobe, "Bottoms")
        shoes = _of(request.wardrobe, "Footwear")

        outfits: list[ProposedOutfit] = []
        for index in range(min(len(tops), len(bottoms), request.count)):
            top = tops[index]
            bottom = bottoms[index]
            ids = [top.id, bottom.id]
            if shoes:
                ids.append(shoes[index % len(shoes)].id)

            outfits.append(
                ProposedOutfit(
                    item_ids=ids,
                    rationale=(
                        f"The {bottom.name.lower()} keep the "
                        f"{top.name.lower()} from reading as formal, which "
                        f"suits {request.occasion}."
                    ),
                )
            )

        # One structurally impossible outfit, so the layer that refuses them is
        # exercised by default rather than only where a test remembers to ask.
        if len(tops) >= 2 and bottoms:
            outfits.append(
                ProposedOutfit(
                    item_ids=[tops[0].id, tops[1].id, bottoms[0].id],
                    rationale="Two tops at once, which is not a thing.",
                )
            )

        return outfits
