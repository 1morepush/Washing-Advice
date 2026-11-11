"""Scanning a photograph of a person wearing their clothes.

The one place the two halves meet: the photograph is stood upright, the reader
is shown that upright picture, and what it found is vetted and cut from the
same pixels. Kept out of the route so the route stays as thin as the others and
so this can be tested without HTTP.
"""

from __future__ import annotations

import asyncio
import base64

from PIL import Image

from app.schemas.common import BoundingBox
from app.schemas.scan import WornDetection, WornScanResult
from app.services.ai.base import ScanImage
from app.services.worn.base import RawDetection, WornScanner
from app.services.worn.cutting import cut_garment, orient_photo, pixel_box

MAX_DETECTIONS = 12
"""The most detections one photograph returns.

A person wears about a dozen things at the outside: a layered outfit with shoes,
a hat, glasses, a necklace and a bag. More than that is a model listing
patterns, buttons and shadows, and each one costs a cutout the response carries
as base64.
"""


async def scan_worn(photo: ScanImage, scanner: WornScanner) -> WornScanResult:
    """Finds what the person in [photo] is wearing and cuts each piece out.

    Raises `PhotoError` if the photograph cannot be opened, and whatever the
    scanner raises (`ProviderError`) if it cannot answer. Pixel work runs off
    the event loop: a dozen cutouts of a phone photograph are a second or two of
    CPU, and every other request on the server would wait for them.
    """
    oriented = await asyncio.to_thread(orient_photo, photo)
    found = await scanner.read(oriented.for_model)
    return await asyncio.to_thread(cut_detections, oriented.image, found)


def cut_detections(photo: Image.Image, found: list[RawDetection]) -> WornScanResult:
    """Vets and cuts what a scanner found, against the upright [photo].

    A detection whose box is nonsense is dropped before anything is spent on
    it, then the list is held to `MAX_DETECTIONS` keeping the most certain, in
    the order the model gave them (which is usually top to bottom, and is how the
    app lists them).
    """
    plausible = [d for d in found if pixel_box(d.box, photo.size) is not None]

    if len(plausible) > MAX_DETECTIONS:
        ranked = sorted(
            range(len(plausible)),
            key=lambda i: plausible[i].detection_confidence,
            reverse=True,
        )
        keep = set(ranked[:MAX_DETECTIONS])
        plausible = [d for i, d in enumerate(plausible) if i in keep]

    detections: list[WornDetection] = []
    for detection in plausible:
        cut = cut_garment(photo, detection.box, detection.mask)
        if cut is None:
            continue
        detections.append(
            WornDetection(
                scan=detection.scan,
                bounding_box=BoundingBox(
                    # Rounded so the wire carries 0.56 and not 0.5600000000000001.
                    left=round(cut.box.left, 6),
                    top=round(cut.box.top, 6),
                    width=round(cut.box.right - cut.box.left, 6),
                    height=round(cut.box.bottom - cut.box.top, 6),
                ),
                detection_confidence=detection.detection_confidence,
                cutout=base64.b64encode(cut.png).decode("ascii"),
                cutout_kind=cut.kind,
            )
        )
    return WornScanResult(detections=detections)
