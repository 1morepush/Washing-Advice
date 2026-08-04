# 6. Gemini-only vision behind a port

Status: accepted

## Context

The original plan listed Gemini, ML Kit, OpenCV, MediaPipe and Tesseract. Each
additional CV library is a native build burden on both iOS and Android, and a
source of version conflicts and app-size growth.

## Decision

One `VisionPort` interface in the core, with Gemini's multimodal structured-JSON
mode as the only implementation for now. It handles garment attributes,
care-label OCR, symbol interpretation and multi-item pile detection in a single
call per scan type.

No OpenCV, MediaPipe or Tesseract. ML Kit is deferred to a later milestone for
barcode scanning and a cheap on-device "is this even clothing?" prefilter.

The API key never ships in the app: Gemini is called from the backend, and the
app talks to an `AiGateway` so a direct-to-Gemini transport remains available for
development without leaking the key in production builds.

## Consequences

Far less native integration work, and one prompt surface to tune rather than
four pipelines to keep in agreement.

The cost is that scanning requires connectivity. That is an acceptable split:
scanning needs the network, but browsing the wardrobe, sorting laundry from
already-known items, and every recommendation the core makes all work offline —
which is the part that matters in a laundry room.

An on-device OCR prefilter remains attractive for cost and offline tag reading.
The orchestration layer is designed as a pipeline of stages precisely so it can
be added as a second stage without rework.
