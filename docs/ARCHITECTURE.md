# Architecture

## What this product is

An AI wardrobe and laundry assistant. Photograph clothes to build a digital
wardrobe, scan care labels, point the camera at a pile of laundry and be told
exactly which loads to run and which cycle to select **on your own machine**.

## The organising constraint

Ruining a wool sweater is unrecoverable. That single fact drives the whole
design:

- The logic that decides "these items can share a load at 30°C on Delicates"
  must be **deterministic**, so the same pile always produces the same plan.
- It must be **explainable**, so a user can disagree with it intelligently
  rather than ignoring it.
- It must work **offline**, because laundry rooms have poor signal and a wrong
  answer is worse than no answer.
- It must be **exhaustively tested**, because the failure mode is destroyed
  clothing rather than a stack trace.

None of that is achievable if the decision lives inside a language model or
inside a widget. So it lives in a standalone domain package, and everything else
sits on top of it.

## Layers

```
┌──────────────────────────────────────────────┐
│  app/          Flutter — presentation only   │   (Milestone 3)
├──────────────────────────────────────────────┤
│  server/       FastAPI — perception only     │   (Milestone 2, done)
│                cost-ordered vision pipeline  │
├──────────────────────────────────────────────┤
│  packages/wardrobe_core   ← all the decisions│   (Milestone 1, done)
│  pure Dart, zero dependencies                │
└──────────────────────────────────────────────┘

The two halves agree on one wire format, defined in `contracts/` and pinned by
golden fixtures that tests in **both** languages parse.
```

The AI layer is reduced to **perception**: turning pixels into confident facts.
It never decides how to wash anything. The UI is reduced to **presentation**. If
a feature involves a judgement about clothing, it belongs in the core.

## `wardrobe_core` bounded contexts

| Context | Responsibility |
|---|---|
| `shared` | `Confident<T>` with provenance, typed ids, injectable clock, feature flags |
| `wardrobe` | Items, fibre composition, CIELAB colour, photos, condition, lifecycle, relationships |
| `care` | ISO 3758 model, the care rule table, resolution between disagreeing sources, plain-English rendering |
| `laundry` | Separation rules and the sorting engine |
| `machines` | Washer and dryer profiles, and translation of abstract requirements into real settings |
| `matching` | Recognising an item already in the wardrobe |
| `vision` | The contract the AI layer must satisfy — interfaces only, no implementation |
| `events` | The append-only history and the projections derived from it |

Dependencies run one way: `laundry` → `machines` → `care` → `wardrobe` →
`shared`. There is no cycle, and nothing depends on `vision`.

## The five decisions worth understanding

### 1. Care is normalised, never free text

`"Cold"` cannot be sorted, compared or merged. `{method: machine, maxTempC: 30,
agitation: gentle}` can. Every care value maps to an ISO 3758 symbol, which is
what makes the sorting engine possible at all.

Every care type supports a **restrictive merge**: combining two requirements
yields the safer of the two. That one operation drives both care resolution and
load building, and it is why a load is always safe for its most delicate member.

### 2. Care rules are a typed table, not an interpreter

A generic condition/action rules engine would be configurable at the cost of
type safety and compile-time exhaustiveness — an untyped mini-language that is
harder to test than the conditionals it replaced.

Instead each rule is typed data: a predicate, the constraint it imposes, a
user-facing rationale, and a priority. Adding knowledge is adding a row.

Because every constraint can **only tighten**, the outcome is independent of the
order rules are applied in. That property is asserted directly in the tests, and
it is what makes the table safe to extend — a new rule can never accidentally
loosen an existing one.

`RuleSource` is an interface, so a remote JSON-backed rule set can be introduced
later without touching the evaluator or any caller.

### 3. A label outranks a generic rule; rules fill the gaps

Three sources have opinions and routinely disagree: the care label, the fibre
rule table, and a vision model's guess. Resolution order:

1. Start from conservative defaults.
2. Apply the rule table — it can only tighten.
3. Let a **scanned label override** the fields it states.
4. Let a model's guess tighten only what nobody else covered.
5. Let a user correction override everything.

Step 3 is the important one. A manufacturer printing "machine wash 40, tumble
low" on a superwash wool jumper knows something the generic wool rule does not.
Forcing our rule over their explicit instruction would be wrong *and*
infuriating.

Step 2 still matters because labels are partial. A creased label whose drying
symbol is illegible produces `tumbleDryAllowed: null` — genuinely "not stated",
which is different from "permitted" — and the rule table fills it.

### 4. Separation is structural; settings are negotiable

Two different kinds of constraint, handled differently:

- **Settings** (temperature, agitation, spin, dry heat) always reconcile by
  taking the most restrictive value.
- **Separations** never reconcile. No temperature makes it acceptable to wash a
  white shirt with a new red one.

Separations are therefore checked as absolute pairwise constraints before any
merging: whites vs darks, lint producers vs lint magnets, delicates vs heavy,
bleeding dye, differing wash methods, and explicit label instructions.

### 5. The event log is the truth; counters are a cache

`WardrobeItem.usage` holds `timesWorn`, `lastWashedAt` and so on, but they are a
**projection** of an append-only event log, not the source of truth. A test
asserts that replaying an item's events reproduces its stored counters exactly.

