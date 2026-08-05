"""The scan endpoints.

Three routes, one per kind of scan. Each does the same three things: validate
the upload, run the pipeline, return the result with diagnostics. All the
interesting behaviour lives in the pipeline; these are deliberately thin.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.api.v1.dependencies import get_pipeline
from app.config import Settings, get_settings
from app.core.errors import ScanFailedError
from app.core.limits import check_image, check_image_count
from app.schemas.scan import (
    CareTagScanResponse,
    CareTagScanResult,
    GarmentScanResponse,
    GarmentScanResult,
    PileScanResponse,
    PileScanResult,
    ScanKind,
)
from app.services.ai.base import ScanImage, ScanRequest
from app.services.ai.pipeline import VisionPipeline

router = APIRouter(prefix="/scan", tags=["scan"])


async def _read_image(upload: UploadFile, settings: Settings) -> ScanImage:
    data = await upload.read()
    mime_type = check_image(data, upload.content_type, max_bytes=settings.max_image_bytes)
    return ScanImage(data=data, mime_type=mime_type)


@router.post(
    "/garment",
    response_model=GarmentScanResponse,
    # An unstated care field must be absent, never null: the core reads
    # absence as "fill this from the rule table" and a null would be
    # decoded as a stated value. See docs/adr/0004-label-overrides-rules.md.
    response_model_exclude_none=True,
    summary="Identify a single garment",
)
async def scan_garment(
    images: list[UploadFile] = File(
        ...,
        description="Photographs of one garment. A front and a back read better than one shot.",
    ),
    brand: str | None = Form(default=None),
    settings: Settings = Depends(get_settings),
    pipeline: VisionPipeline = Depends(get_pipeline),
) -> GarmentScanResponse:
    check_image_count(len(images), maximum=settings.max_images_per_request)
    scan_images = [await _read_image(upload, settings) for upload in images]

    outcome = await pipeline.run(
        ScanRequest(kind=ScanKind.GARMENT, images=scan_images, known_brand=brand)
    )

    if not isinstance(outcome.result, GarmentScanResult):
        raise ScanFailedError(
            "the garment could not be identified from these photographs",
            hint="Try a well-lit photo of the whole garment against a plain background.",
        )

    return GarmentScanResponse(result=outcome.result, diagnostics=outcome.diagnostics)


@router.post(
    "/care-tag",
    response_model=CareTagScanResponse,
    response_model_exclude_none=True,
    summary="Read a care label",
)
async def scan_care_tag(
    image: UploadFile = File(..., description="A close-up of the care label."),
    brand: str | None = Form(default=None),
    settings: Settings = Depends(get_settings),
    pipeline: VisionPipeline = Depends(get_pipeline),
) -> CareTagScanResponse:
    scan_image = await _read_image(image, settings)

    outcome = await pipeline.run(
        ScanRequest(kind=ScanKind.CARE_TAG, images=[scan_image], known_brand=brand)
    )

    if not isinstance(outcome.result, CareTagScanResult):
        raise ScanFailedError(
            "the care label could not be read",
            hint="Fill the frame with the label and keep it flat and in focus.",
        )

    return CareTagScanResponse(result=outcome.result, diagnostics=outcome.diagnostics)


@router.post(
    "/pile",
    response_model=PileScanResponse,
    response_model_exclude_none=True,
    summary="Detect every garment in a pile of laundry",
)
async def scan_pile(
    image: UploadFile = File(..., description="One photo of the whole pile."),
    settings: Settings = Depends(get_settings),
    pipeline: VisionPipeline = Depends(get_pipeline),
) -> PileScanResponse:
    scan_image = await _read_image(image, settings)

    outcome = await pipeline.run(ScanRequest(kind=ScanKind.PILE, images=[scan_image]))

    if not isinstance(outcome.result, PileScanResult):
        raise ScanFailedError(
            "no garments could be identified in this photograph",
            hint="Spread the pile out so fewer items overlap, then try again.",
        )

    return PileScanResponse(result=outcome.result, diagnostics=outcome.diagnostics)
