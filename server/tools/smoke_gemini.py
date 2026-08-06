"""Prove the Gemini provider works against the live API.

The provider is written to the documented interface and tested with a stubbed
transport, which verifies that the code does what it was written to do and says
nothing at all about whether the API agrees. Only a real request settles that,
and a real request needs a key and a billing account — so it cannot live in the
test suite without making the suite unrunnable for anyone without one.

This is that request, as one command:

    GEMINI_API_KEY=... uv run python -m tools.smoke_gemini

It sends generated images rather than photographs, because a build container
has no garments in it. That is enough to answer the questions that matter here
— does the endpoint accept our request shape, does the response schema hold,
does the parser produce a valid result — and not enough to say anything about
recognition quality. Point it at a real photograph with `--image` to judge that.

Nothing here prints the key, and the error paths deliberately do not echo
response bodies, which can contain the image that was sent.
"""

from __future__ import annotations

import argparse
import asyncio
import io
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw

from app.services.ai.base import ProviderError, ScanImage
from app.services.ai.providers.gemini import GeminiVisionProvider


@dataclass(frozen=True)
class Check:
    name: str
    ok: bool
    detail: str
    seconds: float


def _generated_garment() -> bytes:
    """A drawn navy t-shirt on a light background.

    Crude on purpose: the point is to exercise the request and response path,
    not to test recognition. A model that says "blue t-shirt" here has proved
    the wire works.
    """
    image = Image.new("RGB", (768, 768), (244, 244, 242))
    draw = ImageDraw.Draw(image)
    navy = (31, 42, 68)
    draw.polygon(
        [
            (240, 200),
            (330, 150),
            (440, 150),
            (530, 200),
            (500, 280),
            (450, 250),
            (450, 600),
            (320, 600),
            (320, 250),
            (270, 280),
        ],
        fill=navy,
    )
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


def _generated_label() -> bytes:
    """A care label with legible text, since OCR is the point of that stage."""
    image = Image.new("RGB", (768, 512), (250, 250, 248))
    draw = ImageDraw.Draw(image)
    draw.rectangle([(60, 60), (708, 452)], outline=(120, 120, 120), width=3)
    for offset, line in enumerate(
        ["100% COTTON", "MACHINE WASH 30", "DO NOT BLEACH", "TUMBLE DRY LOW", "IRON MEDIUM"]
    ):
        draw.text((110, 120 + offset * 60), line, fill=(30, 30, 30))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=95)
    return buffer.getvalue()


async def _run(provider: GeminiVisionProvider, image_bytes: bytes | None) -> list[Check]:
    checks: list[Check] = []
    garment = ScanImage(data=image_bytes or _generated_garment(), mime_type="image/jpeg")
    label = ScanImage(data=image_bytes or _generated_label(), mime_type="image/jpeg")

    async def attempt(name: str, call) -> None:  # type: ignore[no-untyped-def]
        started = time.monotonic()
        try:
            result = await call()
        except ProviderError as error:
            # The provider's own message, which is written not to include the
            # response body. Anything else risks printing the image back.
            checks.append(Check(name, False, str(error), time.monotonic() - started))
        except Exception as error:  # A smoke test reports; it does not raise.
            checks.append(
                Check(name, False, f"{type(error).__name__}: {error}", time.monotonic() - started)
            )
        else:
            checks.append(Check(name, True, _describe(result), time.monotonic() - started))

    await attempt("scan_garment", lambda: provider.scan_garment([garment]))
    await attempt("scan_care_tag", lambda: provider.scan_care_tag(label))
    await attempt("scan_pile", lambda: provider.scan_pile(garment))
    return checks


def _describe(result: object) -> str:
    """A one-line summary, without dumping a whole result object."""
    for attribute in ("item_type", "garments", "instructions"):
        value = getattr(result, attribute, None)
        if value is not None:
            return f"{attribute}={value!r}"[:120]
    return type(result).__name__


async def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--image",
        type=Path,
        help="A real photograph to send instead of the generated ones.",
    )
    parser.add_argument("--model", default=None, help="Override the configured model.")
    args = parser.parse_args()

    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        print(
            "GEMINI_API_KEY is not set.\n\n"
            "  GEMINI_API_KEY=... uv run python -m tools.smoke_gemini\n\n"
            "The key is read from the environment and never printed. Nothing "
            "else in this project needs one: the default provider is a "
            "deterministic fake and the whole test suite passes without "
            "credentials.",
            file=sys.stderr,
        )
        return 2

    image_bytes = args.image.read_bytes() if args.image else None
    if args.image:
        print(f"Using {args.image} for every stage.")
    else:
        print("Using generated images. Pass --image to judge recognition quality.")

    provider = GeminiVisionProvider(
        api_key=key,
        **({"model": args.model} if args.model else {}),
    )

    try:
        checks = await _run(provider, image_bytes)
    finally:
        await provider.aclose()

    print()
    for check in checks:
        mark = "PASS" if check.ok else "FAIL"
        print(f"  [{mark}] {check.name}  ({check.seconds:.1f}s)")
        print(f"         {check.detail}")

    failed = [check for check in checks if not check.ok]
    print()
    if failed:
        print(f"{len(failed)} of {len(checks)} stages failed against the live API.")
        return 1

    print(
        f"All {len(checks)} stages answered and parsed. The provider works "
        "against the real API.\n"
        "Set VISION_PROVIDER=gemini to use it."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
