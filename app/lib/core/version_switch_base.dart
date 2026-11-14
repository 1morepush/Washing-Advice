/// What the app needs from the web page to move between published versions.
///
/// The site keeps every recent release under `v/<version>/` next to the newest
/// at its root (see `tool/web_site.dart`). Moving between them is navigation
/// plus one stored choice, and both belong to the browser — so this is an
/// interface, with the browser's implementation in `version_switch_web.dart`
/// and a stand-in everywhere else, and a test supplies a fake that records
/// what it was asked to do rather than navigating a test runner anywhere.
library;

import 'data_format.dart';

/// Where the chosen version is remembered, for the script at the top of
/// `web/index.html` to read before Flutter starts.
///
/// Outside the `flutter.` prefix that `shared_preferences` writes under, so
/// nothing the app does with its own settings can touch it, and it is not a
/// setting somebody can lose by resetting them. Pinned to the page's script, to
/// the injected bar, and to `web/404.html` by a test.
const pinnedVersionKey = 'washingAdvice.pinnedVersion';

/// Where the largest data layout ever written on this browser is recorded,
/// as JSON: `{"wardrobe":5,"images":1}`. See [DataFormat].
const dataFormatKey = 'washingAdvice.dataFormat';

/// One published version, as `versions.json` describes it.
final class SiteVersion {
  const SiteVersion({
    required this.version,
    required this.name,
    required this.date,
    required this.dataFormat,
  });

  /// Null for an entry that cannot be used: a version that is not three
  /// numbers, a date that is not one, or a data format that is unreadable.
  /// Dropped by the list rather than shown half-described — a version whose
  /// data format is unknown cannot be checked, so it must not be offered.
  static SiteVersion? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final name = json['name'];
    final date = json['date'];
    final format = DataFormat.fromJson(json['dataFormat']);
    if (version is! String || parseVersion(version) == null) return null;
    if (name is! String || date is! String || format == null) return null;
    final parsed = DateTime.tryParse(date);
    if (parsed == null) return null;
    return SiteVersion(
      version: version,
      name: name,
      date: parsed,
      dataFormat: format,
    );
  }

  final String version;
  final String name;
  final DateTime date;
  final DataFormat dataFormat;
}

/// What `versions.json` says is published.
final class SiteVersions {
  const SiteVersions({required this.earlier});

  /// Reads the file's text. Throws [FormatException] for anything that is not
  /// the shape the assembly script writes, which the list shows as a quiet
  /// "could not load", the same as being offline.
  factory SiteVersions.parse(Map<String, Object?> json) {
    final list = json['versions'];
    if (list is! List) throw const FormatException('No versions list.');
    return SiteVersions(
      earlier: [
        for (final entry in list)
          if (SiteVersion.fromJson(entry) case final SiteVersion version)
            version,
      ],
    );
  }

  /// Every version published under `v/`, in the order the file gives.
  final List<SiteVersion> earlier;

  /// The ones older than [running], newest first.
  List<SiteVersion> olderThan(String running) => [
    for (final version in earlier)
      if (compareVersions(version.version, running) < 0) version,
  ]..sort((a, b) => compareVersions(b.version, a.version));
}

/// `0.38.0` as numbers, or null when it is not three of them.
List<int>? parseVersion(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

/// Orders `0.9.0` before `0.10.0`, which comparing the text would not.
/// Anything that is not a version sorts as the lowest.
int compareVersions(String a, String b) {
  final left = parseVersion(a) ?? const [0, 0, 0];
  final right = parseVersion(b) ?? const [0, 0, 0];
  for (var i = 0; i < 3; i++) {
    if (left[i] != right[i]) return left[i].compareTo(right[i]);
  }
  return 0;
}

/// Moving between published versions.
abstract interface class VersionSwitcher {
  /// Whether there is anywhere to move: only a page on the web has the site's
  /// other versions beside it.
  bool get available;

  /// Reads `versions.json` fresh. Throws when it cannot: offline, not found,
  /// not the expected shape. The caller shows that quietly.
  Future<SiteVersions> fetchVersions();

  /// The largest layout the browser's record says has been written here, or
  /// null when there is no record (or none could be read).
  DataFormat? get storedFormat;

  /// Remembers [version] as the one to open, then opens it. On the web the page
  /// is replaced, so the future does not complete in any way that matters.
  Future<void> switchTo(String version);
}

/// For where there is no site beside the app: nothing to list, nowhere to go.
final class NoVersionSwitcher implements VersionSwitcher {
  const NoVersionSwitcher();

  @override
  bool get available => false;

  @override
  Future<SiteVersions> fetchVersions() async => const SiteVersions(earlier: []);

  @override
  DataFormat? get storedFormat => null;

  @override
  Future<void> switchTo(String version) async {}
}
