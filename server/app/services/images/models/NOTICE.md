# Bundled model: u2netp

`u2netp.onnx` is the small variant of **U²-Net** ("U2-Net: Going Deeper with
Nested U-Structure for Salient Object Detection", Qin et al., Pattern
Recognition 2020), exported to ONNX.

- Licence: **Apache License 2.0** (the U²-Net repository,
  https://github.com/xuebinqin/U-2-Net, is Apache-2.0).
- Obtained from: https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2netp.onnx
  (the `rembg` project's release of the exported weights; `rembg` is MIT).
- Size: 4,574,861 bytes.
- SHA-256: `309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8`
- Modified: no. It is used as published.

It is shipped inside the server package, not downloaded at start-up, so a
deployment built with `pip install .` has it with no network. See
`docs/adr/0010-small-learned-cutout-model.md` for why this model.

The licence text is at http://www.apache.org/licenses/LICENSE-2.0.
