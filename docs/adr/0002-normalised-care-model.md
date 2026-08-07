# 2. Normalise care instructions to ISO 3758

Status: accepted

## Context

Care labels are a closed, standardised vocabulary: a wash tub, a triangle, a
square, an iron, a circle. The obvious implementation is to store what the label
says as text — `"Machine wash cold"` — and show it back to the user.

## Decision

Care is stored as structured values mapping to ISO 3758 symbols:
`{method: machine, maxTempC: 30, agitation: veryMild}`, `bleach: none`,
`{tumbleDryAllowed: false, naturalDry: flatDry}`.

Every care type implements a **restrictive merge**: combining two requirements
yields the safer of the two.

## Consequences

This is what makes the rest of the product possible. You cannot sort a pile of
laundry by comparing the strings `"Cold"` and `"cold wash"`, but you can compare
`maxTempC: 30` against `maxTempC: 40`. Load building is then just a fold of
restrictive merges across the load's members, and the result is provably safe for
the most delicate item in it.

Free text does not disappear — it reappears at the edges, in `CareLanguage`,
which renders the structure back into sentences. That is the right place for it:
one direction, at the boundary, testable.

The cost is that the care-tag scanner must map symbols onto this vocabulary
rather than returning prose, which makes the vision prompt more demanding.
