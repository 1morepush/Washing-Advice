"""The application.

    uv run uvicorn app.main:app --reload

Starts with an empty environment: the default provider is the deterministic
fake, so the service is runnable and its whole test suite passes without
credentials. A service that cannot start without a billing account is a service
nobody can contribute to.
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.v1.dependencies import close_providers
from app.api.v1.router import api_router
from app.config import get_settings
from app.core.errors import install_error_handlers

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()

    # Logs which provider is live and whether a credential is present — never
    # the credential itself. `describe()` exists precisely so nobody reaches for
    # the settings object here and logs the key by accident.
    logger.info("starting with %s", settings.describe())

    yield

    # Providers hold a connection pool for their lifetime; release it rather
    # than leaving sockets to be reaped.
    await close_providers()


def create_app() -> FastAPI:
    app = FastAPI(
        title="Washing Advice — perception layer",
        version="0.1.0",
        description=(
            "Turns photographs into confident facts about clothing. Makes no "
            "laundry decisions: every judgement about how to treat a garment "
            "lives in the wardrobe_core domain package, which the app calls "
            "with these results."
        ),
        lifespan=lifespan,
    )

    install_error_handlers(app)
    app.include_router(api_router)

    return app


app = create_app()
