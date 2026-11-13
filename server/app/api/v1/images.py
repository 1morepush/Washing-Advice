"""Image processing.

Separate from `/scan` on purpose. The scan endpoints turn pixels into *facts*
— a type, a composition, a care constraint — and their answers are small JSON
that the app stores forever. This one turns pixels into other pixels, and its
answer is a large binary the app stores as a file.

Folding it into the garment scan would mean base64 in a JSON body, a response
an order of magnitude larger, and no way to retry the cutout without paying for
the identification again. It also means the cutout can be regenerated later —
with a better remover — from a photograph the app already has, without
re-running any inference.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, Response, UploadFile
from fastapi.concurrency import run_in_threadpool

from app.api.v1.dependencies import get_background_remover
from app.config import Settings, get_settings
from app.core.errors import RateLimitedError, ScanFailedError
from app.core.limits import check_image
from app.services.images.cutout import BackgroundRemover, CutoutError

router = APIRouter(prefix="/image", tags=["image"])

_in_flight = 0
"""Cutouts accepted and not yet answered, in this process.

Bounded by `cutout_max_waiting`. Inference is one at a time, so anything more
than a couple waiting is only memory: each waiting request holds its upload.
Touched only from the event loop, so it needs no lock.
"""

_BUSY_RETRY_SECONDS = 4.0


@router.post(
    "/cutout",
    summary="Remove a garment's background",
    response_class=Response,
    responses={
        200: {
            "content": {"image/png": {}},
            "description": "The garment on a transparent background.",
        }
    },
)
async def cutout(
    image: UploadFile = File(
        ...,
        description="A garment photographed against a plain background.",
    ),
    settings: Settings = Depends(get_settings),
    remover: BackgroundRemover = Depends(get_background_remover),
) -> Response:
    global _in_flight
    if _in_flight >= settings.cutout_max_waiting:
        raise RateLimitedError(
            "The server is busy cutting out other photographs.",
            retry_after=_BUSY_RETRY_SECONDS,
            hint="Try again in a few seconds.",
        )
    _in_flight += 1
    try:
        data = await image.read()
        check_image(data, image.content_type, max_bytes=settings.max_image_bytes)
        # Off the event loop: a cutout takes a second or more of CPU, and
        # health checks and other requests must keep being answered meanwhile.
        result = await run_in_threadpool(remover.remove, data)
    except CutoutError as error:
        raise ScanFailedError(
            str(error),
            hint="Lay the garment flat against a plain, evenly lit background.",
        ) from error
    finally:
        _in_flight -= 1

    if not result.is_plausible:
        # Refused rather than returned. A "cutout" that is really the whole
        # photograph, or a scrap of one, is worse than none at all — it looks
        # like the feature worked, and the user stops checking.
        raise ScanFailedError(
            "the garment could not be told apart from its background",
            hint=(
                "Use a background that contrasts with the garment, and make "
                "sure the whole item is inside the frame."
            ),
        )

    return Response(
        content=result.png,
        media_type="image/png",
        headers={
            # Reported so the app can log and display how well it did without
            # decoding the PNG to find out.
            "X-Cutout-Coverage": f"{result.coverage:.4f}",
            "X-Cutout-Width": str(result.width),
            "X-Cutout-Height": str(result.height),
        },
    )
