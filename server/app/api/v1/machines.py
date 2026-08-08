"""Identifying a specific washer or dryer, by brand and model text.

Separate from `/scan` for the same reason `/image/cutout` is: this answers a
different kind of question than the vision pipeline does. There is no photo
here at all — the answer rests on what the model already knows about a named
appliance — so it is wired up on its own, outside `VisionPipeline`, the same
way cutout removal is.
"""

from __future__ import annotations

import time

from fastapi import APIRouter, Depends

from app.api.v1.dependencies import get_machine_identifier
from app.core.errors import MachineNotIdentifiedError, ProviderUnavailableError
from app.schemas.machines import (
    DryerIdentifyResponse,
    MachineIdentifyRequest,
    WasherIdentifyResponse,
)
from app.schemas.scan import ScanDiagnostics
from app.services.ai.base import ProviderError
from app.services.machines.base import MachineIdentifier
from app.services.machines.gemini_identifier import NotIdentifiedError

router = APIRouter(prefix="/machine", tags=["machines"])

_NOT_IDENTIFIED_HINT = "Try just the brand, or use the generic profile for it in Settings instead."


@router.post(
    "/washer",
    response_model=WasherIdentifyResponse,
    response_model_exclude_none=True,
    summary="Identify a washing machine's real programme line-up",
)
async def identify_washer(
    body: MachineIdentifyRequest,
    identifier: MachineIdentifier = Depends(get_machine_identifier),
) -> WasherIdentifyResponse:
    started = time.perf_counter()
    try:
        result = await identifier.identify_washer(body.brand, body.model)
    except NotIdentifiedError as error:
        raise MachineNotIdentifiedError(str(error), hint=_NOT_IDENTIFIED_HINT) from error
    except ProviderError as error:
        raise ProviderUnavailableError(str(error)) from error

    return WasherIdentifyResponse(
        result=result,
        diagnostics=ScanDiagnostics(
            stages_run=[identifier.name],
            stage_answered=identifier.name,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ),
    )


@router.post(
    "/dryer",
    response_model=DryerIdentifyResponse,
    response_model_exclude_none=True,
    summary="Identify a tumble dryer's real programme line-up",
)
async def identify_dryer(
    body: MachineIdentifyRequest,
    identifier: MachineIdentifier = Depends(get_machine_identifier),
) -> DryerIdentifyResponse:
    started = time.perf_counter()
    try:
        result = await identifier.identify_dryer(body.brand, body.model)
    except NotIdentifiedError as error:
        raise MachineNotIdentifiedError(str(error), hint=_NOT_IDENTIFIED_HINT) from error
    except ProviderError as error:
        raise ProviderUnavailableError(str(error)) from error

    return DryerIdentifyResponse(
        result=result,
        diagnostics=ScanDiagnostics(
            stages_run=[identifier.name],
            stage_answered=identifier.name,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ),
    )
