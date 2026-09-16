"""Errors, and how they reach the client.

Every failure returns the same envelope so the app has one thing to decode, and
every message says what the user or the client can do about it. A 500 with no
detail is the worst possible outcome here: the user is standing at a washing
machine holding a garment, and "something went wrong" gives them nothing.
"""

from __future__ import annotations

import math
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


class RateLimitedError(ApiError):
    """The model behind this call is rate-limited, and said for how long.

    Its own status rather than a 503, and with a `Retry-After` header, because
    the client can do something specific with it: wait that long, then send
    the same request. A 503 reads as "the server is down", and the app's
    answer to that is a spinner and a retry straight back into the limit.
    """

    status_code = status.HTTP_429_TOO_MANY_REQUESTS
    code = "rate_limited"

    def __init__(self, detail: str, *, retry_after: float, hint: str | None = None) -> None:
        super().__init__(detail, hint=hint)
        self.retry_after = retry_after

    def to_response(self) -> JSONResponse:
        response = super().to_response()
        response.headers["Retry-After"] = str(max(1, math.ceil(self.retry_after)))
        return response


def from_provider_error(error: Exception, *, hint: str | None = None) -> ApiError:
    """The API error a failed model call maps to.

    A rate limit becomes [RateLimitedError]; anything else is the provider
    being unavailable. Duck-typed on `retry_after` rather than importing the
    provider layer here, which would put a service import under `core`.
    """
    retry_after = getattr(error, "retry_after", None)
    if isinstance(retry_after, (int, float)):
        return RateLimitedError(
            "The AI service is busy right now.",
            retry_after=float(retry_after),
            hint="Wait that long, then try the same request again.",
        )
    return ProviderUnavailableError(str(error), hint=hint)


class ScanFailedError(ApiError):
    """Every stage declined, so there is no answer to return.

    A 422 rather than a 500: the request was well-formed, but nothing could be
    made of the image. Usually that means a blurry or badly-lit photograph, and
    the hint says so.
    """

    status_code = 422  # Unprocessable Content
    code = "scan_failed"


class MachineNotIdentifiedError(ApiError):
    """The model has no reliable, specific knowledge of this exact appliance.

    A distinct code from `ScanFailedError`, not a reuse of it: this is not a
    scan and did not fail for the same reason a blurry photo does — there is
    no photo, and the request was answered honestly rather than badly. A 422
    for the same reason as a scan failure: the request was well-formed, there
    is simply nothing to return.
    """

    status_code = 422  # Unprocessable Content
    code = "machine_not_identified"


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
