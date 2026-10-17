/// The keyboard and the bottom bar.
///
/// Screens inside the shell lay themselves out around the keyboard. If the
/// shell does not take the keyboard's inset off the body, they shrink from their
/// own bottom edge, which is a bar's height above the real one, and leave a gap
/// between the composer and the keys. The bar must also not float on top of the
/// keyboard. These put a keyboard on screen and measure.
///
/// Ask is the composer, and it is no longer inside the shell: it is pushed over
/// the bar from More. It has no bar to float and no shell to take the inset off
/// the body, so its own page has to do both jobs, and the first test says it
/// still does. The tests about the bar itself run on a place that is still on
/// it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/main.dart';

import '../support/fixtures.dart';

const _screen = Size(400, 800);
const _keyboard = 300.0;

void main() {
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final repository = InMemoryWardrobeRepository();
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'Cream tee'),
      confidentItem(id: 'jeans', name: 'Navy jeans', type: ItemType.jeans),
    ]);
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> open(WidgetTester tester, String location) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: WashingAdviceApp(initialLocation: location),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showKeyboard(WidgetTester tester, [double height = _keyboard]) {
    tester.view.viewInsets = FakeViewPadding(bottom: height);
    addTearDown(tester.view.resetViewInsets);
    return tester.pumpAndSettle();
  }

  const top = 800 - _keyboard;

  testWidgets('the Ask composer sits on the keyboard, with no gap', (
    tester,
  ) async {
    await open(tester, '/ask');
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await showKeyboard(tester);

    final bottom = tester.getRect(find.byType(TextField)).bottom;
    expect(bottom, lessThanOrEqualTo(top));
    // The composer's own padding, and nothing else, between it and the keys.
    expect(top - bottom, lessThanOrEqualTo(16));
  });

  testWidgets('and Ask, being over the bar, has none to leave on the keys', (
    tester,
  ) async {
    await open(tester, '/ask');
    expect(find.byType(NavigationBar), findsNothing);

    await showKeyboard(tester);
    expect(find.byType(NavigationBar), findsNothing);

    // And it is still the whole page: the composer, with the keyboard gone,
    // is back at the bottom of the screen and not a bar's height above it.
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(_screen.height),
    );
    expect(
      _screen.height - tester.getRect(find.byType(TextField)).bottom,
      lessThanOrEqualTo(16),
    );
  });

  testWidgets('the bar is not left floating above the keyboard', (
    tester,
  ) async {
    await open(tester, '/outfits');
    expect(find.byType(NavigationBar), findsOneWidget);

    await showKeyboard(tester);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('the bar is back when the keyboard goes', (tester) async {
    await open(tester, '/outfits');
    await showKeyboard(tester);
    expect(find.byType(NavigationBar), findsNothing);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    // And sits at the bottom of the screen again.
    expect(tester.getRect(find.byType(NavigationBar)).bottom, _screen.height);
  });

  testWidgets('Outfits keeps its season row on the keyboard too', (
    tester,
  ) async {
    await open(tester, '/outfits');
    await showKeyboard(tester);

    expect(find.byType(NavigationBar), findsNothing);
    final bottom = tester.getRect(find.text('With a layer')).bottom;
    expect(bottom, lessThanOrEqualTo(top));
    expect(top - bottom, lessThanOrEqualTo(40));
  });

  testWidgets('and the stylist note field is reachable above the keys', (
    tester,
  ) async {
    await open(tester, '/outfits');
    final note = find.widgetWithText(TextField, 'Anything to add? (optional)');
    await tester.scrollUntilVisible(
      note,
      200,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical)
          .first,
    );
    await tester.tap(note);
    await showKeyboard(tester);
    await tester.ensureVisible(note);
    await tester.pumpAndSettle();

    expect(tester.getRect(note).bottom, lessThanOrEqualTo(top));
  });
}
