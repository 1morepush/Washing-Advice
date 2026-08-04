# 4. A scanned label overrides a generic fibre rule

Status: accepted

## Context

Three sources have opinions about how to wash a garment: the care label, the
fibre rule table, and a vision model's guess. They disagree routinely.

The naive resolution — always take the safest value — has a specific and
infuriating failure. Our wool rule says "never tumble dry". A superwash wool
jumper's label says "machine wash 40, tumble low". Always-safest would override
the manufacturer and tell the user to hand wash a garment designed for the
machine.

## Decision

Resolution order:

1. Conservative defaults.
2. The rule table, which can only tighten.
3. **The scanned label overrides the fields it states.**
4. A model's guess tightens only fields nobody else covered.
5. A user correction overrides everything.

Care-tag scans therefore produce a **partial** `CareConstraint`, not a complete
`CareInstructions`. A null field means "the label did not state this", which is
genuinely different from "the label permits this".

## Consequences

Superwash wool works. So does a creased label whose drying symbol is illegible:
that field stays null and the wool rule fills it, rather than the label's silence
being read as permission.

The resolver reports which fields the label overrode, so the app can surface the
interesting case — "the label says this wool jumper is machine washable, which is
unusual".

Risk: a mis-read label can now override a safety rule. Confidence is recorded on
the resulting profile, and low-confidence readings prompt a re-scan. Per-field
provenance would be stronger and is the natural next step if this proves thin in
practice.

A note for the scanner: under ISO 3758 a wash tub with **no bars** means normal
agitation. That is a stated fact, not silence, and the scan must report it as
`Agitation.normal` rather than leaving it null — otherwise every ordinary garment
inherits the conservative default and gets recommended a gentle cycle it does not
need.
