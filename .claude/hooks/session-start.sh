#!/usr/bin/env bash
# Restores the Dart SDK so a fresh session can run `dart analyze` and
# `dart test` immediately.
#
# Claude Code on the web runs in an ephemeral container: the repository is
# cloned fresh and any toolchain installed last session is gone. `wardrobe_core`
# is pure Dart with no Flutter dependency, so the 233 MB Dart SDK is all that is
# needed to run the entire test suite — no Flutter, no Android SDK, no emulator.
set -euo pipefail

DART_HOME="${DART_HOME:-/opt/dart-sdk}"
DART_CHANNEL_URL="https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip"

if [ -x "$DART_HOME/bin/dart" ]; then
  echo "Dart already present: $("$DART_HOME/bin/dart" --version 2>&1)"
else
  echo "Installing the Dart SDK to $DART_HOME ..."
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  curl -fsSL -o "$tmp/dartsdk.zip" "$DART_CHANNEL_URL"

  # The archive always contains a top-level `dart-sdk/` directory, so it is
  # unpacked into a staging area and then moved into place. Extracting straight
  # to $(dirname "$DART_HOME") would only land correctly when DART_HOME happens
  # to be named `dart-sdk`.
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$tmp/dartsdk.zip" -d "$tmp/stage"
  else
    # Busybox images often lack unzip; Python is always available here and
    # preserves the executable bits that the SDK binaries need.
    python3 - "$tmp/dartsdk.zip" "$tmp/stage" <<'PY'
import os, sys, zipfile

archive, destination = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as bundle:
    bundle.extractall(destination)
    for name in bundle.namelist():
        path = os.path.join(destination, name)
        if os.path.isfile(path):
            mode = (bundle.getinfo(name).external_attr >> 16) & 0o777
            if mode:
                os.chmod(path, mode)
PY
  fi

  mkdir -p "$(dirname "$DART_HOME")"
  rm -rf "$DART_HOME"
  mv "$tmp/stage/dart-sdk" "$DART_HOME"

  # Fail loudly rather than leaving later commands to report a confusing
  # "dart: not found" — a silently broken hook breaks every future session.
  if [ ! -x "$DART_HOME/bin/dart" ]; then
    echo "error: the Dart SDK did not install correctly at $DART_HOME" >&2
    exit 1
  fi
  echo "Installed: $("$DART_HOME/bin/dart" --version 2>&1)"
fi

export PATH="$DART_HOME/bin:$PATH"

# The Flutter app needs the Flutter SDK, which is much larger than Dart and is
# only useful if it is already in the image. It is not installed here on
# purpose: a ~1 GB download would delay the start of every session, including
# the many that only touch the core or the server. When the image provides it,
# it is picked up; otherwise the core and server work as before and the app's
# commands are reported as unavailable rather than failing obscurely later.
FLUTTER_HOME="${FLUTTER_HOME:-/opt/flutter}"
if [ -x "$FLUTTER_HOME/bin/flutter" ]; then
  export PATH="$FLUTTER_HOME/bin:$PATH"
  HAVE_FLUTTER=1
  echo "Flutter present: $("$FLUTTER_HOME/bin/flutter" --version 2>/dev/null | head -1)"
else
  HAVE_FLUTTER=0
fi

# Warm the package caches so the first test run does not stall on a download.
if [ -d packages/wardrobe_core ]; then
  (cd packages/wardrobe_core && dart pub get >/dev/null 2>&1) \
    && echo "wardrobe_core dependencies resolved." \
    || echo "warning: 'dart pub get' failed; run it by hand in packages/wardrobe_core."
fi

if [ "$HAVE_FLUTTER" = "1" ] && [ -d app ]; then
  (cd app && flutter pub get >/dev/null 2>&1) \
    && echo "app dependencies resolved." \
    || echo "warning: 'flutter pub get' failed; run it by hand in app."
fi

cat <<'EOF'

Ready. From packages/wardrobe_core:
  dart analyze
  dart test
  dart run example/sort_demo.dart
EOF

if [ "$HAVE_FLUTTER" = "1" ]; then
  cat <<'EOF'
From app:
  flutter analyze
  flutter test
  dart run build_runner build   # after changing the Drift schema
EOF
else
  cat <<'EOF'
Flutter was not found at /opt/flutter, so the app cannot be built or tested in
this session. The core and the server are unaffected.
EOF
fi
