/// The layout of what this app keeps on a device, and whether an older build
/// can still read it.
///
/// "Use an earlier version" opens a build that is older than the data. A
/// wardrobe saved by 0.39 at database layout 6 cannot be opened by a build that
/// only knows layouts up to 5: Drift refuses to open a database that is newer
/// than its code, and the person is left looking at an app that will not start.
/// Worse would be a build that opened it and wrote back what it understood.
/// So every build declares what it writes, the newest build records what is
/// stored, and the picker only offers a build that reads at least that.
///
/// Only layouts that *cannot be skipped* belong here: the two Drift databases.
/// Preferences and the JSON payloads inside rows are read leniently by every
/// build (an unknown key or enum member is ignored, see
/// `SettingsStore._readProfile`), so a newer one does not lock an older one
/// out.
library;

import '../data/drift/database.dart';
import '../data/images/image_database.dart';

/// Each stored thing that has a layout, and the number of the layout.
///
/// Compared name by name: a build reads the data when, for every name, its
/// number is at least the stored one. A name the other side has never heard of
/// counts as zero, so adding a new kind of storage later does not make an old
/// record look unreadable by an old build that never used it.
final class DataFormat {
  const DataFormat(this.parts);

  /// Reads the shape written by `tool/web_site.dart` and by [toJson].
  /// Anything else — missing, mangled, not numbers — is "unknown", which is
  /// null, never a guess.
  static DataFormat? fromJson(Object? json) {
    if (json is! Map) return null;
    final parts = <String, int>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (entry.key is! String || value is! int || value < 0) return null;
      parts[entry.key as String] = value;
    }
    return parts.isEmpty ? null : DataFormat(parts);
  }

  final Map<String, int> parts;

  Map<String, int> toJson() => Map.of(parts);

  int operator [](String name) => parts[name] ?? 0;

  /// The larger number for every name. What is stored only ever goes up:
  /// opening an older build must not lower the record of what the wardrobe
  /// has been saved at, because the wardrobe was not downgraded.
  DataFormat mergedWith(DataFormat other) => DataFormat({
    for (final name in {...parts.keys, ...other.parts.keys})
      name: this[name] > other[name] ? this[name] : other[name],
  });

  /// What a build whose format is this one could not read of [stored], in
  /// words ("wardrobe", "photos"), or empty when it can read all of it.
  List<String> cannotRead(DataFormat stored) => [
    for (final name in stored.parts.keys)
      if (stored[name] > this[name]) _labels[name] ?? name,
  ];

  @override
  bool operator ==(Object other) =>
      other is DataFormat &&
      other.parts.length == parts.length &&
      parts.entries.every((e) => other.parts[e.key] == e.value);

  @override
  int get hashCode => Object.hashAllUnordered(
    parts.entries.map((e) => Object.hash(e.key, e.value)),
  );

  @override
  String toString() => 'DataFormat($parts)';
}

/// How each name reads in a sentence a person will see.
const _labels = {'wardrobe': 'wardrobe', 'images': 'photos'};

/// What this build writes. The names match `tool/web_site.dart`, which stamps
/// the same two numbers on every published build, read out of the same
/// constants' source lines — a test pins that they agree.
const currentDataFormat = DataFormat({
  'wardrobe': AppDatabase.currentSchemaVersion,
  'images': ImageDatabase.currentSchemaVersion,
});

/// The sentence for a build that cannot read the stored data, or null when it
/// can. [stored] is the largest layout known to have been written here, with
/// this build's own as a floor: whatever is running has at the least written
/// what it writes, so a record that could not be read or written never makes
/// the answer more permissive than the running build itself.
String? whyUnreadable({
  required String version,
  required DataFormat build,
  required DataFormat? stored,
}) {
  final known = stored == null
      ? currentDataFormat
      : currentDataFormat.mergedWith(stored);
  final blockers = build.cannotRead(known);
  if (blockers.isEmpty) return null;
  final what = switch (blockers) {
    [final one] => 'Your $one has',
    [final a, final b] => 'Your $a and $b have',
    _ => 'Your ${blockers.join(', ')} have',
  };
  return '$what been saved in a newer format than $version understands.';
}
