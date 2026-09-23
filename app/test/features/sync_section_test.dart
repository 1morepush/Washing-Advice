/// What the sync section says while it waits.
///
/// A free-tier server that has gone to sleep takes the better part of a
/// minute to answer. "Syncing…" alone for that long reads as a hang, and the
/// next thing somebody does is change a setting that was never wrong.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/features/sync/sync_controller.dart';
import 'package:washing_advice/features/sync/sync_section.dart';

void main() {
  testWidgets('a slow sync explains itself after a few seconds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'syncToken': 'a' * 48});
    final settings = SettingsStore(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(settings),
          syncControllerProvider.overrideWith(_Stuck.new),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: SyncSection())),
        ),
      ),
    );

    expect(find.text('Syncing…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 9));

    expect(find.textContaining('up to a minute to wake'), findsOneWidget);
  });
}

/// A sync that never finishes.
class _Stuck extends SyncController {
  _Stuck(super.ref) {
    state = const SyncRunning();
  }
}
