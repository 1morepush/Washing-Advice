# 5. An event log as the source of truth, with cached projections

Status: accepted

## Context

The product needs `timesWorn`, `lastWashedAt`, cost per wear, laundry frequency,
and analyses nobody has thought of yet — "did this shrink because it was washed
too hot?". The simple implementation increments counters on the item row.

Counters are lossy. Once `timesWorn` is 12, the history that produced it is gone,
an off-by-one is unrepairable, and any new question needs a schema change and a
year of data collection before it can be answered.

## Decision

An append-only `WardrobeEvent` log is the source of truth. Counters on
`WardrobeItem` are a **cached projection** of it. Projections are pure functions
from events to values, and a test asserts that replaying an item's events
reproduces its stored `UsageStats` exactly.

Events are sealed, so adding a kind forces every projection to handle it.

## Consequences

This is deliberately not full event sourcing. Wardrobe items remain ordinary
mutable-looking records that a grid can render without replaying thousands of
events per row. The log buys integrity and answerability; the cache buys reads.

The append-only rule is real: a mistaken wear is corrected with a compensating
event, not by deleting the original. Rewriting history destroys the audit trail
that makes the log worth keeping.

Events are folded by `occurredAt`, not insertion order, because people log
yesterday's wash this morning.

`LaundryRecord` records the settings actually used, not merely that a wash
happened. Without that, "times washed" is a number with no explanatory power.
