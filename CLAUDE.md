# Working in this repository

## Before finishing any change that a user could notice

Decide which digit of the version moves, and say so. This is a required step,
not a formality — it is easy to ship a feature and leave the version where it
was, and the version is how somebody holding a phone knows what they have.

The rules are written in full at the top of
`app/lib/features/settings/patch_notes.dart`, and that docstring is the
authority. Restating them here in detail would create a second copy to drift,
which is the mistake this codebase avoids everywhere else. In short:

| What changed for the user | Digit | Example |
|---|---|---|
| The app can do something it could not do at all before | **Minor** | `0.15.0` → `0.16.0` |
| The app finally does what it already claimed to | **Patch** | `0.12.0` → `0.12.1` |
| Nothing a user could notice — refactor, test, identical answers | **No entry, no bump** | — |

Decided by what the *user* gets, not by how much code changed. A one-line fix
and a rewritten subsystem are the same size to somebody holding a phone.

Two cases that come up often:

* A fix that travels **with** a feature rides along in that feature's minor
  release. Only a repair shipping **on its own** becomes a patch. If the
  release has not reached `main` yet, a fix to it is not a patch — it is part
  of what that release always was.
* A patch never rewrites the release it repairs. The notes are a record of
  what reached `main`, not a tidy summary of it.

When the digit moves, both of these change together:

1. `app/pubspec.yaml` — the `version:` line.
2. `app/lib/features/settings/patch_notes.dart` — a new `Release` at the top
   of the list, newest first, with a name that is a laundry joke.

A test enforces that the newest note matches the version the app declares, so
bumping one without the other fails the build rather than shipping crooked.

## Verifying before you push

Run all three suites and both formatters; CI runs the same four jobs.

```
cd packages/wardrobe_core && dart analyze && dart format . && dart test
cd app                    && flutter analyze && dart format . && flutter test
cd server && uv run ruff format app tests && uv run ruff check app tests \
          && uv run mypy app && uv run pytest
```

Dart and Flutter are at `/opt/dart-sdk/bin` and `/opt/flutter/bin`, which are
not always on `PATH`.

Note `dart format .` is the action; `dart format --set-exit-if-changed .` only
checks. The check prints `Changed …` for files it would rewrite without
rewriting them, which reads as success and is not.

## A note on this container

The working copy has silently rolled back to an older commit mid-session more
than once. If local `git log` disagrees with GitHub, trust GitHub: re-fetch and
reset to the pushed branch rather than committing what the working tree shows.
Stray modified files that predate merged work are the symptom — check whether
the change is already in `origin/main` before committing it, or you will revert
shipped work.
