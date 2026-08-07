/// Running a sync, and saying what happened.
///
/// The reconciliation itself is entirely the core's — this holds the wiring
/// and the screen-facing state. Sync is never blocking and never mandatory:
/// the app works offline by design, so a failure here is information, not an
/// error state to trap someone in.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../data/api/http_sync_remote.dart';

/// Where a sync has got to.
sealed class SyncState {
  const SyncState();
}

/// Sync is not configured. Not a failure — most installs never turn it on.
final class SyncOff extends SyncState {
  const SyncOff();
}

final class SyncIdle extends SyncState {
  const SyncIdle({this.lastSyncedAt});

  final DateTime? lastSyncedAt;
}

final class SyncRunning extends SyncState {
  const SyncRunning();
}

final class SyncDone extends SyncState {
  const SyncDone(this.report);

  final SyncReport report;
}

final class SyncFailed extends SyncState {
  const SyncFailed(this.message, {required this.isRetryable});

  final String message;
  final bool isRetryable;
}

/// Persists the cursors in the same store as every other setting.
class SettingsSyncCursor implements SyncCursor {
  const SettingsSyncCursor(this._settings);

  final SettingsStore _settings;

  @override
  Future<DateTime?> lastSyncedAt() async => _settings.syncedAt;

  @override
  Future<DateTime?> lastPushedAt() async => _settings.pushedAt;

  @override
  Future<void> record(DateTime at, {DateTime? localAt}) =>
      _settings.setCursors(at: at, localAt: localAt);
}

class SyncController extends StateNotifier<SyncState> {
  SyncController(this._ref) : super(const SyncOff()) {
    final settings = _ref.read(settingsStoreProvider);
    state = _ref.read(syncTokenProvider) == null
        ? const SyncOff()
        : SyncIdle(lastSyncedAt: settings.syncedAt);
  }

  final Ref _ref;

  /// Runs one sync, if it is configured.
  ///
  /// Returns whether it succeeded, for callers that chain — but the state is
  /// the real output, because every screen showing sync wants the reason too.
  Future<bool> run() async {
    final token = _ref.read(syncTokenProvider);
    if (token == null) {
      state = const SyncOff();
      return false;
    }

    state = const SyncRunning();

    final remote = HttpSyncRemote(
      baseUrl: _ref.read(syncBaseUrlProvider),
      token: token,
    );

    try {
      final report = await SyncEngine(
        items: _ref.read(wardrobeRepositoryProvider),
        events: _ref.read(eventLogProvider),
        remote: remote,
        cursor: SettingsSyncCursor(_ref.read(settingsStoreProvider)),
      ).sync();

      if (!report.succeeded) {
        state = SyncFailed(
          report.failure ?? 'Sync did not complete.',
          isRetryable: true,
        );
        return false;
      }

      // Everything downstream of storage is now potentially stale: items were
      // merged, events appended, counters rebuilt. Invalidated in one place
      // rather than left to each screen to notice.
      _ref
        ..invalidate(ownedItemsProvider)
        ..invalidate(ownedCountProvider)
        ..invalidate(coWearGraphProvider)
        ..invalidate(savedOutfitsProvider);

      state = SyncDone(report);
      return true;
    } on SyncFailure catch (failure) {
      state = SyncFailed(failure.message, isRetryable: failure.isRetryable);
      return false;
    } finally {
      remote.close();
    }
  }

  /// Stores a new token and forgets the cursors.
  ///
  /// Cursors belong to an account. Carrying one across a change of credential
  /// would make a brand-new account look as though it had already been synced,
  /// and the first pull would ask for "everything since yesterday" from a
  /// server that has nothing.
  Future<void> setToken(String? token) async {
    final settings = _ref.read(settingsStoreProvider);
    await settings.setSyncToken(token);
    await settings.clearCursors();
    _ref.read(syncTokenProvider.notifier).state = settings.syncToken;

    state = settings.syncToken == null ? const SyncOff() : const SyncIdle();
  }

  /// A fresh credential, long enough to be worth having.
  ///
  /// Generated on the device rather than issued by the server, which is what
  /// makes the server's account model a pure function of the token: there is
  /// no registration step to fail, and no list of users to leak.
  static String generateToken([math.Random? random]) {
    final source = random ?? _secureOrFallback();
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    // 48 characters over a 36-symbol alphabet is about 248 bits, comfortably
    // past the server's 32-character floor and past brute force.
    return List.generate(
      48,
      (_) => alphabet[source.nextInt(alphabet.length)],
    ).join();
  }

  static math.Random _secureOrFallback() {
    try {
      return math.Random.secure();
    } on UnsupportedError {
      // Unlike an item id, this one *is* a secret, so a predictable fallback
      // would be a real weakness rather than a cosmetic one. Refusing is the
      // honest response: the user can paste a token generated elsewhere.
      throw StateError(
        'This device has no secure random source, so it cannot generate a '
        'sync token. Generate one elsewhere and paste it in.',
      );
    }
  }
}

/// Where sync talks to. The same server as scanning, unless one is set.
final syncBaseUrlProvider = Provider<Uri>((ref) {
  final raw = ref.watch(backendUrlProvider).trim();
  final parsed = Uri.parse(raw);
  return parsed.path.endsWith('/')
      ? parsed
      : parsed.replace(path: '${parsed.path}/');
});

final syncControllerProvider = StateNotifierProvider<SyncController, SyncState>(
  SyncController.new,
);
