"""The server still answers every app version that can be chosen.

The web app keeps its recent releases published ("Settings -> Use an earlier
version"), and a phone can be left on any of them. The server is one deployment
that every one of them talks to. So a server change that is fine for the newest
app (a renamed field, a stricter validation, a removed endpoint) can break an
older one that nobody is testing, on a phone, in a utility room.

`contracts/compat/<version>/` records what each release really sent and what it
needed back (see `contracts/compat/README.md` for how it is recorded and why it
is trustworthy). This replays every recorded version, with the fake providers,
and checks that the server still succeeds and still returns every field that
version's decoders cannot do without.

Failing here means: you changed the wire format in a way an older app notices.
Make the change additive (keep the old field, accept the old request) rather
than editing the fixtures. Edit them only when you mean to stop supporting that
version, and drop it from the offered versions at the same time. See the rule
in the repository's `CLAUDE.md`.
"""

from __future__ import annotations

import json
import os
import re
from collections.abc import Iterator
from pathlib import Path
from typing import Any

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.v1.dependencies import reset_wiring
from app.main import create_app

COMPAT = Path(__file__).resolve().parents[2] / "contracts" / "compat"
PUBSPEC = Path(__file__).resolve().parents[2] / "app" / "pubspec.yaml"


def _version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def versions() -> list[str]:
    """Every recorded version, oldest first."""
    return sorted(
        (p.name for p in COMPAT.iterdir() if p.is_dir() and re.fullmatch(r"\d+\.\d+\.\d+", p.name)),
        key=_version_key,
    )


def cases() -> list[tuple[str, str]]:
    return [
        (version, path.stem)
        for version in versions()
        for path in sorted((COMPAT / version / "requests").glob("*.json"))
    ]


def _read(path: Path) -> Any:
    return json.loads(path.read_text())


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    # The fake providers are the default; spelled out so a developer's
    # environment (a real key in `.env`) cannot make the suite call a model.
    monkeypatch.setenv("VISION_PROVIDER", "fake")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    # The cutout endpoint's learned model is covered by its own tests; this
    # suite is about the wire format and should be fast and deterministic.
    monkeypatch.setenv("CUTOUT_REMOVER", "classical")
    reset_wiring()
    with TestClient(create_app()) as test_client:
        yield test_client
    reset_wiring()


def replay(client: TestClient, record: dict[str, Any]) -> httpx.Response:
    """Sends a recorded request exactly as the app did."""
    kwargs: dict[str, Any] = {}
    if record.get("contentType") == "application/json":
        kwargs["json"] = record["json"]
    elif record.get("contentType") == "multipart/form-data":
        files = [
            (
                f["field"],
                (
                    f["filename"],
                    (COMPAT / "assets" / f["asset"]).read_bytes(),
                    f["contentType"],
                ),
            )
            for f in record.get("files", [])
        ]
        if files:
            kwargs["data"] = record.get("fields", {})
            kwargs["files"] = files
        else:
            # httpx sends text fields alone as a urlencoded form, which is not
            # what the app does: it sends multipart with no file part.
            kwargs["headers"] = {"Content-Type": "multipart/form-data; boundary=compat"}
            kwargs["content"] = _multipart_without_files(record.get("fields", {}))
    return client.request(record["method"], record["path"], params=record.get("query"), **kwargs)


def _multipart_without_files(fields: dict[str, str]) -> bytes:
    """A multipart body of text fields only, which is what the app sends for a
    stain question with no photograph."""
    out = b""
    for name, value in fields.items():
        out += (
            f'--compat\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'
        ).encode()
    return out + b"--compat--\r\n"


def _missing(node: Any, steps: list[str], at: str = "") -> list[str]:
    """The places `steps` (a path like `a.b[].c`) leads that lack the last key."""
    if not steps:
        return []
    step = steps[0]
    if step == "[]":
        if not isinstance(node, list):
            return [f"{at}: expected a list"]
        found: list[str] = []
        for index, element in enumerate(node):
            found += _missing(element, steps[1:], f"{at}[{index}]")
        return found
    if not isinstance(node, dict):
        return [f"{at}: expected an object"]
    if step not in node:
        return [f"{at}.{step}"]
    return _missing(node[step], steps[1:], f"{at}.{step}")


