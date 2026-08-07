# 8. App layering, and putting the camera behind a seam

Status: accepted

## Context

The Flutter app has to talk to three things that do not exist in a test: a
camera, a SQLite file on a phone, and an HTTP backend. The default way to build
it — widgets calling `ImagePicker`, a Drift database and an HTTP client directly
— makes the entire app unverifiable except by hand on a device. That is
tolerable for a weekend project and not for one where the whole point is that
bad advice damages clothing.

There is also a standing risk of the domain leaking upward. Once a widget can
compute "this is wool, so no tumble dryer", laundry knowledge exists in two
places and they diverge.

## Decision

**The app holds no laundry logic.** It renders what `wardrobe_core` decides and
posts images to the server. The formatter functions on the detail screen turn a
`WashCare` into a sentence; they never choose a temperature.

**Every boundary is an interface the core already owns, or a small one the app
adds:**

| Boundary | Interface | Real | Substituted with |
|---|---|---|---|
| Storage | `WardrobeRepository` (core) | `DriftWardrobeRepository` | `InMemoryWardrobeRepository` |
| History | `EventLog` (core) | `DriftEventLog` | `InMemoryEventLog` |
| Perception | `VisionPort` (core) | `AiGateway` | a fake gateway |
| Camera | `ImageCaptureSource` (app) | `ImagePickerCaptureSource` | `FixedImageCaptureSource` |
| Ids | `IdGenerator` (core) | `RandomIdGenerator` | `SequentialIdGenerator` |

Riverpod holds the graph, so substituting any of them is one override.

**The camera is the only genuinely unverifiable part, so it is the smallest
interface that will do** — two methods. Everything downstream of it works on
ordinary bytes and is therefore exercisable in CI. `image_picker` opens the
camera on a phone and a file dialog on the web, which is the same class either
way.

**The scan flow's state is a sealed union**, not nullable fields plus an
`isLoading` flag. "Loading, and also holding an error, and also showing a
result" cannot be constructed, and adding a step is a compile error at every
place that must handle it.

**Storage takes its executor rather than opening one.** `database.dart` has no
Flutter import; opening a platform database lives in `connection.dart`. This is
what lets the schema and every query run under plain `dart test` against real
sqlite3, and it is what lets the Drift repository be held to
`runRepositoryContractTests` — the same suite that defines what the in-memory
implementation means.

## Consequences

Good:

- `lib/main_demo.dart` is the shipping app with every boundary substituted. The
  screenshots in the README are of the real widgets, not mock-ups, and the
  scan flow can be driven end to end in a browser with no camera and no server.
- A wrong `WHERE` clause fails a test instead of surfacing as a wrong wardrobe
  screen.
- Replacing the backend with an on-device pipeline later is a change to one
  provider binding.

Bad:

- More indirection than a small app needs. A reader looking for "where does the
  database get opened" has two files to visit rather than one.
- `AiGateway` is exposed as a concrete type rather than as `VisionPort`, purely
  so the scan screen can read `lastDiagnostics`. That is a genuine leak, kept
  because showing "answered from memory · 4 ms" in the UI is worth more than the
  purity, and confined to one provider.

## What this actually caught

The argument for this layering is not theoretical. Running the app for the first
time found three defects that every unit test had passed over: a stream that
never emitted its first value (a wardrobe list that loaded forever), a gradient
that asserts on single-colour garments, and an empty wardrobe reporting that
filters were hiding things. All three are now covered by widget tests that run
in CI — which was only possible because the screens can be built without a
device.
