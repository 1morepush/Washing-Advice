"""Looking a garment over for wear.

Beside the stain endpoint under `/care`, because it is the same kind of
question: something is wrong with this particular garment, here is a
photograph, what is it. It is not under `/scan` because nothing here is being
identified — the app already knows what the garment is and says so in the
request.

What comes back is *observations*, and nothing here records anything. A wear
observation changes the grade, can push a garment to end-of-life, and changes
how the thing is washed from the next load onward, so `ConditionReview` in the
core decides which are worth putting to the user and the user decides the rest.
The same division as everywhere else: the model perceives, something else
judges.
"""

from __future__ import annotations

import time

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.api.v1.dependencies import get_condition_reader
from app.config import Settings, get_settings
from app.core.errors import ProviderUnavailableError
from app.core.limits import check_image, check_image_count
from app.schemas.condition import ConditionResponse
from app.schemas.scan import ScanDiagnostics
from app.services.ai.base import ProviderError, ScanImage
from app.services.condition.base import ConditionReader, ConditionRequest

router = APIRouter(prefix="/care", tags=["condition"])


@router.post(
    "/condition",
    response_model=ConditionResponse,
    response_model_exclude_none=True,
    summary="Look a garment over for wear",
)
async def read_condition(
    images: list[UploadFile] = File(
        ...,
        description=(
            "Photographs of one garment. Wear is not evenly distributed — "
            "cuffs, underarms, the seat — so more angles read better."
        ),
    ),
    garment: str = Form(..., description="What it is, e.g. 'Navy wool jumper'."),
    fabric: str | None = Form(default=None),
    known: str | None = Form(
        default=None,
        description="Wear already recorded, so it is not reported again.",
    ),
    settings: Settings = Depends(get_settings),
    reader: ConditionReader = Depends(get_condition_reader),
) -> ConditionResponse:
    check_image_count(len(images), maximum=settings.max_images_per_request)

    scan_images = []
    for upload in images:
        data = await upload.read()
        mime_type = check_image(data, upload.content_type, max_bytes=settings.max_image_bytes)
        scan_images.append(ScanImage(data=data, mime_type=mime_type))

    started = time.perf_counter()
    try:
        result = await reader.read(
            ConditionRequest(
                images=scan_images,
                garment=garment,
                fabric=fabric,
                known=known,
            )
        )
    except ProviderError as error:
        raise ProviderUnavailableError(str(error)) from error

    return ConditionResponse(
        result=result,
        diagnostics=ScanDiagnostics(
            stages_run=[reader.name],
            stage_answered=reader.name,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ),
    )