def _steps(path: str) -> list[str]:
    steps: list[str] = []
    for piece in path.split("."):
        trailing = 0
        while piece.endswith("[]"):
            trailing += 1
            piece = piece[:-2]
        if piece:
            steps.append(piece)
        steps += ["[]"] * trailing
    return steps


def test_there_are_recorded_versions_to_replay() -> None:
    # A glob that matched nothing would make everything below pass by not
    # existing.
    assert len(versions()) >= 1
    assert len(cases()) >= 15


def test_the_current_app_version_is_recorded() -> None:
    """A release that did not record what it sends is not covered.

    The check is here as well as in the app's own test so that a version bump
    with no record fails the server's build too, where the person changing the
    server will see it.
    """
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+)", PUBSPEC.read_text(), re.MULTILINE)
    assert match, "no version in app/pubspec.yaml"
    assert match.group(1) in versions(), (
        f"app {match.group(1)} has no record under contracts/compat/. "
        "Run app/tool/capture_compat.sh."
    )


def test_every_recorded_request_has_a_recorded_answer_shape() -> None:
    for version in versions():
        requests = {p.stem for p in (COMPAT / version / "requests").glob("*.json")}
        required = {p.stem for p in (COMPAT / version / "required").glob("*.json")}
        assert requests == required, f"{version}: requests and required fields disagree"


@pytest.mark.parametrize(("version", "name"), cases(), ids=[f"{v}-{n}" for v, n in cases()])
def test_the_server_answers_what_that_version_sends(
    client: TestClient, version: str, name: str
) -> None:
    record = _read(COMPAT / version / "requests" / f"{name}.json")
    required = _read(COMPAT / version / "required" / f"{name}.json")

    response = replay(client, record)

    assert response.status_code == required["status"], (
        f"{version} {name}: {record['method']} {record['path']} -> "
        f"{response.status_code} {response.text[:300]}"
    )

    kind = required["kind"]
    if kind == "json":
        body = response.json()
        gone = [
            place
            for path in required["paths"]
            for place in _missing(body, _steps(path))
        ]
        assert not gone, (
            f"{version} {name}: the response no longer has what that version's "
            f"app needs: {gone[:5]}"
        )
    elif kind == "sse":
        assert response.headers["content-type"].startswith("text/event-stream")
        assert any(line.startswith("data:") for line in response.text.splitlines())
    elif kind == "image":
        assert response.headers["content-type"] == "image/png"
        assert response.content.startswith(b"\x89PNG\r\n\x1a\n")
    else:  # pragma: no cover
        pytest.fail(f"unknown kind {kind}")


@pytest.mark.skipif(
    not os.environ.get("COMPAT_WRITE_SAMPLES"),
    reason="only when recording a release: see contracts/compat/README.md",
)
def test_write_samples(client: TestClient) -> None:
    """Records what the server answers the newest recorded requests with.

    The app's decoders are then run against these (`compat_capture_test.dart`)
    to find which fields each version cannot do without. Not a check, so it is
    skipped unless asked for.
    """
    newest = versions()[-1]
    out = COMPAT / "samples"
    out.mkdir(exist_ok=True)
    for path in sorted((COMPAT / newest / "requests").glob("*.json")):
        record = _read(path)
        response = replay(client, record)
        assert response.status_code == 200, f"{path.stem}: {response.status_code}"
        kind = _kind_of(path.stem)
        if kind == "json":
            (out / f"{path.stem}.json").write_text(
                json.dumps(response.json(), indent=2, sort_keys=True) + "\n"
            )
        elif kind == "sse":
            (out / f"{path.stem}.sse").write_text(response.text)
        else:
            (out / f"{path.stem}.png").write_bytes(response.content)


def _kind_of(name: str) -> str:
    return {"care_stain_stream": "sse", "image_cutout": "image"}.get(name, "json")
