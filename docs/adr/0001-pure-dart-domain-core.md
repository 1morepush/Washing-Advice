# 1. A pure-Dart domain core with no dependencies

Status: accepted

## Context

The product must decide how to wash clothes. Getting that wrong destroys a
user's property, so the decision has to be deterministic, offline, explainable
and exhaustively tested. It also has to be reachable from a Flutter app today
and potentially from a server or CLI later.

## Decision

All domain logic lives in `packages/wardrobe_core`: a Dart package with no
Flutter dependency and no runtime dependencies at all. The Flutter app is a thin
presentation layer over it; the backend is a perception layer beside it.

No code generation either. Dart 3 `sealed` classes give exhaustive pattern
matching natively, so `freezed` and `json_serializable` earn nothing here.
Serialisation is hand-written, which keeps the package dependency-free and makes
its alignment with the cross-language contracts explicit and testable.

## Consequences

Good: the core runs anywhere a Dart VM runs, so it is fully testable in CI
without an emulator, a device or a Flutter toolchain — which matters because the
development environment for this project has none of those. The boundary is
enforced by the compiler rather than by discipline.

Bad: hand-written `toJson`/`fromJson` for around twenty types is tedious and can
drift. Mitigated by round-trip tests that encode, decode and re-encode, which
catch fields written but never read back.

Code generation is still fine in the app layer, where Drift and Riverpod pay for
themselves.
