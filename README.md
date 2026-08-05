# Washing Advice

An AI wardrobe and laundry assistant. Photograph your clothes to build a digital
wardrobe, scan care labels, then point the camera at a pile of laundry and get
told exactly which loads to run — and which cycle to select on *your* machine.

> Instead of "wash cold", it says: **Delicates, 30°C, 800 rpm, extra rinse on**
> — and tells you it chose 30°C because your new red tee bleeds.

## Status

Milestone 1 is complete: the domain core that makes every laundry decision.
The backend and the Flutter app are next. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design and
[`docs/adr/`](docs/adr) for the decisions behind it.

| # | Scope | Status |
|---|---|---|
| 1 | Domain core: care model, sorting engine, machine translation, matching, events | **Done** — 247 tests |
| 2 | FastAPI backend, AI orchestrator, Gemini provider, knowledge cache | **Done** — 103 tests |
| 3 | Flutter app shell: navigation, Drift/SQLite, theming, camera | Next |
| 4 | Wardrobe browse, item detail, care-tag scanning UI | |
| 5 | Pile scanning and batch processing | |
| 6 | Outfits, packing, analytics | |
| 7 | Offline sync, Supabase, store preparation | |

## Layout

```
packages/wardrobe_core/   Pure Dart domain core — zero dependencies
server/                   FastAPI perception layer — pixels to confident facts
contracts/                The wire format, pinned by fixtures both sides parse
docs/ARCHITECTURE.md      Design, and the reasoning behind it
docs/adr/                 Architecture decision records
.claude/hooks/            Restores the Dart SDK in a fresh web session
```

## Running it

The core is pure Dart, so it needs only the Dart SDK — no Flutter, no Android
SDK, no emulator.

```sh
cd packages/wardrobe_core
dart pub get
dart analyze
dart test
```

And the server needs only Python and `uv` — no credentials:

```sh
cd server
uv sync --group dev
uv run pytest
uv run uvicorn app.main:app --reload   # http://localhost:8000/docs
```

The default vision provider is a deterministic fake, so everything runs with an
empty environment. Set `GEMINI_API_KEY` and `VISION_PROVIDER=gemini` for the
real model.

To see the sorting engine work on a realistic pile:

```sh
dart run example/sort_demo.dart
```

which prints loads, settings and the reasoning behind each:

```
  LOAD 4: Darks (delicates) — cold, hand wash
    • Wool sweater                 70% Wool, 30% Acrylic

    WASH
      Programme:   Hand Wash/Wool
      Temperature: 30°C
      Spin:        600 rpm
      Extra rinse  ON
      i Fill the drum to no more than 40% on this programme —
        gentle cycles cannot move a full drum.
    DRY
      Do not tumble dry
      ⚠ Do not tumble dry this load. Dry flat to keep its shape.
    WHY
      · Running at 30°C because Wool sweater must not be washed hotter.
      · Using a delicate cycle because Wool sweater needs gentle handling.
      · Spin capped at 600 rpm to protect delicate fabrics.
      · Air dry this load: Wool sweater must not be tumble dried.
```

## Design in one paragraph

Ruining a wool sweater is unrecoverable, so no laundry decision is ever made by
a language model. All of it lives in `packages/wardrobe_core` — deterministic,
offline, explainable and exhaustively tested. The AI layer is reduced to
*perception* (turning pixels into confident facts) and the UI to *presentation*.
Care data is normalised to ISO 3758 rather than stored as text, because you
cannot sort laundry by comparing the strings `"Cold"` and `"cold wash"`, but you
can compare `maxTempC: 30` against `maxTempC: 40`.

## What it does not do yet

Stated plainly because the code says so too:

- **Machine profiles are brand archetypes, not model-exact.** Every seeded
  profile is flagged `isVerifiedModel: false` and is meant to be corrected by the
  user.
- **Item matching cannot tell apart visually identical garments.** Three
  identical black t-shirts will all match each other, which is why the matcher
  returns ranked candidates and the app asks rather than guessing.
- **Condition detection, embeddings and the offline vision pipeline are modelled
  but not implemented.** The types and seams exist; the detection does not.
- **The Gemini provider has never run against the live API.** It is written to
  the documented interface and tested with a stubbed transport, but no real
  request has been made. It stays behind the provider registry until it has been
  smoke-tested with a key.
- **The knowledge cache recognises an identical image, not the same label
  re-photographed.** Matching a label shot from a different angle needs
  embeddings.
