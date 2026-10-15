/// Choosing how the app looks, from the screen to the pixel.
///
/// The theme's own values are checked in `test/core/theme_test.dart`. What this
/// covers is the part a theme test cannot see: that a stored choice is what the
/// app starts in, that tapping one in Settings changes the whole app at once
/// and is kept, and that a phone in dark mode does not get a say once somebody
/// has picked Light.
///
/// The last of those is why the colours here are read off the frame and not off
/// the theme. A theme that says black and a screen that shows grey are
/// different bugs, and only one of them can be found by asking the theme.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/settings/setting_info.dart';
import 'package:washing_advice/main.dart';

final _light = AppTheme.light().colorScheme.surface;
final _dark = AppTheme.dark().colorScheme.surface;
final _black = AppTheme.amoled().colorScheme.surface;

final _screen = GlobalKey();

void main() {
  late ProviderContainer container;

  /// The app as `main()` builds it, on a phone-sized surface.
  ///
  /// [store] lets a test hand the app a settings store of its own, over the
  /// same preferences.
  Future<void> pumpApp(
    WidgetTester tester, {
    Map<String, Object> stored = const {},
    String initialLocation = '/',
    SettingsStore Function(SharedPreferences)? store,
  }) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          store == null ? SettingsStore(prefs) : store(prefs),
        ),
        wardrobeRepositoryProvider.overrideWithValue(
          InMemoryWardrobeRepository(),
        ),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _screen,
        child: UncontrolledProviderScope(
          container: container,
          child: WashingAdviceApp(initialLocation: initialLocation),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The colour actually painted at [at], read back from the frame.
  Future<Color> painted(WidgetTester tester, Offset at) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_screen),
    );
    // Encoding a frame is real engine work, which the test binding's fake
    // clock will wait on forever.
    final (:bytes, :width) = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData())!;
      final width = image.width;
      image.dispose();
      return (bytes: bytes, width: width);
    }))!;

    final offset = (at.dy.round() * width + at.dx.round()) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  // Clear of every widget on the settings screen: the gutter to the left of
  // the list is the scaffold's own colour, and the middle of the bar is its
  // background, a long way from the title.
  Future<Color> ground(WidgetTester tester) =>
      painted(tester, const Offset(4, 900));
  Future<Color> bar(WidgetTester tester) =>
      painted(tester, const Offset(600, 30));

  /// A look's own row. The group's header also names the current look, so a
  /// bare `find.text('Dark')` can be two things.
  Finder look(String label) =>
      find.widgetWithText(RadioListTile<Appearance>, label);

  Future<void> choose(WidgetTester tester, String label) async {
    // Centred, not merely on screen: at the very top the row would sit under
    // the app bar and the tap would land on that instead.
    await Scrollable.ensureVisible(tester.element(look(label)), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(look(label));
    await tester.pumpAndSettle();
  }

  group('what is stored decides what the app starts in', () {
    // The theme and the dark theme MaterialApp is given, and the mode it is
    // told to follow. Written out per case so that none of it is read back
    // from the mapping under test.
    for (final (stored, mode, darkSurface) in [
      (null, ThemeMode.system, _dark),
      ('system', ThemeMode.system, _dark),
      ('light', ThemeMode.light, _dark),
      ('dark', ThemeMode.dark, _dark),
      ('amoled', ThemeMode.dark, _black),
      // A look from some other version of the app. Starting as it always did
      // is the whole of the requirement.
      ('sepia', ThemeMode.system, _dark),
    ]) {
      testWidgets('${stored ?? 'nothing at all'}: $mode', (tester) async {
        await pumpApp(tester, stored: {'appearance': ?stored});

        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.themeMode, mode);
        expect(app.theme!.colorScheme.surface, _light);
        expect(app.darkTheme!.colorScheme.surface, darkSurface);
      });
    }

    testWidgets('and a stored AMOLED is on screen, not just in the theme', (
      tester,
    ) async {
      await pumpApp(
        tester,
        stored: {'appearance': 'amoled'},
        initialLocation: '/settings',
      );

      expect((await ground(tester)).toARGB32(), _black.toARGB32());
    });
  });

  testWidgets(
    'the screen for settings that could not be read follows the phone',
    (tester) async {
      // Shown precisely when there is no stored choice to honour, and built with
      // no providers at all: one that went looking for the appearance would have
      // nothing to ask and would fail on the one screen that must not.
      await tester.pumpWidget(StartupFailureApp(error: StateError('refused')));

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);
      expect(app.darkTheme!.colorScheme.surface, _dark);
    },
  );

  group('choosing in Settings', () {
    testWidgets('changes the whole app at once, and keeps the choice', (
      tester,
    ) async {
      // A phone in dark mode, so Match phone is Dark to begin with and Light is
      // a choice the phone would never make for itself.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester, initialLocation: '/settings');
      final prefs = await SharedPreferences.getInstance();

      expect((await ground(tester)).toARGB32(), _dark.toARGB32());

      await choose(tester, 'AMOLED');
      expect((await ground(tester)).toARGB32(), _black.toARGB32());
      // Choosing scrolled the settings list up under the bar, which in the
      // other two looks tints it. Here it must still be the black it was.
      expect((await bar(tester)).toARGB32(), _black.toARGB32());
      expect(prefs.getString('appearance'), 'amoled');

      await choose(tester, 'Light');
      expect(
        (await ground(tester)).toARGB32(),
        _light.toARGB32(),
        reason: 'Light is light even on a phone that is in dark mode',
      );
      expect(prefs.getString('appearance'), 'light');

      await choose(tester, 'Dark');
      expect((await ground(tester)).toARGB32(), _dark.toARGB32());
      expect(prefs.getString('appearance'), 'dark');

      // And back to following the phone, which then has its say again.
      await choose(tester, 'Match phone');
      expect((await ground(tester)).toARGB32(), _dark.toARGB32());
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();
      expect((await ground(tester)).toARGB32(), _light.toARGB32());
      expect(prefs.getString('appearance'), 'system');
    });

    testWidgets('stays on the settings screen while it does', (tester) async {
      // The app root rebuilds when the choice changes. A router rebuilt with
      // it would send somebody back to the wardrobe the moment they tapped.
      await pumpApp(tester, initialLocation: '/settings');

      await choose(tester, 'AMOLED');

      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('waits for the save before it shows the choice', (
      tester,
    ) async {
      // Saved first, shown second. The other way round, a save that failed
      // would leave a screen saying one thing and the next launch doing
      // another — and the screen is the one that gets believed.
      late _SlowStore slow;
      await pumpApp(
        tester,
        initialLocation: '/settings',
        store: (prefs) => slow = _SlowStore(prefs),
      );
      final before = await ground(tester);

      await choose(tester, 'AMOLED');
      await tester.pumpAndSettle();

      expect(slow.asked, Appearance.amoled);
      expect(container.read(appearanceProvider), Appearance.system);
      expect(await ground(tester), before);

      slow.finish();
      await tester.pumpAndSettle();

      expect(container.read(appearanceProvider), Appearance.amoled);
      expect((await ground(tester)).toARGB32(), _black.toARGB32());
    });
  });

  group('the section', () {
    testWidgets('offers the four looks, with Match phone chosen to begin', (
      tester,
    ) async {
      await pumpApp(tester, initialLocation: '/settings');
      await tester.ensureVisible(look('AMOLED'));

      expect(find.text('Appearance'), findsOneWidget);
      for (final label in ['Match phone', 'Light', 'Dark', 'AMOLED']) {
        expect(look(label), findsOneWidget, reason: label);
      }
      // The group says what it is currently set to, beside its name.
      expect(
        find.descendant(
          of: find.byType(SettingsGroup).first,
          matching: find.text('Match phone'),
        ),
        findsNWidgets(2),
      );
      expect(find.text('Light or dark, as your phone is set'), findsOneWidget);
      expect(
        find.text('True black. Easier on OLED screens and in a dark room'),
        findsOneWidget,
      );
      // The longer explanation is behind the info button, not on the page.
      expect(
        find.textContaining('nothing changes until you choose'),
        findsNothing,
      );
      await tester.tap(find.byTooltip('About Appearance'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Match phone is the default, so nothing changes'),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<Appearance>>(find.byType(RadioGroup<Appearance>))
            .groupValue,
        Appearance.system,
      );
    });

    testWidgets('shows the stored choice as the chosen one', (tester) async {
      await pumpApp(
        tester,
        stored: {'appearance': 'amoled'},
        initialLocation: '/settings',
      );
      await tester.ensureVisible(look('AMOLED'));

      expect(
        tester
            .widget<RadioGroup<Appearance>>(find.byType(RadioGroup<Appearance>))
            .groupValue,
        Appearance.amoled,
      );
    });

    testWidgets('comes first, ahead of the laundry and the reminder', (
      tester,
    ) async {
      await pumpApp(tester, initialLocation: '/settings');
      await tester.ensureVisible(find.text('Reminders'));

      double top(String text) => tester.getTopLeft(find.text(text)).dy;

      expect(top('Appearance'), lessThan(top('Washing and drying')));
      expect(top('Washing and drying'), lessThan(top('Reminders')));
    });
  });
}

/// A store whose write of the appearance takes as long as the test says.
class _SlowStore extends SettingsStore {
  _SlowStore(super.prefs);

  final _written = Completer<void>();

  /// What it was last asked to keep.
  Appearance? asked;

  void finish() => _written.complete();

  @override
  Future<void> setAppearance(Appearance value) {
    asked = value;
    return _written.future;
  }
}
