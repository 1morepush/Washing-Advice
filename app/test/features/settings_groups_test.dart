/// Settings, grouped: the value on every row, the long copy behind a tap.
///
/// The screen was a column of headings and paragraphs, with the server address
/// first. These pin the new shape without losing anything from the old one:
/// every setting is still there, the explanations are still there, and the one
/// thing that is set once and left is where it belongs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/laundry/evening_nudge.dart';
import 'package:washing_advice/features/settings/patch_notes.dart';
import 'package:washing_advice/features/settings/setting_info.dart';
import 'package:washing_advice/main.dart';

import '../support/recording_nudges.dart';

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        wardrobeRepositoryProvider.overrideWithValue(
          InMemoryWardrobeRepository(),
        ),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        nudgesProvider.overrideWithValue(RecordingNudges()),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const WashingAdviceApp(initialLocation: '/settings'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('has six groups, in the order a person reaches for them', (
    tester,
  ) async {
    // Tall enough to lay every group out at once: the list builds lazily.
    await open(tester, size: const Size(400, 6000));

    final groups = <String>[];
    for (final title in [
      'Appearance',
      'Washing and drying',
      'Reminders',
      'Sync',
      'Advanced',
      'About',
    ]) {
      final header = find.descendant(
        of: find.byType(SettingsGroup),
        matching: find.text(title),
      );
      await reveal(tester, header);
      expect(header, findsOneWidget, reason: title);
      groups.add(title);
    }
    expect(
      tester
          .widgetList<SettingsGroup>(find.byType(SettingsGroup))
          .map((g) => g.title),
      groups,
    );
  });

  testWidgets('each row says what it is currently set to', (tester) async {
    await open(tester);

    // Appearance, on the group.
    expect(
      find.descendant(
        of: find.byType(SettingsGroup).first,
        matching: find.text('Match phone'),
      ),
      findsWidgets,
    );

    // The two laundry switches, in words rather than only a thumb position.
    await reveal(tester, find.text('Wash each colour separately'));
    expect(
      find.text('Off — colours that do not conflict share a drum'),
      findsOneWidget,
    );
    expect(find.text('Off — each load dries as one'), findsOneWidget);

    await reveal(tester, find.text('Split a load for drying'));
    await tester.tap(find.text('Split a load for drying'));
    await tester.pumpAndSettle();
    expect(find.text('On — whatever can be tumble dried is'), findsOneWidget);

    // The reminder.
    await reveal(tester, find.text('Ask what I wore, every evening'));
    expect(find.text('Off'), findsOneWidget);

    // The server, on the folded row.
    await reveal(tester, find.text('Advanced'));
    expect(find.text(defaultBackendUrl), findsOneWidget);
  });

  testWidgets('long explanations are behind a tap, and still there', (
    tester,
  ) async {
    await open(tester);
    await reveal(tester, find.text('Wash each colour separately'));

    expect(find.textContaining('only ever separate more'), findsNothing);

    await reveal(tester, find.byTooltip('About Wash each colour separately'));
    await tester.tap(find.byTooltip('About Wash each colour separately'));
    await tester.pumpAndSettle();

    expect(find.textContaining('only ever separate more'), findsOneWidget);
    expect(find.textContaining('no argument about it'), findsOneWidget);
  });

  testWidgets('the server address is under Advanced, and not first', (
    tester,
  ) async {
    await open(tester, size: const Size(400, 6000));

    // Not the first thing on the screen any more.
    expect(find.text('Scan backend'), findsNothing);
    expect(find.widgetWithText(TextField, 'Server address'), findsNothing);

    await reveal(tester, find.text('Server address'));
    final advanced = tester.getTopLeft(
      find.descendant(
        of: find.byType(SettingsGroup),
        matching: find.text('Advanced'),
      ),
    );
    expect(
      tester.getTopLeft(find.text('Server address')).dy,
      greaterThan(advanced.dy),
    );
    final sync = tester.getTopLeft(
      find.descendant(
        of: find.byType(SettingsGroup),
        matching: find.text('Sync'),
      ),
    );
    expect(advanced.dy, greaterThan(sync.dy));

    // Opening the row reaches the field and the button, as before.
    await tester.tap(find.text('Server address'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
    expect(find.text('Save and test'), findsOneWidget);
  });

  testWidgets('every setting the old screen had is reachable', (tester) async {
    await open(tester);

    for (final text in [
      'Your machines',
      'Wash each colour separately',
      'Split a load for drying',
      'Ask what I wore, every evening',
      'Sync token',
      'Server address',
      'What\'s new',
    ]) {
      // A field's label is drawn as text inside the field, not as a Text.
      final finder = text == 'Sync token'
          ? find.widgetWithText(TextField, text)
          : find.text(text);
      await reveal(tester, finder);
      expect(finder, findsOneWidget, reason: text);
    }
    await reveal(
      tester,
      find.text(
        '${patchNotes.first.version} · '
        '${patchNotes.first.name}',
      ),
    );
  });

  for (final (width, scale) in [(320.0, 1.0), (320.0, 2.0)]) {
    testWidgets('fits ${width.toInt()} dp wide at ${scale}x text', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, size: Size(width, 640));

      // Scrolled to the end, so every group is laid out at least once.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -20000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
