"""The application.

    uv run uvicorn app.main:app --reload

Starts with an empty environment: the default provider is the deterministic
fake, so the service is runnable and its whole test suite passes without
credentials. A service that cannot start without a billing account is a service
nobody can contribute to.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI

from app.api.v1.router import api_router
from app.config import get_settings
from app.core.errors import install_error_handlers

logger = logging.getLogger(__name__)


def create_app() -> FastAPI:
    settings = get_settings()

    app = FastAPI(
        title="Washing Advice — perception layer",
        version="0.1.0",
        description=(
            "Turns photographs into confident facts about clothing. Makes no "
            "laundry decisions: every judgement about how to treat a garment "
            "lives in the wardrobe_core domain package, which the app calls "
            "with these results."
        ),
    )

    install_error_handlers(app)
    app.include_router(api_router)

    # Logs which provider is live and whether a credential is present — never
    # the credential itself. `describe()` exists precisely so nobody reaches for
    # the settings object here and logs the key by accident.
    logger.info("starting with %s", settings.describe())

    return app


app = create_app()
