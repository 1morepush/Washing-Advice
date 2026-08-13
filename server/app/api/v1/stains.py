"""Advising on a stain, from a description and optionally a photograph.

Outside `VisionPipeline` for the same reason `/machine` is: the answer rests on
what the model knows about a substance and a fabric, not on reading an image.
The photograph is optional and corroborating — the user's own account of what
was spilled is the better evidence, and a close-up of a mark on fabric is
genuinely hard to identify.

What this endpoint does **not** do is decide whether the treatment is safe for
the garment. It has a summary of the care label, not the label, and the real
constraints live in `wardrobe_core`. The app vets every step against them
before showing any of it, and reports what it removed. Doing it here as well
would put the same judgement in two places and let them drift.
"""

from __future__ import annotations

import time

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.api.v1.dependencies import get_stain_adviser
from app.config import Settings, get_settings
from app.core.errors import ProviderUnavailableError
from app.core.limits import check_image
from app.schemas.scan import ScanDiagnostics
from app.schemas.stains import StainAdviceRequest, StainAdviceResponse
from app.services.ai.base import ProviderError, ScanImage
from app.services.stains.base import StainAdviser

router = APIRouter(prefix="/care", tags=["stains"])


@router.post(
    "/stain",
    response_model=StainAdviceResponse,
    response_model_exclude_none=True,
    summary="How to treat a stain on a particular garment",
)
async def advise_on_stain(
    substance: str = Form(...),
    fabric: str = Form(...),
    care: str = Form(...),
    color: str | None = Form(default=None),
    note: str | None = Form(default=None),
    photo: UploadFile | None = File(default=None),
    adviser: StainAdviser = Depends(get_stain_adviser),
    settings: Settings = Depends(get_settings),
) -> StainAdviceResponse:
    started = time.perf_counter()

    image: ScanImage | None = None
    if photo is not None:
        data = await photo.read()
        # An empty part is what a multipart client sends for "no file", and it
        # is not a failure worth reporting — the description alone is enough.
        if data:
            mime_type = check_image(data, photo.content_type, max_bytes=settings.max_image_bytes)
            image = ScanImage(data=data, mime_type=mime_type)

    request = StainAdviceRequest(
        substance=substance,
        fabric=fabric,
        care=care,
        color=color,
        note=note,
    )

    try:
        result = await adviser.advise(request, image)
    except ProviderError as error:
        raise ProviderUnavailableError(str(error)) from error

    return StainAdviceResponse(
        result=result,
        diagnostics=ScanDiagnostics(
            stages_run=[adviser.name],
            stage_answered=adviser.name,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ),
    )
