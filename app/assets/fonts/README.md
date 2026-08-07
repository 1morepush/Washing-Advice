# Bundled fonts

**Liberation Sans**, regular and bold.
Copyright © 2012 Red Hat, Inc., with Reserved Font Name "Liberation".
Digitized data copyright © 2010 Google Corporation, with Reserved Font Name
"Arimo", "Tinos" and "Cousine".
Licensed under the [SIL Open Font License, version 1.1](https://scripts.sil.org/OFL).

## Why it is here

Flutter's web build has no system fonts to fall back on: CanvasKit renders text
itself, and with no font asset it fetches Roboto from Google's CDN at runtime.
That makes the first paint depend on a network the app otherwise does not need,
and in a sandboxed CI container that request simply fails — which is how this
was found, as screenshots that rendered every icon and not one word.

Bundling a font makes the web build self-contained, which is the same goal as
the `--no-web-resources-cdn` flag used to build it.

It is applied **on web only** (see `lib/core/theme.dart`). Android and iOS have
Roboto and SF Pro already, and those are better on their own platforms than
anything shipped in the bundle.
