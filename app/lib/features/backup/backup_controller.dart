/// What the Backup group on the settings screen is doing, and what it last did.
///
/// A [StateNotifier] like the sync controller beside it: one value that says
/// whether something is running, how far along it is, and what the last thing
/// that finished had to say. The dialogs that ask the person to choose are the
/// screen's business; this does the work around them.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/backup/backup_files_port.dart';
import '../../core/settings.dart';
import '../settings/patch_notes.dart';
import 'backup_service.dart';

/// The service, built from the phone's real storage.
///
/// Read only when a button is pressed, never while drawing the screen: a test
/// that opens Settings with the wardrobe faked must not open a database.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(databaseProvider),
    images: ref.watch(imageStoreProvider),
    settings: ref.watch(settingsStoreProvider),
    // The newest note is the version the app declares; a test keeps the two
    // equal, so there is no second place for it to be written down.
    appVersion: patchNotes.first.version,
  ),
);

/// When the last backup was made, as state so the line under the button
/// changes the moment a new one is saved.
final lastBackupAtProvider = StateProvider<DateTime?>(
  (ref) => ref.watch(settingsStoreProvider).lastBackupAt,
);

final garmentsAtLastBackupProvider = StateProvider<int?>(
  (ref) => ref.watch(settingsStoreProvider).garmentsAtLastBackup,
);

/// Which backup chore is running.
enum BackupActivity { idle, saving, reading, restoring }

/// What the last chore had to say, for the panel under the buttons.
final class BackupNotice {
  const BackupNotice(this.title, {this.detail, this.isError = false});

  final String title;
  final String? detail;
  final bool isError;
}

final class BackupState {
  const BackupState({
    this.activity = BackupActivity.idle,
    this.stage,
    this.done = 0,
    this.total = 0,
    this.notice,
  });

  final BackupActivity activity;

  /// What is being done, in the words shown beside the progress bar.
  final String? stage;
  final int done;
  final int total;
  final BackupNotice? notice;

  bool get busy => activity != BackupActivity.idle;

  /// 0..1, or null when there is no count to show a fraction of.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0, 1);
}

/// A backup file read and found sound, with the name it came under.
final class ChosenBackup {
  const ChosenBackup(this.backup, this.fileName);

  final OpenedBackup backup;
  final String fileName;
}

class BackupController extends StateNotifier<BackupState> {
  BackupController(this._ref) : super(const BackupState());

  final Ref _ref;

  /// Makes a backup and hands it to the person.
  Future<void> save() async {
    if (state.busy) return;
    state = const BackupState(
      activity: BackupActivity.saving,
      stage: 'Packing your wardrobe…',
    );

    try {
      final service = _ref.read(backupServiceProvider);
      final built = await service.create(
        onProgress: (done, total) {
          state = BackupState(
            activity: BackupActivity.saving,
            stage: 'Packing photos',
            done: done,
            total: total,
          );
        },
      );

      final at = DateTime.now();
      final fileName = backupFileName(at);
      final handover = await _ref
          .read(backupFilesProvider)
          .save(built.bytes, fileName: fileName);

      if (handover == BackupHandover.cancelled) {
        state = const BackupState(notice: BackupNotice('Nothing was saved.'));
        return;
      }

      final garments = await service.ownedGarments();
      await _ref
          .read(settingsStoreProvider)
          .setLastBackup(at, garments: garments);
      _ref.read(lastBackupAtProvider.notifier).state = at.toUtc();
      _ref.read(garmentsAtLastBackupProvider.notifier).state = garments;

      state = BackupState(
        notice: BackupNotice(
          'Backup saved',
          detail:
              '$fileName\n${built.manifest.counts.summary}\n'
              '${backupSizeLabel(built.bytes.length)}'
              '${built.manifest.counts.missingImages > 0 ? '\n${built.manifest.counts.missingImages} photos could not be read and are not in it.' : ''}',
        ),
      );
    } on Object catch (error) {
      state = BackupState(
        notice: BackupNotice(
          'The backup could not be made',
          detail: _explain(error),
          isError: true,
        ),
      );
    }
  }

  /// Asks for a file and checks it all the way through.
  ///
  /// Null if the person declined or the file was refused; the refusal is in
  /// [BackupState.notice].
  Future<ChosenBackup?> choose() async {
    if (state.busy) return null;
    state = const BackupState(
      activity: BackupActivity.reading,
      stage: 'Waiting for a file…',
    );

    try {
      final picked = await _ref.read(backupFilesProvider).pick();
      if (picked == null) {
        state = const BackupState();
        return null;
      }

      state = const BackupState(
        activity: BackupActivity.reading,
        stage: 'Checking the backup…',
      );
      // A turn of the event loop, so "Checking" is on screen before the work
      // that blocks it.
      await Future<void>.delayed(Duration.zero);
      final opened = BackupReader.open(picked.bytes);

      state = const BackupState();
      return ChosenBackup(opened, picked.name);
    } on Object catch (error) {
      state = BackupState(
        notice: BackupNotice(
          'That file could not be restored',
          detail: _explain(error),
          isError: true,
        ),
      );
      return null;
    }
  }