This buys the integrity of event sourcing without its read cost, and it keeps
questions nobody anticipated answerable — "how many times did I wear this before
it started fading?" is a fold over history, not a schema migration.

## Colour

Colour is held in **CIELAB** and compared with **CIEDE2000**, not RGB. RGB
distance rates dark navy and dark brown as far apart while calling two obviously
different pastels close, which would mis-sort laundry.

The implementation is verified against all 25 published Sharma, Wu and Dalal
reference vectors, including the four that sit on the hue-quadrant discontinuity
and differ only in the fourth decimal place.

## The perception layer

`server/` turns pixels into confident facts and does nothing else. It makes no
laundry decisions; every judgement about how to treat a garment lives in the
core, which the app calls with these results.

It is a **pipeline of stages ordered by cost** — memory, then on-device, then
the cloud model — that stops as soon as the answer is good enough. "Check memory
first, call the expensive model only if needed" is therefore what the ordering
rule *does*, not a special case inside it. The knowledge cache is itself a
free stage rather than a wrapper, so `stagesRun` in the response diagnostics
tells the truth about where an answer came from. See
[ADR 7](adr/0007-cost-ordered-vision-pipeline.md).

Today two stages are registered: the cache and one provider. An on-device OCR
pass is a registration away, and nothing else changes when it lands.

### The contract semantic that everything depends on

Every field of a scanned `CareConstraint` is optional, and an **absent** field
means *the label did not state this*. That is categorically different from the
label permitting it, and the difference is preserved all the way onto the wire:
responses are serialised with `exclude_none`, so an unreadable drying symbol
produces JSON with no `tumbleDryAllowed` key at all rather than one set to null.

The core reads absence as "fill this from the rule table" and a stated value as
"the manufacturer said so". A null in that position would turn a guess into a
manufacturer's instruction, which is how a wool blend ends up in a tumble dryer.
Tests on both sides assert it, from both directions.

The related trap: a wash tub with **no bars** means normal agitation under ISO
3758. That is a stated fact, not silence, and the prompt says so at length —
because a model left to itself omits it, and every ordinary garment then
inherits the conservative default and gets recommended a gentle cycle it does
not need.

### Running it

```sh
cd server
uv sync --group dev
uv run pytest
uv run uvicorn app.main:app --reload
```

No credentials required. The default provider is a deterministic fake that
derives its answers from a hash of the image bytes, so the same image always
gives the same result and cache behaviour is testable. Set `GEMINI_API_KEY` and
`VISION_PROVIDER=gemini` to use the real model.

## Honest limitations

These are stated in code and must be stated in the UI too.

- **Seeded machine profiles are brand archetypes, not model-exact.** Real
  machines vary by model, year and region. Every seeded profile has
  `isVerifiedModel: false`, and the UI is expected to act on that and invite
  correction. Presenting a guessed cycle list as fact is the fastest way to lose
  a user's trust.
- **Attribute matching cannot distinguish visually identical garments.** Three
  black t-shirts of the same brand and size will all match each other. This is
  why the matcher returns ranked candidates with confidence rather than a
  verdict, and why the app asks when the top two are close. `MatcherChain`
  exists so a visual-embedding matcher can be added without changing callers.
- **Condition detection, embeddings and the offline vision pipeline are modelled
  but not implemented.** The types and seams exist; the detection does not. They
  are gated behind `FeatureFlags` and must not be presented as working.
- **The knowledge cache keys on a hash of the image bytes.** It recognises the
  same image being scanned again — a retry, a double-tap — but *not* the same
  physical label photographed a second time at a different angle. That needs a
  perceptual hash or an embedding. The brand-and-type composition prior is the
  part that generalises today.
- **The Gemini provider has never been executed against the live API.** It is
  written against the documented interface and covered by tests using a stubbed
  transport and recorded response shapes, but no request has been made without a
  key. It stays behind the registry until it has been smoke-tested.

## Testing approach

234 tests. The ones that matter most assert *properties* rather than examples:

- Care rule application is order-independent (reversal and rotation).
- Separation conflict detection is symmetric across a sample wardrobe.
- Event replay reproduces cached counters, including from a shuffled log.
- Every seeded machine profile round-trips through JSON and offers the
  temperature and heat it claims to default to.
- No matcher ever selects a temperature, spin speed or dryer heat above what a
  load allows — checked across every seeded machine.

Run them with:

```sh
cd packages/wardrobe_core
dart analyze && dart test
dart run example/sort_demo.dart   # prints a worked plan
```

## Milestones

| # | Scope | Status |
|---|---|---|
| 1 | Domain core: care, sorting, machines, matching, events | **Done** — 247 tests |
| 2 | FastAPI backend, AI orchestrator, Gemini provider, knowledge cache | **Done** — 103 tests |
| 3 | Flutter app shell: navigation, Drift/SQLite, theming, camera | Next |
| 4 | Wardrobe browse, item detail, care-tag scanning UI | |
| 5 | Pile scanning and batch processing | |
| 6 | Outfits, packing, analytics dashboards | |
| 7 | Offline sync, Supabase, store preparation | |
