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

import json
import time
from collections.abc import AsyncIterator

from fastapi import APIRouter, Depends, File, Form, UploadFile
from fastapi.responses import StreamingResponse

from app.api.v1.dependencies import get_stain_adviser
from app.config import Settings, get_settings
from app.core.errors import ProviderUnavailableError
from app.core.limits import check_image
from app.schemas.scan import ScanDiagnostics
from app.schemas.stains import StainAdviceRequest, StainAdviceResponse
from app.services.ai.base import ProviderError, ScanImage
from app.services.stains.base import Identified, Proposed, StainAdviser

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
    request = StainAdviceRequest(
        substance=substance,
        fabric=fabric,
        care=care,
        color=color,
        note=note,
    )
    image = await _read_photo(photo, settings)

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


@router.post(
    "/stain/stream",
    summary="The same advice, sent as each step is written",
    response_class=StreamingResponse,
)
async def stream_stain_advice(
    substance: str = Form(...),
    fabric: str = Form(...),
    care: str = Form(...),
    color: str | None = Form(default=None),
    note: str | None = Form(default=None),
    photo: UploadFile | None = File(default=None),
    adviser: StainAdviser = Depends(get_stain_adviser),
    settings: Settings = Depends(get_settings),
) -> StreamingResponse:
    """Server-sent events, one per finished step.

    A separate route rather than a flag on `/stain`, because the response is a
    different media type and a different failure model — see `_events` for the
    second part, which is the awkward one.

    The non-streaming endpoint stays. It is what a caller wanting one
    all-or-nothing answer should use, it is what the retry-on-unparseable-JSON
    path lives on, and an app talking to an older server needs it to exist.
    """
    started = time.perf_counter()
    request = StainAdviceRequest(
        substance=substance,
        fabric=fabric,
        care=care,
        color=color,
        note=note,
    )
    # Before the response starts, so a photo that is too large is still an
    # ordinary 4xx rather than an error smuggled inside a 200.
    image = await _read_photo(photo, settings)

    return StreamingResponse(
        _events(adviser, request, image, started),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            # Nginx and friends buffer a proxied response by default, which
            # would hold every step until the last one and quietly undo the
            # entire point of this endpoint.
            "X-Accel-Buffering": "no",
        },
    )


async def _events(
    adviser: StainAdviser,
    request: StainAdviceRequest,
    image: ScanImage | None,
    started: float,
) -> AsyncIterator[str]:
    """The event sequence, including the failures.

    Errors are sent **in band** rather than raised. By the time a provider
    fails the 200 and the headers are long gone, so there is no status code
    left to fail with — a raise here would truncate the stream and leave the
    client to guess whether it had the whole treatment or half of it. Half a
    treatment presented as a whole one is the dangerous outcome on this
    endpoint: it ends wherever the model stopped, which may be before the step
    that says to check the mark before it goes near heat.

    So the client is told, and the contract is that a stream without a `done`
    is not a complete answer.
    """
    try:
        async for event in adviser.stream(request, image):
            match event:
                case Identified(text=text):
                    yield _sse({"type": "identified", "identifiedAs": text})
                case Proposed(step=step):
                    yield _sse(
                        {
                            "type": "step",
                            "step": step.model_dump(by_alias=True, exclude_none=True),
                        }
                    )
    except ProviderError as error:
        yield _sse({"type": "error", "message": str(error)})
        return

    yield _sse(
        {
            "type": "done",
            "diagnostics": ScanDiagnostics(
                stages_run=[adviser.name],
                stage_answered=adviser.name,
                elapsed_ms=int((time.perf_counter() - started) * 1000),
            ).model_dump(by_alias=True, exclude_none=True),
        }
    )


def _sse(payload: dict[str, object]) -> str:
    """One event. The blank line is what ends it, not the newline."""
    return f"data: {json.dumps(payload)}\n\n"


async def _read_photo(photo: UploadFile | None, settings: Settings) -> ScanImage | None:
    """The optional corroborating photograph, if one really came."""
    if photo is None:
        return None

    data = await photo.read()
    # An empty part is what a multipart client sends for "no file", and it is
    # not a failure worth reporting — the description alone is enough.
    if not data:
        return None

    mime_type = check_image(data, photo.content_type, max_bytes=settings.max_image_bytes)
    return ScanImage(data=data, mime_type=mime_type)
