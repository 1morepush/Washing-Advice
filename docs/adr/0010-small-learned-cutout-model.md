# 10. A small learned model for garment cutouts, with the classical remover kept as the fallback

Status: accepted

## Context

Cutouts were made by a border-colour rule (`BorderSampledRemover`, see the
docstring in `cutout.py`): sample the frame's edge, call that the background,
keep what is far from it. ADR 0006 and the original docstring argued for it on
two grounds: the app tells people to lay clothes flat on a plain background, and
a learned model would break the property that the server starts, and passes its
whole suite, with no network.

The owner's real photographs are clothes laid flat on a white board *on carpet*.
On those the rule fails in two ways:

- **A ragged shape with a white fringe.** Shadows and creases are far from the
  board colour, so they read as garment; and the edge pixels, a blend of garment
  and board, survive as a pale halo that shows on the app's dark tile.
- **No cutout at all** when the border is part board, part carpet, or when the
  garment itself touches the frame. The "background" is then partly garment, the
  subject is subtracted from itself, and the app is left showing the whole photo.

The premise of the first decision, that the instruction to use a plain
background solves the hard part, turns out not to hold for a board on carpet.

## Decision

Add `LearnedRemover`, which runs **`u2netp`** (the small U²-Net, 4.6 MB,
Apache-2.0) through ONNX Runtime, behind the existing `BackgroundRemover` seam.
It is the default (`CUTOUT_REMOVER=learned`). `CUTOUT_REMOVER=classical`
switches it off.

The model's 320x320 soft mask is **refined** against the full photograph (a
guided filter, so the outline follows real garment edges), thresholded, cleaned
of specks and small holes, and then **rendered** by the same code the classical
remover uses: the mask is eroded a pixel, the colour of the edge band is
replaced with the garment's own interior colour, and the alpha is feathered
lightly. That rendering step is what removes the fringe, and it improves the
classical remover too.

The model file is **bundled in the package** (`app/services/images/models/`),
so `pip install .` on Render has it and nothing is downloaded at start-up. The
suite still needs no network.

### The fallback is part of the design, not an afterthought

`FallbackRemover(learned, classical)` answers with the classical remover when:

- onnxruntime or the model file is unavailable, or inference raises: logged
  once per distinct reason, not once per request;
- the learned mask is implausible (empty, nearly everything, a scrap): the
  classical one gets a go, and the more plausible of the two is returned.

`Cutout.is_plausible` is unchanged, and the endpoint still refuses a result that
is not plausible rather than returning a "cutout" that is the whole photo.

The classical remover was improved as well, since it is still the fallback: its
border clusters now count as background only when they hold a real share of the
border (a garment touching the frame no longer becomes "background"), and each
cluster's own spread is forgiven so carpet texture is background rather than a
field of small foregrounds. Two backgrounds in one border (board plus carpet)
are handled by the clustering.

## Why this model

The spike ran three candidates on the owner's two failing photographs:

| Model | Size | Result |
|---|---|---|
| `u2netp` | 4.6 MB | Cut both out cleanly, about 0.5 s on CPU at 320x320 |
| `silueta` | 44 MB | Worse, and heavier |
| `isnet-general-use` | 170 MB | Needs about 830 MB resident: cannot run on a 512 MB instance |

`u2netp` is the only one that is both good enough and small enough, by a wide
margin on the second axis. The model has a fixed 320x320 input (a 256 input was
tried to save memory and the graph rejects it), so there is no memory/quality
dial on the model itself.

## Memory

Render's free plan is 512 MB, so memory was the constraint the design was built
around, and was measured on the real process (`uvicorn app.main:app`, 12-megapixel
JPEG of about 2 MB, requests over HTTP, RSS sampled every 20 ms from `/proc`):

| | Baseline | Peak |
|---|---|---|
| Server idle | 71-77 MB | |
| Learned remover, one request at a time | | **382-396 MB** |
| Learned remover, 5 concurrent requests | | **395-404 MB** |
| Classical remover only | | 161 MB |

A bare script in the spike peaked near 365 MB from a 76 MB baseline, so almost
the whole transient is the network's own activations at 320x320, not the server
or the photograph. Between requests the process settles around 115 MB.

What keeps it there:

- **One session, loaded lazily**, with the CPU arena and memory pattern turned
  off and one thread, as in the spike.
- **One inference at a time**: a lock, and a single dedicated worker thread.
  The worker matters on its own: glibc gives each thread its own heap arena, and
  with requests spread over a pool of threads the peak was about 65 MB higher.
- **Admission control**: at most `CUTOUT_MAX_WAITING` (3) cutouts in flight; the
  rest get a 429 with `Retry-After`, because every waiting request holds its
  upload in memory.
- **Decode small**: JPEGs are decoded at a reduced scale (Pillow `draft`) to the
  size the cutout is returned at, so a 12-megapixel photo costs roughly what a
  1-megapixel one does. The model sees 320x320; the refinement and rendering run
  at the returned size (at most 768 px).
- **`malloc_trim`** after each request, which returns freed heap to the OS.

The honest reading: about 395 MB against a 512 MB limit leaves a margin of about
115 MB, which is enough but not generous. It is **under the 450 MB line, not far
under it**. If the free plan's accounting turns out tighter than `/proc` RSS,
`CUTOUT_REMOVER=classical` is a one-line environment change that drops the
peak to about 160 MB with no redeploy.

## Rate limiting

The cutout endpoint used to be exempt from the request limiter because it was
cheap. It is now the most expensive thing the server does per request, so it has
its own limiter (`CUTOUT_RATE_LIMIT_PER_MINUTE`, 12; `CUTOUT_RATE_LIMIT_PER_DAY`,
600), separate from the AI endpoints': a cutout spends CPU and memory, not the
Gemini allowance, so re-cutting a wardrobe neither eats the scan quota nor is
refused because scans did. There is no global cap, as there is no shared
allowance to protect; the single-inference lock and the admission control bound
the cost. The app already waits on a 429's `Retry-After`.

## Considered and rejected

- **A larger model** (`silueta`, `isnet-general-use`, or full-size U²-Net at
  170 MB). Worse results or far more memory; `isnet-general-use` alone would be
  OOM-killed on this plan.
- **Asking Gemini to do it.** It would put a network call, a quota and the
  owner's API key into something that today needs none, make every cutout
  non-deterministic, and Gemini returns descriptions, not pixel masks. ADR 0006
  keeps Gemini for what only a language model can do.
- **Downloading the model at first run.** Breaks the no-network start-up
  property and makes the first request slow.
- **Staying classical and tuning it.** The cases that fail are not tuning
  problems: when the border contains the garment or two surfaces, no colour rule
  can know which is which.

## Consequences

Cutouts of the owner's board-on-carpet photographs work, and edges are clean on
a dark tile. The server's image is about 60 MB larger (onnxruntime and the
model) and its peak memory is about 2.4x higher.

Limits that remain, because the model is small: thin straps, lace and
open-weave knits, and white-on-white (a white shirt on a white board) are the
hard cases, and photographs are still best taken filling the frame.

Existing cutouts do not change by themselves. The app has a "Redo cutouts"
action that re-cuts them from the stored originals, skipping hand-edited ones.
