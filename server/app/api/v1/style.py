"""Outfit ideas from the wardrobe the caller sends.

Stateless, like every other endpoint here: the server holds no wardrobe and is
told the garments to choose from on each request. That keeps the domain in one
language and means this endpoint can be pointed at somebody else's wardrobe
without knowing anything about them.

What comes back is *proposals*. Nothing here checks that the ids are real or
that the outfit makes structural sense — `StyleVetting` in the core does that,
against the wardrobe it already holds, for the same reason stain advice is
vetted there rather than here: the app has the facts and the server has a
summary.
"""

from __future__ import annotations

import time

from fastapi import APIRouter, Depends

from app.api.v1.dependencies import get_stylist
from app.core.errors import ProviderUnavailableError
from app.schemas.scan import ScanDiagnostics
from app.schemas.style import StyleRequest, StyleResponse
from app.services.ai.base import ProviderError
from app.services.style.base import Stylist

router = APIRouter(prefix="/style", tags=["style"])


@router.post(
    "/outfits",
    response_model=StyleResponse,
    response_model_exclude_none=True,
    summary="Propose outfits from a wardrobe",
)
async def propose_outfits(
    request: StyleRequest,
    stylist: Stylist = Depends(get_stylist),
) -> StyleResponse:
    started = time.perf_counter()

    try:
        outfits = await stylist.propose(request)
    except ProviderError as error:
        raise ProviderUnavailableError(str(error)) from error

    return StyleResponse(
        result=outfits,
        diagnostics=ScanDiagnostics(
            stages_run=[stylist.name],
            stage_answered=stylist.name,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ),
    )
