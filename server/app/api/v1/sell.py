"""Selling a garment on Depop.

Depop has no public API, so nothing here posts a listing: these endpoints write
down what a buyer needs to know, and look up what such a thing costs, and the
app puts both in front of the seller to correct and paste. See
docs/adr/0009-selling-on-depop.md for why prices come from a cited web search
rather than from a model's memory.

What comes back is *proposals*. Nothing here decides a price: turning
comparable listings into an asking price, and an asking price into what the
seller is paid after fees, is arithmetic in the domain core, where it is tested.
The same division as everywhere else — the model perceives, something else
judges.
"""

from __future__ import annotations

import time

from fastapi import APIRouter, Depends, File, Form, UploadFile
from pydantic import ValidationError

from app.api.v1.dependencies import get_listing_describer, get_price_searcher
from app.config import Settings, get_settings
from app.core.errors import InvalidFieldError, from_provider_error
from app.core.limits import MAX_LISTING_PHOTOS, check_image, check_image_count
from app.schemas.scan import ScanDiagnostics
from app.schemas.selling import (
    DescribeContext,
    DescribeResponse,
    PriceSearchRequest,
    PriceSearchResponse,
)
from app.services.ai.base import ProviderError, ScanImage
from app.services.selling.base import DescribeRequest, ListingDescriber
from app.services.selling.prices import PriceSearcher

router = APIRouter(prefix="/sell", tags=["sell"])


def _read_context(raw: str | None) -> DescribeContext | None:
    """The `context` form field, parsed and checked against the contract.

    Absent or blank is no context. Anything else must be the JSON object the
    schema describes, and one that is not is refused with the key at fault
    rather than ignored: a context that was quietly dropped would send a garment
    whose brand somebody typed back to be guessed at from its photographs.
    """
    if raw is None or not raw.strip():
        return None

    try:
        return DescribeContext.model_validate_json(raw)
    except ValidationError as error:
        problems = "; ".join(
            f"{'.'.join(str(step) for step in found['loc']) or 'context'}: {found['msg']}"
            for found in error.errors(include_input=False, include_url=False)
        )
        raise InvalidFieldError(
            f"the 'context' field is not valid: {problems}",
            hint=(
                "Send context as a JSON object such as "
                '{"known": {"brand": "Nike", "sizeLabel": "M"}, "notes": "worn twice"}.'
            ),
        ) from error


@router.post(
    "/describe",
    response_model=DescribeResponse,
    # A field the photographs did not show must be absent, never null: the
    # contract reads absence as "ask the seller" and a null as an answer.
    response_model_exclude_none=True,
    summary="Write the facts of a listing from photographs",
)
async def describe_listing(
    images: list[UploadFile] = File(
        ...,
        description=(
            "One to four photographs of one garment. A front and a back read "
            "better than one, and a close-up of the brand label or the size "
            "label is what lets them be reported at all."
        ),
    ),
    context: str | None = Form(
        default=None,
        description=(
            "JSON, when the garment is already in the wardrobe: what the app "
            "knows about it (`known`) and anything the person typed (`notes`). "
            "Known facts outrank what the photographs seem to show."
        ),
    ),
    settings: Settings = Depends(get_settings),
    describer: ListingDescriber = Depends(get_listing_describer),
) -> DescribeResponse:
    check_image_count(len(images), maximum=MAX_LISTING_PHOTOS)
    parsed_context = _read_context(context)

    scan_images = []
    for upload in images:
        data = await upload.read()
        mime_type = check_image(data, upload.content_type, max_bytes=settings.max_image_bytes)
        scan_images.append(ScanImage(data=data, mime_type=mime_type))

    started = time.perf_counter()
    try:
        facts = await describer.describe(
            DescribeRequest(images=scan_images, context=parsed_context)
        )
    except ProviderError as error:
        raise from_provider_error(error) from error

    return DescribeResponse(
        result=facts,
        diagnostics=ScanDiagnostics(
            stages_run=[describer.name],
            stage_answered=describer.name,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ),
    )


@router.post(
    "/prices",
    response_model=PriceSearchResponse,
    # `searchedAt` and `provider` exist only when a search ran, and a null for
    # either would read as a search that ran and reported nothing.
    response_model_exclude_none=True,
    summary="Look up what a garment sells for",
)
async def look_up_prices(
    request: PriceSearchRequest,
    searcher: PriceSearcher = Depends(get_price_searcher),
) -> PriceSearchResponse:
    """Comparable Depop listings and the price new, each found on a page we can cite.

    **Never an HTTP error for a search problem.** A listing can be written
    without prices, so a search that is not configured, has used up its free
    allowance, or failed answers 200 with that in `status` and nothing found.
    The only errors are a request that is not the contract's shape (422) and a
    server that is misconfigured as a whole (503, like every other endpoint).
    """
    started = time.perf_counter()
    outcome = await searcher.search(request)

    return PriceSearchResponse(
        result=outcome.result,
        diagnostics=ScanDiagnostics(
            stages_run=outcome.stages_run,
            stage_answered=outcome.stage_answered,
            served_from_cache=outcome.from_cache,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ),
    )
