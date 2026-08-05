"""Errors, and how they reach the client.

Every failure returns the same envelope so the app has one thing to decode, and
every message says what the user or the client can do about it. A 500 with no
detail is the worst possible outcome here: the user is standing at a washing
machine holding a garment, and "something went wrong" gives them nothing.
"""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.responses import JSONResponse

from app.schemas.base import WireModel


class ErrorResponse(WireModel):
    """The single error shape every failure returns."""

    error: str
    """A stable machine-readable code, e.g. `unsupported_media`."""

    detail: str
    """A human-readable explanation, safe to show to a user."""

    hint: str | None = None
    """What to try instead, when there is something actionable to suggest."""


class ApiError(Exception):
    """Base for errors that map to a specific status code."""

    status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR
    code: str = "internal_error"

    def __init__(self, detail: str, *, hint: str | None = None) -> None:
        super().__init__(detail)
        self.detail = detail
        self.hint = hint

    def to_response(self) -> JSONResponse:
        body = ErrorResponse(error=self.code, detail=self.detail, hint=self.hint)
        return JSONResponse(status_code=self.status_code, content=body.to_wire())


class UnsupportedMediaError(ApiError):
    status_code = status.HTTP_415_UNSUPPORTED_MEDIA_TYPE
    code = "unsupported_media"


class PayloadTooLargeError(ApiError):
    status_code = 413  # Content Too Large
    code = "payload_too_large"


class ProviderUnavailableError(ApiError):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    code = "provider_unavailable"


class ScanFailedError(ApiError):
    """Every stage declined, so there is no answer to return.

    A 422 rather than a 500: the request was well-formed, but nothing could be
    made of the image. Usually that means a blurry or badly-lit photograph, and
    the hint says so.
    """

    status_code = 422  # Unprocessable Content
    code = "scan_failed"


def install_error_handlers(app: FastAPI) -> None:
    """Registers the handlers that turn exceptions into the error envelope."""

    @app.exception_handler(ApiError)
    async def _handle_api_error(_: Request, error: ApiError) -> JSONResponse:
        return error.to_response()

    @app.exception_handler(ValueError)
    async def _handle_value_error(_: Request, error: ValueError) -> JSONResponse:
        # Domain validation failures — an out-of-range confidence, a malformed
        # hex colour — are the client's or the model's fault, not the server's.
        body: dict[str, Any] = ErrorResponse(
            error="invalid_request",
            detail=str(error),
        ).to_wire()
        return JSONResponse(status_code=status.HTTP_400_BAD_REQUEST, content=body)