  Future<Map<RestoreMode, RestorePlan>> previews(OpenedBackup backup) =>
      _ref.read(backupServiceProvider).previews(backup);

  Future<BackupCounts> currentCounts() =>
      _ref.read(backupServiceProvider).currentCounts();

  /// Applies a backup that [choose] returned.
  Future<RestoreOutcome?> restore(OpenedBackup backup, RestoreMode mode) async {
    if (state.busy) return null;
    state = const BackupState(
      activity: BackupActivity.restoring,
      stage: 'Restoring…',
    );

    try {
      final outcome = await _ref
          .read(backupServiceProvider)
          .restore(
            backup,
            mode,
            onProgress: (done, total) {
              state = BackupState(
                activity: BackupActivity.restoring,
                stage: 'Restoring photos',
                done: done,
                total: total,
              );
            },
          );
      _refreshAfterRestore();
      state = BackupState(
        notice: BackupNotice(
          outcome.plan.isEmpty && !outcome.changedAnything
              ? 'Nothing to restore'
              : (mode == RestoreMode.replace ? 'Wardrobe replaced' : 'Merged'),
          detail: describeOutcome(outcome),
        ),
      );
      return outcome;
    } on Object catch (error) {
      state = BackupState(
        notice: BackupNotice(
          'The restore did not finish',
          detail: _explain(error),
          isError: true,
        ),
      );
      return null;
    }
  }

  /// Puts what the screens hold in step with what the restore wrote.
  ///
  /// Records reach the screens by themselves, through the database streams.
  /// Preferences live in state seeded once at startup, so they are re-read.
  void _refreshAfterRestore() {
    final settings = _ref.read(settingsStoreProvider);
    _ref.read(appearanceProvider.notifier).state = settings.appearance;
    _ref.read(splitDryingProvider.notifier).state = settings.splitDrying;
    _ref.read(separateWashingProvider.notifier).state =
        settings.separateWashing;
    _ref.read(washerBrandProvider.notifier).state = settings.washerBrand;
    _ref.read(dryerBrandProvider.notifier).state = settings.dryerBrand;
    _ref.read(customWasherProvider.notifier).state = settings.customWasher;
    _ref.read(customDryerProvider.notifier).state = settings.customDryer;

    // Derived from the history and read once, not watched.
    _ref.invalidate(coWearGraphProvider);
    _ref.invalidate(ownedCountProvider);
    _ref.invalidate(knownBrandsProvider);
    _ref.invalidate(knownCountriesProvider);
  }

  void dismissNotice() {
    if (!state.busy) state = const BackupState();
  }

  String _explain(Object error) => switch (error) {
    BackupException(:final message) => message,
    RestoreFailed(:final message) => message,
    _ =>
      'Something went wrong, and nothing was changed. '
          '(${error.toString().split('\n').first})',
  };
}

final backupControllerProvider =
    StateNotifierProvider<BackupController, BackupState>(BackupController.new);

/// What a restore did, in the numbers a person would check it against.
String describeOutcome(RestoreOutcome outcome) {
  final plan = outcome.plan;
  final lines = <String>[];

  String part(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  void kind(String label, RestoreCounts c) {
    final bits = <String>[
      if (c.added > 0) '${c.added} added',
      if (c.updated > 0) '${c.updated} updated',
      if (c.removed > 0) '${c.removed} removed',
      if (plan.mode == RestoreMode.merge && c.kept > 0)
        '${c.kept} kept as they were',
    ];
    if (bits.isNotEmpty) lines.add('$label: ${bits.join(', ')}');
  }

  kind('Garments', plan.itemCounts);
  kind('History', plan.eventCounts);
  kind('Outfits', plan.outfitCounts);
  kind('Listings', plan.listingCounts);
  if (outcome.imagesWritten > 0) {
    lines.add(part(outcome.imagesWritten, 'photo restored', 'photos restored'));
  }
  if (outcome.imagesMissing > 0) {
    lines.add(
      part(
        outcome.imagesMissing,
        'photo was not in the backup',
        'photos were not in the backup',
      ),
    );
  }
  if (outcome.settingsApplied > 0) {
    lines.add(
      part(outcome.settingsApplied, 'setting restored', 'settings restored'),
    );
  }
  return lines.isEmpty
      ? 'This wardrobe already has everything in that backup.'
      : lines.join('\n');
}
