# 3. A typed rule table, not a rules engine

Status: accepted

## Context

Care knowledge — "wool must not be tumble dried", "3% elastane rules out high
heat" — has to live somewhere. Scattering it through conditionals in the sorter
makes it untestable and invisible to the user. The conventional answer is a
rules engine with serialisable conditions and actions, loadable from a server.

## Decision

Rules are typed Dart data: a predicate over item facts, the constraint imposed,
a user-facing rationale, and a priority. Adding knowledge means adding a row to
a table.

Crucially, `CareConstraint.applyTo` merges restrictively, so a rule can **only
ever tighten** care, never loosen it.

`RuleSource` is an interface, so a remote JSON-backed rule set can be added
later without touching the evaluator or any caller.

## Consequences

Because constraints only tighten, the result is **independent of the order rules
are applied in**. That is a real property, asserted in the tests by reversing and
rotating the rule list, and it is what makes the table safe to extend: a new rule
can never accidentally undo an existing one. `priority` therefore affects only
the order explanations are listed in, never the outcome.

Each rule carries its own explanation, so the app can always say *why* it is
recommending something. This turned out to matter more than expected — the
rationale is a product feature, not documentation.

Rejected alternative: a generic condition/action interpreter. It buys
over-the-air updates at the cost of type safety, exhaustiveness checking, and a
validator plus test harness of its own. The `RuleSource` seam preserves the
option without paying for it now.
