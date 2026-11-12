/// What a backup says about itself, and why one can be refused.
///
/// The manifest is the first thing read and the thing everything else is
/// checked against: a format version so a file from the future is turned away
/// with a sentence rather than half-read, and counts so a file that was cut
/// short is noticed even if the cut happened to land between two entries.
library;

import 'dart:math' as math;

/// What every backup calls itself, so that some other zip is not mistaken for
/// one just because it has a file named `manifest.json`.
const String backupFormatName = 'washing-advice-backup';

/// The layout this build writes and the newest one it can read.
///
/// Moves only when a file written by this build could not be understood by an
/// older one — a renamed or removed key, a new kind of record that cannot be
/// skipped. Adding a key does not move it: readers ignore keys they do not
/// know, which is what lets a newer build add to a backup without locking
/// every older one out of it.
const int backupFormatVersion = 1;

/// Why a backup could not be used.
///
/// Every message is written to be read by the person who tapped the button, as
/// the whole of what they are told. None of these is thrown once anything has
/// been written: they all come from *reading*, before the first change.
sealed class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A file that is not a Washing Advice backup at all.
final class BackupNotABackup extends BackupException {
  const BackupNotABackup(super.message);
}

/// A backup from a newer version of the app than this one.
///
/// Refused rather than read as far as it goes. A newer layout may carry things
/// this build would drop on the floor, and a restore that quietly leaves out
/// half a wardrobe is worse than one that says "update first".
final class BackupTooNew extends BackupException {
  BackupTooNew({required this.found, this.appVersion})
      : super(
          'This backup was made by a newer version of Washing Advice'
          '${appVersion == null ? '' : ' ($appVersion)'}, and this version '
          'cannot read it safely. Update the app, then try again.',
        );

  /// The format version the file declares.
  final int found;

  /// The app version that wrote it, when it said.
  final String? appVersion;
}

/// A file that claims to be a backup and is damaged: cut short, altered, or
/// missing a part it says it has.
final class BackupCorrupt extends BackupException {
  const BackupCorrupt(super.message);
}

/// How much is in a backup.
final class BackupCounts {
  const BackupCounts({
    this.items = 0,
    this.deletedItems = 0,
    this.events = 0,
    this.outfits = 0,
    this.listings = 0,
    this.images = 0,
    this.missingImages = 0,
  });

  /// Garments somebody can see: every lifecycle state except deleted.
  final int items;

  /// Garments that were deleted. Kept in the file because a deletion is a
  /// record like any other, and restoring without it would bring a deleted
  /// garment back the next time two copies of the wardrobe met.
  final int deletedItems;

  /// Entries in the history: wears, washes, repairs and the rest.
  final int events;
  final int outfits;
  final int listings;

  /// Image files in the archive: photographs and cutouts, each stored once
  /// however many records point at it.
  final int images;

  /// Images the records mention that could not be read when the backup was
  /// made, so are not in the archive. The records are kept all the same, as
  /// they were on the phone, where the app already shows a placeholder.
  final int missingImages;

  /// "84 garments, 212 photos, 3 listings": what a person would miss, in the
  /// words they would use, leaving out what there is none of.
  String get summary {
    final parts = <String>[
      _count(items, 'garment'),
      if (images > 0) _count(images, 'photo'),
      if (outfits > 0) _count(outfits, 'outfit'),
      if (listings > 0) _count(listings, 'listing'),
      if (events > 0)
        _count(events, 'history entry', plural: 'history entries'),
    ];
    return parts.join(', ');
  }

  Map<String, Object?> toJson() => {
        'items': items,
        'deletedItems': deletedItems,
        'events': events,
        'outfits': outfits,
        'listings': listings,
        'images': images,
        'missingImages': missingImages,
      };

  /// Reads the counts. A missing one is zero; one that is not a whole number
  /// is damage, which is the caller's to report.
  factory BackupCounts.fromJson(Map<String, Object?> json) {
    int read(String key) => switch (json[key]) {
          null => 0,
          final int value when value >= 0 => value,
          _ => throw FormatException('"$key" is not a count'),
        };

    return BackupCounts(
      items: read('items'),
      deletedItems: read('deletedItems'),
      events: read('events'),
      outfits: read('outfits'),
      listings: read('listings'),
      images: read('images'),
      missingImages: read('missingImages'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BackupCounts &&
      other.items == items &&
      other.deletedItems == deletedItems &&
      other.events == events &&
      other.outfits == outfits &&
      other.listings == listings &&
      other.images == images &&
      other.missingImages == missingImages;

  @override
  int get hashCode => Object.hash(
        items,
        deletedItems,
        events,
        outfits,
        listings,
        images,
        missingImages,
      );

  @override
  String toString() => 'BackupCounts($summary)';
}

/// "1 garment", "84 garments".
String _count(int n, String noun, {String? plural}) =>
    '$n ${n == 1 ? noun : (plural ?? '${noun}s')}';

/// The manifest at the front of an archive.
final class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.createdAt,
    required this.counts,
    this.formatVersion = backupFormatVersion,
  });

  final int formatVersion;

  /// The app that wrote it, e.g. `0.34.0`. For a person asking "which phone
  /// is this from"; nothing reads it to decide anything.
  final String appVersion;

  /// When it was made, in UTC.
  final DateTime createdAt;

  final BackupCounts counts;

  Map<String, Object?> toJson() => {
        'format': backupFormatName,
        'formatVersion': formatVersion,
        'appVersion': appVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'counts': counts.toJson(),
      };

  /// Reads a manifest, or says in a [BackupException] why it is not one.
  ///
  /// The version is checked *before* anything else is trusted: a manifest from
  /// a newer layout may have moved the very keys read below.
  static BackupManifest fromJson(Map<String, Object?> json) {
    if (json['format'] != backupFormatName) {
      throw const BackupNotABackup('This file is not a Washing Advice backup.');
    }

    final version = json['formatVersion'];
    if (version is! int || version < 1) {
      throw const BackupCorrupt(
        'This backup does not say which format it uses, so it cannot be read.',
      );
    }
    final appVersion = switch (json['appVersion']) {
      final String text when text.isNotEmpty => text,
      _ => null,
    };
    if (version > backupFormatVersion) {
      throw BackupTooNew(found: version, appVersion: appVersion);
    }

    try {
      return BackupManifest(
        formatVersion: version,
        appVersion: appVersion ?? 'unknown',
        createdAt: DateTime.parse(json['createdAt']! as String).toUtc(),
        counts: BackupCounts.fromJson(
          (json['counts'] as Map<String, Object?>?) ?? const {},
        ),
      );
    } on Object {
      throw const BackupCorrupt(
        "This backup's label is damaged, so it cannot be read.",
      );
    }
  }
}

/// The name a backup is saved under: `washing-advice-backup-2026-11-11.zip`.
///
/// Dated by [at] as given, so the caller decides whose midnight it is — a
/// person asking for a backup at ten at night means today, not tomorrow in
/// Greenwich.
String backupFileName(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  final year = at.year.toString().padLeft(4, '0');
  return 'washing-advice-backup-$year-${two(at.month)}-${two(at.day)}.zip';
}

/// A size a person can read: `812 KB`, `12.4 MB`.
String backupSizeLabel(int bytes) {
  if (bytes < 1000) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1000;
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  // Whole numbers once there are three digits; a decimal below that, where
  // it is the difference between 1.2 MB and 1 MB.
  final shown = value >= 100
      ? math.max(value, 1).round().toString()
      : value.toStringAsFixed(1);
  return '$shown ${units[unit]}';
}
