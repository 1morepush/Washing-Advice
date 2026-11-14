#!/usr/bin/env bash
# Records what this checkout's app sends to the server and needs back, under
# contracts/compat/<version>/. Run it at each release, from app/:
#
#   tool/capture_compat.sh            # the version in pubspec.yaml
#   tool/capture_compat.sh 0.39.0     # name it explicitly
#
# Why, and what the files are: contracts/compat/README.md. In short, the server
# keeps answering every app version that "Use an earlier version" can open, and
# these records are how its tests know what each of them expects.
#
# Four steps, because the answer to "which response fields does this version
# need" is found by decoding a real server answer, and the real server answers
# the requests the app has just been recorded sending:
#
#   1. the app's requests, from the real AiGateway through a recording client;
#   2. the server's answers to those, with its fake providers, as samples;
#   3. the fields the app's decoders cannot do without, found by removing each
#      field of each sample in turn and seeing what stops decoding;
#   4. both suites, to prove the record is consistent.
#
# Needs flutter and dart on PATH (/opt/flutter/bin, /opt/dart-sdk/bin) and uv.
set -euo pipefail

cd "$(dirname "$0")/.."

version="${1:-$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' pubspec.yaml)}"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: '$version' is not a version like 0.39.0" >&2
  exit 64
fi
echo "Recording $version"

export COMPAT_VERSION="$version"

echo "1/4  requests"
COMPAT_WRITE=requests flutter test test/wire/compat_capture_test.dart

echo "2/4  the server's answers"
(cd ../server && COMPAT_WRITE_SAMPLES=1 uv run pytest tests/test_compat.py -k write_samples -q)

echo "3/4  the fields the app needs"
COMPAT_WRITE=required flutter test test/wire/compat_capture_test.dart

echo "4/4  checking"
unset COMPAT_VERSION
flutter test test/wire/compat_capture_test.dart
(cd ../server && uv run pytest tests/test_compat.py -q)

echo
echo "Recorded contracts/compat/$version. Commit it with the release."
