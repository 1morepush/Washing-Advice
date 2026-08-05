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

from app.api.v1.dependencies import get_background_remover
from app.config import Settings, get_settings
from app.core.errors import ScanFailedError
from app.core.limits import check_image
from app.services.images.cutout import BackgroundRemover, CutoutError

router = APIRouter(prefix="/image", tags=["image"])


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
    data = await image.read()
    check_image(data, image.content_type, max_bytes=settings.max_image_bytes)

    try:
        result = remover.remove(data)
    except CutoutError as error:
        raise ScanFailedError(
            str(error),
            hint="Lay the garment flat against a plain, evenly lit background.",
        ) from error

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
