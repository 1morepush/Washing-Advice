/// Making a backup from the phone, and putting one back.
///
/// The core decides *what* (the archive layout, the merge rules); this is the
/// part that knows *where*: Drift for the records, an [ImageStore] for the
/// pictures, preferences for the settings.
///
/// ## Order of a restore, and why
///
/// 1. **Read and validate the file.** Done before this class is involved
///    (`BackupReader.open`), so a bad file is refused with nothing touched.
/// 2. **Plan** against what is on the phone now.
/// 3. **Write the images** the records to be written need.
/// 4. **Write the records in one transaction.**
/// 5. Only then settings, sync cursors and the clearing of replaced pictures.
///
/// Images before records, so no moment exists in which a record points at a
/// picture that has not been written. The cost is that a failure in step 4
/// leaves pictures nothing points at; those are deleted, except any that were
/// already referenced before (a restore may re-save a file that was there).
/// A failure anywhere before step 4 commits has changed no record, and one in
/// step 4 rolls back, so *the records are never half-restored*.
///
/// What is not atomic: the pictures a **replace** discards are removed after
/// the commit, best effort. A crash between leaves some unreferenced files,
/// which cost space and nothing else.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/settings.dart';
import '../../data/drift/database.dart';
import '../../data/drift/drift_event_log.dart';
import '../../data/drift/drift_listing_repository.dart';
import '../../data/drift/drift_outfit_repository.dart';
import '../../data/drift/drift_wardrobe_repository.dart';
import '../../data/images/image_store.dart';

/// What a restore did, in numbers.
final class RestoreOutcome {
  const RestoreOutcome({
    required this.plan,
    required this.imagesWritten,
    required this.imagesMissing,
    required this.settingsApplied,
  });

  final RestorePlan plan;

  /// Pictures copied into this phone's storage.
  final int imagesWritten;

  /// Pictures the records mention that the backup never had.
  final int imagesMissing;

  final int settingsApplied;

  RestoreMode get mode => plan.mode;

  bool get changedAnything =>
      plan.replacesEverything ||
      plan.items.isNotEmpty ||
      plan.events.isNotEmpty ||
      plan.outfits.isNotEmpty ||
      plan.listings.isNotEmpty ||
      settingsApplied > 0;
}

