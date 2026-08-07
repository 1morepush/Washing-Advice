# 7. A cost-ordered vision pipeline, with the cache as a stage

Status: accepted

## Context

The perception layer needs to answer three kinds of scan, and the obvious
implementation is a service class with three methods that each call Gemini.

That works until any of the following is wanted, all of which are on the roadmap:

- an on-device OCR pass, so a legible care label never costs a network call;
- remembering a label already read, so a retry is free;
- swapping the model, or running a local one in development;
- combining two sources that each read part of a label.

Each of those bolted onto a three-method service becomes a conditional inside
it, and the conditionals interact.

## Decision

The layer is a **pipeline of stages ordered by cost**:

```
memory (FREE)  →  on-device (ON_DEVICE)  →  cloud model (NETWORK)
```

Each stage may answer fully, answer partially, or decline. The pipeline stops as
soon as an answer is complete and confident enough.

The knowledge cache is **itself a stage**, at `StageCost.FREE`, rather than a
cache wrapped around the orchestrator.

Providers are registered by name in a `ProviderRegistry` that holds factories,
and `ProviderStage` adapts any provider into a stage.

## Consequences

"Check memory first, call the expensive model only if needed" is not a feature
of the pipeline — it is what the ordering rule *does*. Adding the on-device OCR
stage later is a registration, not a rewrite, and no existing stage changes.

Making the cache a stage rather than a wrapper means there is exactly one place
that decides what runs, and `stagesRun` in the diagnostics tells the truth about
where an answer came from. A cache wrapped around the outside would have to
report its hits separately, and the two accounts would drift.

Two rules that turned out to matter more than expected:

**A partial answer must not short-circuit.** A partial care reading is a
contribution, not a conclusion — the entire point of gathering one is to let a
later stage fill what it could not. Only a *complete* answer above the confidence
threshold stops the pipeline. This is asserted directly, because the natural
implementation gets it wrong.

**A stage that fails must decline, not raise.** One provider being unavailable
must never take the pipeline down; the next stage should get its turn. Provider
failures are therefore caught in `ProviderStage` and converted to a declined
outcome, and `ProviderError` is reserved for a genuine failure to produce an
answer rather than for the ordinary case of having nothing to say.

Registering factories rather than instances means importing a provider module
never opens a connection or requires a credential. The Gemini provider can be
registered in every environment and fails only if it is actually selected without
a key — which is why the service starts, and the whole suite passes, with an
empty environment.

The cost is one more layer to understand than three methods would have been. It
earns that on the first stage added.
