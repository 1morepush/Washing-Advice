"""The base for every model that goes on the wire.

Python is snake_case and the contract is camelCase, and writing `alias="..."` on
each of forty fields is both noise and a standing invitation to typos — a
mistyped alias is not a compile error, it is a field the app silently never
receives.

So the mapping is generated once here. Models are constructed with Python names
and serialised with camelCase ones.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict
from pydantic.alias_generators import to_camel


class WireModel(BaseModel):
    """Immutable, camelCase on the wire, snake_case in Python."""

    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        frozen=True,
    )

    def to_wire(self) -> dict[str, Any]:
        """Serialises to the exact shape `contracts/` describes.

        `by_alias` for camelCase, and `exclude_none` because an absent field is
        the contract's way of saying "not stated" — emitting explicit nulls
        would blur that into "stated as nothing".
        """
        return self.model_dump(mode="json", by_alias=True, exclude_none=True)
