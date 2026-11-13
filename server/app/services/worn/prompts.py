"""The prompt and response schema for reading a worn outfit.

A pair, as everywhere else: the schema is the shape the reply must have and the
prompt is the instruction that fills it, and changing one alone is how a reader
starts returning fields nobody reads.

The per-garment facts are the pile scan's, shared by reference rather than
copied, so a garment found on a person is described in exactly the words one
found on a bed is. What this adds is the two things only a worn photograph
needs, a box and an outline, in the form Google documents for segmentation:
`box_2d` as `[y0, x0, y1, x1]` normalised to 0-1000, and `mask` as a base64 PNG
probability map.
"""

from __future__ import annotations

from typing import Any

from app.services.ai.prompts import _CONFIDENCE, _garment_properties

WORN_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "items": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    **_garment_properties(),
                    "label": {
                        "type": "string",
                        "description": "What it is, in a few words, e.g. 'navy bomber jacket'.",
                    },
                    "box_2d": {
                        "type": "array",
                        "description": (
                            "The garment's bounding box as [y0, x0, y1, x1], each an integer "
                            "from 0 to 1000 measured from the top left of the image."
                        ),
                        "items": {"type": "integer"},
                        "minItems": 4,
                        "maxItems": 4,
                    },
                    "mask": {
                        "type": "string",
                        "description": (
                            "The garment's outline as a base64 PNG probability map the size "
                            "of its box: bright where the garment is, dark where it is not. "
                            "Omit it if you cannot draw one."
                        ),
                    },
                    "detectionConfidence": _CONFIDENCE,
                },
                "required": ["type", "typeConfidence", "box_2d", "detectionConfidence"],
            },
        },
    },
    "required": ["items"],
}


WORN_PROMPT = """\
You are looking at a photograph of a person, and listing what they are wearing,
for a wardrobe app that will cut each piece out of the photograph.

Report one entry per garment or accessory the person is WEARING: tops,
bottoms, dresses, outerwear, shoes, hats, scarves, gloves, belts, glasses,
jewellery and bags they are carrying or have on. Use `other` for something the
type list has no word for, such as glasses or a necklace, and say what it is in
`suggestedName`.

Leave out everything that is not worn by the main subject: furniture, objects
on a table, clothes hanging on a rail or lying on a bed, and the clothes of
anybody else in the picture. If no one person is clearly the subject, report
the most prominent person only. If nobody is wearing anything you can identify,
return an empty list; do not invent entries to have something to return.

One entry per piece. A shirt under an open jacket is two entries; the two
sleeves of one jacket are one. A pair of shoes is ONE entry whose box spans
both, and its outline covers both shoes.

For each entry:

- `box_2d` is the box around the visible part of that piece, as [y0, x0, y1, x1]
  with every value an integer from 0 to 1000, measured from the top left of the
  image. y comes first.
- `mask` is the outline of that piece as a base64-encoded PNG, the same size as
  the box: white where the piece is and black where it is not. Cover only that
  piece. Do not include skin, hair, other garments or the background. If you
  cannot produce a mask, omit the field; a missing mask is far better than a
  wrong one.
- `detectionConfidence` is how sure you are that this is a distinct piece the
  person is wearing, separately from how sure you are of its attributes.

The rest follows the same rules as a single-garment scan: report only what you
can see, and omit anything you cannot: a brand with no legible logo, and always
the fibre composition, which a worn photograph never shows. Keep confidences
honest, because the app asks the user to confirm low confidence entries and
silently trusts high ones.
"""