/// A restore that failed after reading the file.
///
/// Carries what to tell the person. By the time one is thrown no record has
/// changed.
final class RestoreFailed implements Exception {
  const RestoreFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackupService {
  BackupService({
    required AppDatabase database,
    required this.images,
    required this.settings,
    required this.appVersion,
    DateTime Function()? now,
  }) : _db = database,
       _now = now ?? DateTime.now;

  final AppDatabase _db;
  final ImageStore images;
  final SettingsStore settings;
  final String appVersion;
  final DateTime Function() _now;

  /// Called inside the restore transaction, after the records are written.
  /// Lets a test fail a restore at the last moment and check it all rolls back.
  @visibleForTesting
  Future<void> Function()? afterWritesForTest;

  /// Everything on the phone, as a backup would hold it.
  Future<BackupSnapshot> snapshot() async => BackupSnapshot(
    // Straight from the table rather than through a query: a query for the
    // wardrobe leaves out deleted garments, and a backup must not.
    items: [for (final row in await _db.select(_db.items).get()) itemFrom(row)],
    events: await DriftEventLog(_db).all(),
    outfits: await DriftOutfitRepository(_db).all(),
    listings: await DriftListingRepository(_db).all(),
    settings: settings.portableSettings(),
  );

  /// How many garments the person owns, counted as the wardrobe screen does.
  Future<int> ownedGarments() =>
      DriftWardrobeRepository(_db).count(const WardrobeQuery.owned());

  /// What is on the phone now, as counts, for saying what a replace would lose.
  Future<BackupCounts> currentCounts() async {
    final now = await snapshot();
    final deleted = now.items
        .where((i) => i.lifecycle == LifecycleState.removed)
        .length;
    return BackupCounts(
      items: now.items.length - deleted,
      deletedItems: deleted,
      events: now.events.length,
      outfits: now.outfits.length,
      listings: now.listings.length,
      images: now.imageUris.length,
    );
  }

  /// Builds the archive. Records nothing about it: whether it was *kept* is
  /// the caller's to say, once it has been handed over.
  Future<BuiltBackup> create({BackupProgress? onProgress}) async {
    final everything = await snapshot();
    return BackupWriter.build(
      everything,
      appVersion: appVersion,
      createdAt: _now(),
      readImage: images.read,
      onProgress: onProgress,
    );
  }

  /// What a restore of [backup] would do in each mode, without doing it.
  Future<Map<RestoreMode, RestorePlan>> previews(OpenedBackup backup) async {
    final current = await snapshot();
    return {
      for (final mode in RestoreMode.values)
        mode: planRestore(
          current: current,
          incoming: backup.snapshot,
          mode: mode,
        ),
    };
  }

  /// Restores [backup]. Throws [RestoreFailed] with nothing changed.
  Future<RestoreOutcome> restore(
    OpenedBackup backup,
    RestoreMode mode, {
    BackupProgress? onProgress,
  }) async {
    final current = await snapshot();
    final plan = planRestore(
      current: current,
      incoming: backup.snapshot,
      mode: mode,
    );

    // Stable across restores and across which records win, so a second restore
    // lands on the files the first wrote.
    final names = restoreNames(backup.imageUris);
    final wanted = plan.imageUris.where(names.containsKey).toList();

    // Pictures that only a listing needs, and that are already here, stay as
    // they are in a merge. A listing started from a garment shares that
    // garment's file; the backup's copy of it may be older than the one this
    // phone kept because its garment was edited later, and a listing must not
    // put the old picture back under the new garment.
    final needed = plan.itemImageUris;
    final spare = mode == RestoreMode.merge
        ? plan.imageUris.where((uri) => !needed.contains(uri)).toSet()
        : const <String>{};

    final moved = <String, String>{};
    final newlyWritten = <String>[];
    final alreadyReferenced = current.imageUris;
    try {
      for (var i = 0; i < wanted.length; i++) {
        onProgress?.call(i, wanted.length);
        if (i % 4 == 3) await Future<void>.delayed(Duration.zero);

        final uri = wanted[i];
        if (spare.contains(uri) && await images.read(uri) != null) {
          moved[uri] = uri;
          continue;
        }
        final Uint8List? bytes = backup.imageBytes(uri);
        if (bytes == null) continue;
        final stored = await images.save(bytes, name: names[uri]!);
        moved[uri] = stored;
        newlyWritten.add(stored);
      }
      onProgress?.call(wanted.length, wanted.length);

      await _commit(plan.withImageUris(moved));
    } on Object catch (error) {
      await _discard(
        newlyWritten.where((uri) => !alreadyReferenced.contains(uri)),
      );
      throw RestoreFailed(
        'The restore did not finish, and nothing on this phone was changed. '
        '(${_brief(error)})',
      );
    }

    final restored = plan.withImageUris(moved);

    if (mode == RestoreMode.replace) {
      // The pictures nothing refers to any more. Best effort, after the
      // commit: failing to delete a file costs space, not a wardrobe.
      final kept = BackupSnapshot(
        items: restored.items,
        listings: restored.listings,
      ).imageUris;
      await _discard(current.imageUris.where((uri) => !kept.contains(uri)));
    }

    final applied = await settings.applyPortableSettings(
      backup.snapshot.settings,
      overwrite: mode == RestoreMode.replace,
    );

    final outcome = RestoreOutcome(
      plan: plan,
      imagesWritten: newlyWritten.length,
      imagesMissing: plan.imageUris.length - moved.length,
      settingsApplied: applied,
    );
    if (outcome.changedAnything) {
      // Sync sends what changed since its cursor, and these records are older
      // than that. Forgetting the cursors makes the next sync look at
      // everything, which merging makes harmless.
      await settings.clearCursors();
    }

    return outcome;
  }

  Future<void> _commit(RestorePlan plan) => _db.transaction(() async {
    if (plan.replacesEverything) {
      await _db.delete(_db.items).go();
      await _db.delete(_db.events).go();
      await _db.delete(_db.outfits).go();
      await _db.delete(_db.listings).go();
    }

    await DriftWardrobeRepository(_db).saveAll(plan.items);
    await DriftEventLog(_db).appendAll(plan.events);
    final outfits = DriftOutfitRepository(_db);
    for (final outfit in plan.outfits) {
      await outfits.save(outfit);
    }
    final listings = DriftListingRepository(_db);
    for (final listing in plan.listings) {
      await listings.save(listing);
    }

    await afterWritesForTest?.call();
  });

  Future<void> _discard(Iterable<String> uris) async {
    for (final uri in uris) {
      try {
        await images.delete(uri);
      } on Object {
        // See the library comment: a file left behind costs space only.
      }
    }
  }

  String _brief(Object error) {
    final text = error.toString().replaceAll('\n', ' ');
    return text.length > 120 ? '${text.substring(0, 120)}…' : text;
  }
}
