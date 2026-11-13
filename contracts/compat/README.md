# Compatibility with older apps

The web app keeps its recent releases published, and **Settings → Use an earlier
version** lets a phone run any of them. The server is one deployment that all of
them talk to. A server change that is fine for the newest app can break an older
one that nobody is looking at.

So each release's wire format is recorded here, and the server's tests replay
all of it.

```
contracts/compat/
  <version>/
    requests/<endpoint>.json    what that version's app sent
    required/<endpoint>.json    the response fields its decoders cannot do without
  samples/                      what the server answered the newest requests with
  assets/                       the photographs the requests refer to
```

## What the files are

A **request** is the HTTP request as the real `AiGateway` made it, recorded
through a recording client: method, path, content type, text fields or JSON, and
which asset photograph was attached (named, not inlined). Not hand-written, so it
is what the app really sends, awkward fields and all.

A **required** file lists the response fields the app *needs*, as paths
(`result.colors.value[].l`, with `[]` meaning "in every element"). It is
**derived**: the app's own decoders are run against a sample answer, then again
with each field removed in turn, and a field whose removal makes decoding throw
is required. A field the app ignores, or defaults when absent, is not listed, so
the server is free to drop or rename those. It cannot be too generous, because
nobody wrote it. What it cannot see is a field the sample does not contain (the
fake provider's price search has no comparables, so what the app needs from a
comparable is not probed). When such a field matters, record a richer sample.

`server/tests/test_compat.py` replays every request of every recorded version
against the app with the fake providers and asserts a 200, and that every
required path is present in the answer (the right content type, for the stain
stream and the cutout image). `app/test/wire/compat_capture_test.dart` is the
other half: it fails if the app now sends something different from, or needs
something different than, its own version's record.

Not covered: the sync endpoints (off on the deployed server, which answers 404;
the app says so), and the weather calls, which go to Open-Meteo, not here.

## Recording a release

At each release, from `app/` on the release commit:

```sh
tool/capture_compat.sh          # the version in pubspec.yaml
```

It records the requests, has the server answer them, derives the required
fields, and runs both suites. Commit `contracts/compat/<version>/` (and any
changed `samples/`) with the release. Two tests refuse a release that did not do
it: the app's, and `test_the_current_app_version_is_recorded` on the server.

## The rule

**Server changes are additive within the supported window**, which is the
versions offered for rollback: the current one and the five before it (the
`--keep` of `app/tool/web_site.dart`).

* Adding a response field, a request field with a default, or an endpoint is
  free.
* Removing or renaming a request field, a response field a version requires, or
  an endpoint fails `test_compat.py`. Keep the old shape alongside the new one
  until the version that needs it leaves the window.
* Editing a fixture to make a failure pass is a decision to **stop supporting
  that version**, and should be made as one: say so in the commit, and do not
  offer that version any more (it will fall out of the window by itself, or
  remove it from the store).
* When a version leaves the window, delete its folder here. Leaving it costs
  only test time; deleting it is the deliberate act of dropping support.

## Where the record came from

Recorded at the release commit of each version, with the same capture test, from
a checkout of that commit (the test file copied in, `scan_worn` left out before
0.37.0, which had no such call):

| Version | Source commit | Result |
|---|---|---|
| 0.34.0 | `80a8f2b` | recovered; identical to 0.35.0 and 0.36.0 |
| 0.35.0 | `cf96e5d` | recovered |
| 0.36.0 | `9dbd923` | recovered |
| 0.37.0 | `871ffc1` | recovered; adds `scan_worn` |
| 0.38.0 | `7576106` | recorded at the release |

The wire format did not change across 0.34.0 to 0.38.0 except for the addition
of the worn-photo scan, so the five records differ only by that endpoint. What
could not be recovered: anything before 0.34.0 (not attempted: it is outside the
window), and the sync endpoints (not recorded, see above).
