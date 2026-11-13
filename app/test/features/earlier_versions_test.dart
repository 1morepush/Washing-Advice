/// "Use an earlier version", driven through the real section with a fake
/// switcher that records what it was asked to do instead of navigating.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/data_format.dart';
import 'package:washing_advice/core/version_switch.dart';
import 'package:washing_advice/features/settings/earlier_versions_section.dart';

class _FakeSwitcher implements VersionSwitcher {
  _FakeSwitcher({
    this.versions,
    this.error,
    this.stored,
    this.available = true,
  });

  Future<SiteVersions> Function()? versions;
  Object? error;
  int fetches = 0;
  final switched = <String>[];

  @override
  final bool available;

  DataFormat? stored;

  @override
  DataFormat? get storedFormat => stored;

  @override
  Future<SiteVersions> fetchVersions() async {
    fetches++;
    if (error != null) throw error!;
    return versions!();
  }

  @override
  Future<void> switchTo(String version) async => switched.add(version);
}

SiteVersion _v(String v, String name, {Map<String, int>? format}) =>
    SiteVersion(
      version: v,
      name: name,
      date: DateTime.utc(2026, 11, 13),
      dataFormat: DataFormat(format ?? currentDataFormat.parts),
    );

void main() {
  Future<void> pump(
    WidgetTester tester,
    _FakeSwitcher switcher, {
    Size size = const Size(400, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [versionSwitcherProvider.overrideWithValue(switcher)],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(textScale),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: EarlierVersionsSection(running: '0.38.0'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists the earlier versions and says which is running', (
    tester,
  ) async {
    final switcher = _FakeSwitcher(
      versions: () async => SiteVersions(
        earlier: [
          _v('0.36.0', 'Tumble Dry Forecast'),
          _v('0.37.0', 'Off the Rack'),
        ],
      ),
    );
    await pump(tester, switcher);

    expect(find.text('You are using 0.38.0.'), findsOneWidget);
    // Newest first.
    final first = tester.getTopLeft(find.text('0.37.0 · Off the Rack')).dy;
    final second = tester
        .getTopLeft(find.text('0.36.0 · Tumble Dry Forecast'))
        .dy;
    expect(first, lessThan(second));
    expect(find.text('13 November 2026'), findsNWidgets(2));
    expect(find.widgetWithText(OutlinedButton, 'Use 0.37.0'), findsOneWidget);
  });

  testWidgets('does not offer the running version or a later one', (
    tester,
  ) async {
    final switcher = _FakeSwitcher(
      versions: () async => SiteVersions(
        earlier: [
          _v('0.38.0', 'Clean Cut'),
          _v('0.39.0', 'Later'),
          _v('0.37.0', 'Off the Rack'),
        ],
      ),
    );
    await pump(tester, switcher);

    expect(find.text('0.37.0 · Off the Rack'), findsOneWidget);
    expect(find.textContaining('Clean Cut'), findsNothing);
    expect(find.textContaining('Later'), findsNothing);
  });

  testWidgets(
    'says earlier versions come after the next update when none exist',
    (tester) async {
      await pump(
        tester,
        _FakeSwitcher(versions: () async => const SiteVersions(earlier: [])),
      );
      expect(
        find.text('Earlier versions appear here after the next update.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows a version the data has outgrown, disabled, with why', (
    tester,
  ) async {
    final switcher = _FakeSwitcher(
      stored: DataFormat({
        'wardrobe': currentDataFormat['wardrobe'] + 1,
        'images': currentDataFormat['images'],
      }),
      versions: () async => SiteVersions(
        earlier: [
          _v('0.34.0', 'Fold and Sold', format: {'wardrobe': 3, 'images': 1}),
          _v(
            '0.37.0',
            'Off the Rack',
            format: {
              'wardrobe': currentDataFormat['wardrobe'] + 1,
              'images': currentDataFormat['images'],
            },
          ),
        ],
      ),
    );
    await pump(tester, switcher);

    final blocked = find.widgetWithText(OutlinedButton, 'Use 0.34.0');
    expect(tester.widget<OutlinedButton>(blocked).onPressed, isNull);
    expect(
      find.text(
        'Your wardrobe has been saved in a newer format than 0.34.0 '
        'understands.',
      ),
      findsOneWidget,
    );
    // 0.37.0 reads the stored layout, so it can be chosen.
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Use 0.37.0'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('offline: a quiet message, and Try again asks again', (
    tester,
  ) async {
    final switcher = _FakeSwitcher(error: Exception('offline'));
    await pump(tester, switcher);

    expect(find.textContaining('could not be listed just now'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(switcher.fetches, 1);

    switcher.error = null;
    switcher.versions = () async =>
        SiteVersions(earlier: [_v('0.37.0', 'Off the Rack')]);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(switcher.fetches, 2);
    expect(find.text('0.37.0 · Off the Rack'), findsOneWidget);
  });

  testWidgets('shows progress while it looks', (tester) async {
    final gate = Completer<SiteVersions>();
    final switcher = _FakeSwitcher(versions: () => gate.future);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [versionSwitcherProvider.overrideWithValue(switcher)],
        child: const MaterialApp(
          home: Scaffold(body: EarlierVersionsSection(running: '0.38.0')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Looking for earlier versions…'), findsOneWidget);
    gate.complete(const SiteVersions(earlier: []));
    await tester.pumpAndSettle();
  });

  testWidgets('choosing one explains it, and only pins once confirmed', (
    tester,
  ) async {
    final switcher = _FakeSwitcher(
      versions: () async =>
          SiteVersions(earlier: [_v('0.37.0', 'Off the Rack')]),
    );
    await pump(tester, switcher);

    await tester.tap(find.text('Use 0.37.0'));
    await tester.pumpAndSettle();
    expect(find.text('Use 0.37.0?'), findsOneWidget);
    expect(find.textContaining('Back to latest'), findsOneWidget);
    expect(switcher.switched, isEmpty);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(switcher.switched, isEmpty);

    await tester.tap(find.text('Use 0.37.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Use 0.37.0'));
    await tester.pumpAndSettle();
    expect(switcher.switched, ['0.37.0']);
  });

  testWidgets('draws nothing where there is no site to move between', (
    tester,
  ) async {
    await pump(tester, _FakeSwitcher(available: false));
    expect(find.text('Use an earlier version'), findsNothing);
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('fits 320 px wide at ${scale}x text, with every state', (
      tester,
    ) async {
      final switcher = _FakeSwitcher(
        stored: DataFormat({'wardrobe': currentDataFormat['wardrobe'] + 1}),
        versions: () async => SiteVersions(
          earlier: [
            _v('0.35.0', 'A Rather Long Laundry Joke Of A Name'),
            _v('0.36.0', 'Tumble Dry Forecast', format: {'wardrobe': 1}),
          ],
        ),
      );
      await pump(
        tester,
        switcher,
        size: const Size(320, 700),
        textScale: scale,
      );
      expect(tester.takeException(), isNull);

      // Nothing runs off the right edge.
      for (final finder in [
        find.text('0.35.0 · A Rather Long Laundry Joke Of A Name'),
        find.textContaining('has been saved in a newer format'),
        find.text('Use an earlier version'),
      ]) {
        expect(tester.getBottomRight(finder).dx, lessThanOrEqualTo(320));
      }
    });
  }
}
