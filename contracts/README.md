# Contracts

The wire format between the Python perception layer and the Dart domain core.

Two languages have to agree on these shapes exactly. The server encodes them and
the Flutter app decodes them, so a field renamed on one side and not the other
is not a compile error — it is a runtime failure on a user's phone, on the one
screen that renamed field happens to feed.

So the agreement is pinned rather than assumed:

- **`*.schema.json`** — JSON Schema, the normative definition.
- **`examples/*.json`** — golden fixtures, parsed by tests **on both sides**.
  Python validates them against the schemas; Dart decodes them into its domain
  models. Drift in either direction fails a test.

## The one semantic that matters most

In `care_constraint.schema.json`, **every property is optional**, and an absent
property means *the label did not state this*. That is categorically different
from the label permitting it.

A creased care label whose drying symbol is illegible must come back with
`tumbleDryAllowed` **omitted**, not `true`. The domain core's rule table then
fills the gap from fibre content. Sending `true` would read as permission the
manufacturer never gave, and is how a wool blend ends up in a tumble dryer.

See [`docs/adr/0004-label-overrides-rules.md`](../docs/adr/0004-label-overrides-rules.md).

## A related trap

A wash tub with **no bars** beneath it means `agitation: "normal"` under ISO
3758. That is a stated fact, not silence, and a scan must report it. Omitting it
makes every ordinary garment inherit the core's conservative default and get
recommended a gentle cycle it does not need — which under-cleans and quietly
erodes trust in every other recommendation the app makes.
