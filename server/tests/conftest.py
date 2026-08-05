"""Shared fixtures."""

from __future__ import annotations

import struct
import zlib
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient

from app.api.v1.dependencies import reset_wiring
from app.main import create_app
from app.services.ai.base import ScanImage


def png_bytes(seed: int = 0) -> bytes:
    """A genuinely valid 1x1 PNG, varying with `seed`.

    Real bytes rather than `b"fake"` so the magic-byte sniffing in
    `app.core.limits` is actually exercised, and so the fake provider — which
    hashes the image — produces different answers for different seeds.
    """

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)
    raw = bytes([0, seed % 256, (seed >> 8) % 256, (seed >> 16) % 256])
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def scan_image(seed: int = 0) -> ScanImage:
    return ScanImage(data=png_bytes(seed), mime_type="image/png")


@pytest.fixture(autouse=True)
def _fresh_wiring() -> Iterator[None]:
    """Rebuilds the cached pipeline and cache around every test.

    Without this the knowledge cache leaks between tests, and a test that
    happens to run after a caching test sees a hit it never set up.
    """
    reset_wiring()
    yield
    reset_wiring()


@pytest.fixture
def client() -> Iterator[TestClient]:
    with TestClient(create_app()) as test_client:
        yield test_client
