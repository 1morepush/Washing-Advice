"""A deterministic stylist, for tests and for running without a key.

Not a stub returning one canned outfit. It pairs real garments from the
wardrobe it is given, so the vetting downstream has something with structure to
check — and it deliberately produces one *bad* proposal when it can, because a
fake that only ever returned valid outfits would make the checking layer look
tested when nothing had exercised it.
"""

from __future__ import annotations

from app.schemas.style import (
    ProposedOutfit,
    ProposedPiece,
    StyleAnswer,
    StyleCandidate,
    StyleRequest,
)


def _of(wardrobe: list[StyleCandidate], category: str) -> list[StyleCandidate]:
    return [item for item in wardrobe if item.category == category]


class FakeStylist:
    """Pairs tops with bottoms in order, and always the same way."""

    @property
    def name(self) -> str:
        return "fake"

    async def propose(self, request: StyleRequest) -> StyleAnswer:
        return StyleAnswer(
            outfits=await self._outfits(request),
            pieces=self._pieces(request) if request.suggest_gaps else [],
        )

    def _pieces(self, request: StyleRequest) -> list[ProposedPiece]:
        """One usable suggestion, and two the client must throw away.

        Same principle as the impossible outfit below: a fake that only ever
        returned valid answers would leave the checking layer looking tested
        when nothing had exercised it. The unanchored piece and the invented
        type are the two refusals worth having covered by default.
        """
        tops = _of(request.wardrobe, "Tops")
        if not tops:
            return []

        allowed = request.stylable_types or ["Jeans"]
        return [
            ProposedPiece(
                type=allowed[0],
                colors=["dark blue"],
                pairs_with=[tops[0].id],
                rationale=(
                    f"Something with weight under the {tops[0].name.lower()} "
                    "would stop it reading as an afterthought."
                ),
            ),
            ProposedPiece(
                type=allowed[0],
                colors=["olive"],
                pairs_with=[],
                rationale="Goes with nothing of theirs, so it is not advice.",
            ),
            ProposedPiece(
                type="gorpcore silhouette",
                colors=["taupe"],
                pairs_with=[tops[0].id],
                rationale="Not a thing anybody can go and look for.",
            ),
        ]

    async def _outfits(self, request: StyleRequest) -> list[ProposedOutfit]:
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
