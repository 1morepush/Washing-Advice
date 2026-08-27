"""Answering a question about the wardrobe the caller sends.

Stateless like every other endpoint here: the conversation so far arrives with
each request rather than being held. That is not only consistency — a server
holding conversations would be a server holding a record of what somebody asked
about their clothes, and this service deliberately keeps nothing.

Nothing that comes back is checked, because there is nothing checkable in it.
Elsewhere the model names ids and the core vets them against the wardrobe it
holds; here the product is a sentence, and vetting a sentence means writing a
second model to grade the first. The guardrails are in the prompt instead, and
the honest place to say so is here: this endpoint returns text the user reads,
not instructions the app acts on. Nothing downstream changes a garment because
of it.
"""

from __future__ import annotations

import time

from fastapi import APIRouter, Depends

from app.api.v1.dependencies import get_chat_adviser
from app.core.errors import ProviderUnavailableError
from app.schemas.chat import ChatRequest, ChatResponse
from app.schemas.scan import ScanDiagnostics
from app.services.ai.base import ProviderError
from app.services.chat.base import ChatAdviser

router = APIRouter(prefix="/chat", tags=["chat"])


@router.post(
    "/ask",
    response_model=ChatResponse,
    response_model_exclude_none=True,
    summary="Answer a question about laundry and the wardrobe",
)
async def ask(
    request: ChatRequest,
    adviser: ChatAdviser = Depends(get_chat_adviser),
) -> ChatResponse:
    started = time.perf_counter()

    try:
        answer = await adviser.answer(request)
    except ProviderError as error:
        raise ProviderUnavailableError(str(error)) from error

    return ChatResponse(
        reply=answer.reply,
        diagnostics=ScanDiagnostics(
            stages_run=[adviser.name],
            stage_answered=adviser.name,
            elapsed_ms=int((time.perf_counter() - started) * 1000),
        ),
    )
