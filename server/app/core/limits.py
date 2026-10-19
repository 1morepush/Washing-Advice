"""What the service will accept.

Uploads arrive from phone cameras, so the limits are set by what a real device
produces rather than by what is theoretically possible. They exist to stop one
oversized request exhausting memory, and to reject obvious mistakes early with a
message that says what to do about it.
"""

from __future__ import annotations

from app.core.errors import PayloadTooLargeError, UnsupportedMediaError

ALLOWED_MIME_TYPES: frozenset[str] = frozenset(
    {
        "image/jpeg",
        "image/jpg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif",
    }
)

MAX_LISTING_PHOTOS = 4
"""Photographs read into one listing draft.

Fewer than the scans allow, which is `Settings.max_images_per_request`. Every
photograph is sent to the model whole, so the count sets how long the upload and
the reading take on a phone's connection and how many tokens one draft costs
against a free allowance. It is a number the app can build its checklist around
rather than a memory limit.
"""

_MAGIC_PREFIXES: tuple[tuple[bytes, str], ...] = (
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
)


def check_image(
    data: bytes,
    mime_type: str | None,
    *,
    max_bytes: int,
) -> str:
    """Validates one upload and returns the MIME type to use.

    Raises `UnsupportedMedia` or `PayloadTooLarge` — both of which the error
    handler turns into a 4xx with an explanation, rather than a 500 that tells
    the user nothing.
    """
    if not data:
        raise UnsupportedMediaError("the uploaded file is empty")

    if len(data) > max_bytes:
        raise PayloadTooLargeError(
            f"image is {len(data) // 1024} KB; the limit is {max_bytes // 1024} KB. "
            "Reduce the capture resolution before uploading."
        )

    normalised = (mime_type or "").split(";")[0].strip().lower()

    # Clients routinely send application/octet-stream for a camera capture, so
    # the magic bytes are consulted before rejecting anything.
    sniffed = _sniff(data)
    if normalised not in ALLOWED_MIME_TYPES:
        if sniffed is None:
            allowed = ", ".join(sorted(ALLOWED_MIME_TYPES))
            raise UnsupportedMediaError(
                f"unsupported image type {normalised or 'unknown'!r}; expected one of: {allowed}"
            )
        return sniffed

    # A declared type that contradicts the actual bytes is a client bug worth
    # correcting silently rather than failing on — the bytes are the truth.
    return sniffed or normalised


def _sniff(data: bytes) -> str | None:
    for prefix, mime_type in _MAGIC_PREFIXES:
        if data.startswith(prefix):
            return mime_type
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    if data[4:8] == b"ftyp" and data[8:12] in (b"heic", b"heix", b"mif1"):
        return "image/heic"
    return None


def check_image_count(count: int, *, maximum: int) -> None:
    if count == 0:
        raise UnsupportedMediaError("at least one image is required")
    if count > maximum:
        raise PayloadTooLargeError(f"at most {maximum} images per request, got {count}")
