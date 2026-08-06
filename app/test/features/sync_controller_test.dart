/// The app's sync wiring.
///
/// The reconciliation is the core's and is tested there, against a fake remote
/// and against the real server. What is under test here is what the app adds:
/// cursor persistence, the state a screen renders, and the credential handling
/// that is easy to get subtly wrong.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/features/sync/sync_controller.dart';

void main() {
  late SettingsStore settings;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());

    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        wardrobeRepositoryProvider.overrideWithValue(
          InMemoryWardrobeRepository(),
        ),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
      ],
    );
  });

  tearDown(() => container.dispose());

  SyncController controller() =>
      container.read(syncControllerProvider.notifier);

  group('setting up', () {
    test('an unconfigured app is off, which is not a failure', () {
      // Most installs never turn sync on. Rendering that as an error state
      // would be telling people something is broken when nothing is.
      expect(container.read(syncControllerProvider), isA<SyncOff>());
    });

    test('saving a token turns it on', () async {
      await controller().setToken('a' * 48);

      expect(container.read(syncControllerProvider), isA<SyncIdle>());
      expect(settings.syncToken, 'a' * 48);
    });

    test('whitespace around a pasted token is trimmed', () async {
      // Pasting from a password manager or an email routinely brings a newline
      // with it, and a token that differs by one character is a different
      // account with an empty wardrobe.
      await controller().setToken('  ${'b' * 48}\n');

      expect(settings.syncToken, 'b' * 48);
    });

    test('an empty token clears it rather than storing nothing', () async {
      await controller().setToken('c' * 48);
      await controller().setToken('   ');

      expect(settings.syncToken, isNull);
      expect(container.read(syncControllerProvider), isA<SyncOff>());
    });

    test('changing the token forgets the cursors', () async {
      // Cursors belong to an account. Carried across a change of credential,
      // the first pull would ask a brand-new account for "everything since
      // yesterday" and receive nothing, leaving the device looking synced and
      // empty.
      await settings.setCursors(
        at: DateTime.utc(2026, 8, 1),
        localAt: DateTime.utc(2026, 8, 1),
      );

      await controller().setToken('d' * 48);

      expect(settings.syncedAt, isNull);
      expect(settings.pushedAt, isNull);
    });
  });

  group('the generated token', () {
    test('is long enough for the server to accept', () {
      // The server enforces a 32-character floor. A client that generated
      // something shorter would fail on every request with a message about the
      // token, which reads as "your token is wrong" rather than "this app is".
      expect(SyncController.generateToken().length, greaterThanOrEqualTo(32));
    });

    test('is not the same twice', () {
      final tokens = {
        for (var i = 0; i < 50; i++) SyncController.generateToken(),
      };
      expect(tokens, hasLength(50));
    });

    test('uses only characters that survive being pasted', () {
      // Typed out, read aloud, and copied between devices. Anything that a
      // mail client might reflow or a shell might interpret is a support
      // problem waiting to happen.
      expect(SyncController.generateToken(), matches(RegExp(r'^[a-z0-9]+$')));
    });

    test('draws from the source it is given', () {
      // Pinning that the alphabet is applied, so a future change to it cannot
      // silently shrink the space.
      final fixed = SyncController.generateToken(_ZeroRandom());
      expect(fixed, matches(RegExp(r'^a+$')));
    });
  });

  group('cursors', () {
    test('round-trip through storage as UTC', () async {
      final cursor = SettingsSyncCursor(settings);
      await cursor.record(
        DateTime.utc(2026, 8, 5, 12),
        localAt: DateTime.utc(2026, 8, 5, 11, 55),
      );

      expect(await cursor.lastSyncedAt(), DateTime.utc(2026, 8, 5, 12));
      expect(await cursor.lastPushedAt(), DateTime.utc(2026, 8, 5, 11, 55));
    });

    test('a local time is stored as UTC, not as wall clock', () async {
      // The two cursors are compared against timestamps that are always UTC.
      // Storing a local one would reintroduce a skew of exactly the offset.
      final cursor = SettingsSyncCursor(settings);
      final local = DateTime(2026, 8, 5, 12);
      await cursor.record(local, localAt: local);

      expect((await cursor.lastSyncedAt())!.isUtc, isTrue);
      expect(await cursor.lastSyncedAt(), local.toUtc());
    });

    test('the remote cursor can advance without the local one', () async {
      // Which is exactly what a pull-only run does.
      final cursor = SettingsSyncCursor(settings);
      await cursor.record(
        DateTime.utc(2026, 8, 1),
        localAt: DateTime.utc(2026, 8, 1),
      );
      await cursor.record(DateTime.utc(2026, 8, 2));

      expect(await cursor.lastSyncedAt(), DateTime.utc(2026, 8, 2));
      expect(await cursor.lastPushedAt(), DateTime.utc(2026, 8, 1));
    });

    test('survive a new store over the same preferences', () async {
      await SettingsSyncCursor(
        settings,
      ).record(DateTime.utc(2026, 8, 5), localAt: DateTime.utc(2026, 8, 5));

      final reopened = SettingsStore(await SharedPreferences.getInstance());
      expect(reopened.syncedAt, DateTime.utc(2026, 8, 5));
    });
  });

  test('running with no token does nothing rather than throwing', () async {
    expect(await controller().run(), isFalse);
    expect(container.read(syncControllerProvider), isA<SyncOff>());
  });

  test('an unreachable server is reported, not thrown', () async {
    // Offline-first: a dead network is the expected case, and it must not
    // become an exception every caller has to wrap.
    await controller().setToken('e' * 48);
    container.read(backendUrlProvider.notifier).state =
        'http://127.0.0.1:9/'; // Discard port: refuses immediately.

    expect(await controller().run(), isFalse);
    expect(container.read(syncControllerProvider), isA<SyncFailed>());
  });
}

/// Always returns the first symbol, so the alphabet is observable.
class _ZeroRandom implements math.Random {
  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
