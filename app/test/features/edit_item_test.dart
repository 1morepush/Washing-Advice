/// Editing an item.
///
/// The behaviour under test is not "the form saves" — it is that a correction
/// is recorded as the user's and that the care follows the correction. A form
/// that let someone change 100% wool to 100% acrylic while still recommending
/// a wool cycle would be worse than no form at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/router.dart';

void main() {
  const id = ItemId('jumper');
  late InMemoryWardrobeRepository repository;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    await repository.save(_woolJumper());
  });

  Future<void> pump(WidgetTester tester) async {
    // The form is taller than the 800x600 default, and a lazy ListView never
    // builds what is off-screen — so the fields below the fold would not exist
    // to tap. A phone-shaped surface is also closer to what ships.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [wardrobeRepositoryProvider.overrideWithValue(repository)],
        // The real router, not a bare `home:`. The screen navigates after
        // saving, and a test that stubbed that out would pass while the
        // shipping app threw.
        child: MaterialApp.router(
          routerConfig: buildRouter(initialLocation: '/item/${id.value}/edit'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows where each value came from', (tester) async {
    await pump(tester);

    // So the user can see what they are overruling. Correcting a care-label
    // reading deserves more hesitation than correcting a photo's guess.
    expect(find.textContaining('from a photo'), findsWidgets);
  });

  testWidgets('a renamed item keeps everything else', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField).first, 'Grey jumper');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await repository.byId(id))!;
    expect(saved.name, 'Grey jumper');
    expect(saved.composition.value.percentOf(Fiber.wool), 100);
  });

  testWidgets('marking a favourite records it', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await repository.byId(id))!.isFavorite, isTrue);
  });

  testWidgets('the care preview reflects the edit before it is saved', (
    tester,
  ) async {
    await pump(tester);

    // The wool rule forbids tumble drying, so that is what the form should say
    // on arrival — computed from the item, not hard-coded into the screen.
    expect(find.textContaining('Do not tumble dry'), findsOneWidget);
  });

  testWidgets('correcting the fabric re-derives the care', (tester) async {
    await pump(tester);

    // Wool → acrylic. The wool rule forbids tumble drying; acrylic does not,
    // and a form that saved the new fabric while keeping the old advice would
    // be worse than one that never allowed the correction.
    await tester.tap(find.text('Add fiber'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acrylic').last);
    await tester.pumpAndSettle();

    // Wool to nothing, acrylic to everything. Sliders are ordered by share,
    // so wool is still first until it drops.
    await tester.drag(find.byType(Slider).first, const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider).first, const Offset(500, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await repository.byId(id))!;

    // The correction is recorded as the user's, which is what makes it outrank
    // the camera on every future resolution.
    expect(saved.composition.source, Provenance.userEdited);
    expect(saved.composition.value.percentOf(Fiber.acrylic), greaterThan(0));
    expect(saved.composition.value.percentOf(Fiber.wool), 0);

    // And the advice moved with it. Not tumble drying — the rule table can
    // only ever *tighten*, so nothing but a care label can permit that, and
    // both fibres forbid it. What changes is the handling: wool asks to be
    // reshaped while damp on a very mild cycle because it felts, and acrylic
    // asks to be washed inside out because it pills.
    expect(
      saved.effectiveCare.warnings,
      isNot(contains(CareWarning.reshapeWhileDamp)),
    );
    expect(saved.fabricClass, FabricClass.normal);
  });

  testWidgets('a stored care label survives an edit', (tester) async {
    // The reason `CareResolver.forItem` exists. Re-resolving after a rename
    // must not quietly drop the manufacturer's instruction.
    await repository.save(
      (await repository.byId(id))!.copyWith(
        careLabel: Confident(
          const CareConstraint(tumbleDryAllowed: true, maxTempC: 40),
          confidence: 0.93,
          source: Provenance.tagScan,
        ),
      ),
    );

    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'Renamed');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = (await repository.byId(id))!;
    expect(saved.name, 'Renamed');
    expect(saved.careLabel, isNotNull);
    expect(saved.care.source, Provenance.tagScan);
    expect(saved.effectiveCare.dry.tumbleDryAllowed, isTrue);
  });
  group('setting the color by hand', () {
    /// The value is not decoration: it decides which load the garment goes in
    /// and whether the app warns that its dye may run. A camera under warm
    /// indoor light reads navy as black often enough that this needs an
    /// override, and correcting it has to reach the laundry rules.
    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('a swatch replaces what the camera guessed', (tester) async {
      await pump(tester);

      await tester.tap(find.byTooltip('Remove this color'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'Navy'));
      await tester.pumpAndSettle();
      await save(tester);

      final saved = (await repository.byId(id))!;
      expect(saved.colors.value.dominant!.name, 'Navy');
      expect(saved.colors.source, Provenance.userEdited);
    });

    testWidgets('correcting it changes the load it sorts into', (tester) async {
      // Charcoal and white are on opposite sides of the whites/darks line, so
      // a correction that did not reach `colorClass` would be one the app
      // accepted and then ignored.
      await pump(tester);
      expect((await repository.byId(id))!.colorClass, ColorClass.darks);

      await tester.tap(find.byTooltip('Remove this color'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'White'));
      await tester.pumpAndSettle();
      await save(tester);

      expect((await repository.byId(id))!.colorClass, ColorClass.whites);
    });

    testWidgets('the first color named is the one it mostly is', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.widgetWithText(ActionChip, 'Red'));
      await tester.pumpAndSettle();
      await save(tester);

      final saved = (await repository.byId(id))!;
      expect(saved.colors.value.colors.map((c) => c.name), ['Charcoal', 'Red']);
      expect(saved.colors.value.dominant!.name, 'Charcoal');
    });

    testWidgets('a hex code is accepted for anything not offered', (
      tester,
    ) async {
      // What someone copying a colour off a shop listing actually has.
      await pump(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Or a hex code'),
        '#123456',
      );
      await tester.tap(find.byTooltip('Add this color'));
      await tester.pumpAndSettle();
      await save(tester);

      expect(
        (await repository.byId(id))!.colors.value.colors.last.hex,
        '#123456',
      );
    });

    testWidgets('a hex code that is not one says so', (tester) async {
      await pump(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Or a hex code'),
        'navy',
      );
      await tester.tap(find.byTooltip('Add this color'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Six hex digits'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Charcoal'), findsOneWidget);
    });

    testWidgets('leaving the color alone leaves its provenance alone', (
      tester,
    ) async {
      // Re-stamping an untouched field as the user's would make the app claim
      // they confirmed something they never looked at — and that claim
      // outranks every future scan.
      await pump(tester);
      await save(tester);

      expect(
        (await repository.byId(id))!.colors.source,
        Provenance.aiInference,
      );
    });
  });
}

WardrobeItem _woolJumper() {
  final now = DateTime.utc(2026, 8, 5);
  return WardrobeItem(
    id: const ItemId('jumper'),
    name: 'Charcoal merino jumper',
    type: Confident(
      ItemType.sweater,
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    composition: Confident(
      FabricComposition(const {Fiber.wool: 100}),
      confidence: 0.6,
      source: Provenance.aiInference,
    ),
    colors: Confident(
      ColorPalette([ItemColor.fromHex('#3C3F44', name: 'Charcoal')]),
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    care: const CareProfile.unknown(),
    addedAt: now,
    updatedAt: now,
  );
}
