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

from pydantic import BaseModel, ConfigDict, ValidationError
from pydantic.alias_generators import to_camel


def validation_problems(error: ValidationError, *, under: str = "") -> list[str]:
    """What a validation failed on, one line a problem: "known.brand: String should ...".

    Led by the key the problem is about, when there is one; a problem with the
    whole value has just the message. [under] goes in front of every key, for a
    failure found inside something larger ("results.3").

    The input that failed is left out on purpose. Pydantic's own message quotes
    it, and here it may be a page of web text or somebody's typed note, going
    into a prompt or a response. The field and the rule are what the reader of
    this needs.
    """
    problems: list[str] = []
    for found in error.errors(include_input=False, include_url=False):
        where = ".".join(part for part in (under, *(str(step) for step in found["loc"])) if part)
        problems.append(f"{where}: {found['msg']}" if where else str(found["msg"]))
    return problems


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
