/// Whether the app ever tells anyone what the label said about dry cleaning.
///
/// It did not. The value was read off the label, parsed, resolved, persisted
/// and even announced by the review screen's diff — "Dry cleaning: allowed →
/// not allowed" — and then neither care summary mentioned it again, because
/// both render a fixed list of four rows written before `ProfessionalCare`
/// existed. A user who scanned a label whose only news was "do not dry clean"
/// saw a screen that appeared to have ignored it.
///
/// The silence case matters as much as the prohibition. Most labels say
/// nothing about dry cleaning, and a row reading "Dry cleaning: allowed" would
/// be inventing a manufacturer's permission out of an absence.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/scan/care_tag_controller.dart';
import 'package:washing_advice/features/scan/care_tag_screen.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';

import '../support/fixtures.dart';

void main() {
  _missingFacts();
  const itemId = ItemId('tee');

  late InMemoryWardrobeRepository repository;
  late ProviderContainer container;
  late _LabelGateway gateway;

  /// An item whose scanned label states [constraint].
  Future<void> withLabel(CareConstraint constraint) async {
    final base = confidentItem(id: itemId.value, name: 'White cotton tee');
    final labelled = base.copyWith(
      careLabel: Confident(
        constraint,
        confidence: 0.95,
        source: Provenance.tagScan,
      ),
    );
    await repository.save(
      labelled.copyWith(care: const CareResolver().forItem(labelled).profile),
    );
  }

  setUp(() {
    repository = InMemoryWardrobeRepository();
    gateway = _LabelGateway();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        aiGatewayProvider.overrideWithValue(gateway),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            const ScanImage(bytes: [1, 2, 3]),
          ]),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester, Widget screen) async {
    // Wide, because this file is about what the screens say rather than how
    // they fit. `flutter_test`'s default font draws every glyph as a square of
    // the font size, so a phone-width surface overflows on text that fits
    // perfectly well in a browser — `layout_fit_test.dart` is where fit is
    // measured, against the real font.
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the item detail screen', () {
    testWidgets('says so when the label forbids dry cleaning', (tester) async {
      await withLabel(const CareConstraint(doNotDryClean: true));

      await pump(tester, const ItemDetailScreen(id: itemId));

      expect(find.text('Dry cleaning'), findsOneWidget);
      expect(find.text('Do not dry clean'), findsOneWidget);
    });

    testWidgets('names the solvent when the label states one', (tester) async {
      await withLabel(
        const CareConstraint(solvent: CleaningSolvent.hydrocarbon),
      );

      await pump(tester, const ItemDetailScreen(id: itemId));

      expect(
        find.text('Professional dry clean (hydrocarbon solvent only)'),
        findsOneWidget,
      );
    });

    testWidgets('stays silent when the label was', (tester) async {
      // The common case, and the one where an invented "allowed" would be a
      // manufacturer's permission nobody gave.
      await withLabel(const CareConstraint(maxTempC: 40));

      await pump(tester, const ItemDetailScreen(id: itemId));

      expect(find.text('Dry cleaning'), findsNothing);
    });
  });

  group('a label that prints a word instead of a number', () {
    testWidgets('the wording is shown, not just the figure', (tester) async {
      // American labels say "machine wash cold" and never give a number. The
      // app answered "Machine wash, up to 30°C" — correct, and unrecognisable
      // to someone holding the garment. Both now.
      await withLabel(
        const CareConstraint(
          method: WashMethod.machine,
          maxTempC: 30,
          washTemperature: WashTemperature.cold,
        ),
      );

      await pump(tester, const ItemDetailScreen(id: itemId));

      expect(find.textContaining('Machine wash cold'), findsOneWidget);
      expect(find.textContaining('up to 30°C'), findsOneWidget);
    });

    testWidgets('a label giving only a number says only the number', (
      tester,
    ) async {
      // European labels print the figure in the tub. Inventing "cold" for it
      // would be putting a word in the manufacturer's mouth.
      await withLabel(
        const CareConstraint(method: WashMethod.machine, maxTempC: 30),
      );

      await pump(tester, const ItemDetailScreen(id: itemId));

      expect(find.textContaining('up to 30°C'), findsOneWidget);
      expect(find.textContaining('Machine wash cold'), findsNothing);
      expect(find.textContaining('Machine wash warm'), findsNothing);
    });
  });

  group('what the garment is made of', () {
    // The fibre content is printed on most labels, is taken when it is there,
    // and outranks whatever was guessed from a photograph — and the review
    // screen never mentioned it. Somebody scanning a tag could not tell
    // whether the composition had been captured, corrected, or never read.

    testWidgets('a fabric read off the label is shown as read', (tester) async {
      await withLabel(const CareConstraint(maxTempC: 30));
      gateway.reading = CareTagScanResult(
        instructions: const CareConstraint(maxTempC: 40),
        confidence: 0.95,
        composition: Confident(
          FabricComposition(const {Fiber.wool: 80, Fiber.nylon: 20}),
          confidence: 0.95,
          source: Provenance.tagScan,
        ),
      );

      await pump(tester, const CareTagScreen(id: itemId));
      final controller = container.read(
        careTagControllerProvider(itemId).notifier,
      );
      await controller.capture();
      await controller.readCollected();
      await tester.pumpAndSettle();

      expect(find.text('What it is made of'), findsOneWidget);
      expect(find.textContaining('80% Wool'), findsOneWidget);
      expect(find.textContaining('Read from this label'), findsOneWidget);
    });

    testWidgets('a fabric the label did not win is not claimed as read', (
      tester,
    ) async {
      // The fixture's own composition is already a tag scan, so `resolve`
      // keeps it. Showing the label's figure under a flat "read from this
      // label" would claim a provenance the saved value does not have — the
      // screen says which one is actually being kept instead.
      await withLabel(const CareConstraint(maxTempC: 30));
      gateway.reading = CareTagScanResult(
        instructions: const CareConstraint(maxTempC: 40),
        confidence: 0.95,
        composition: Confident(
          FabricComposition(const {Fiber.wool: 80, Fiber.nylon: 20}),
          confidence: 0.95,
          source: Provenance.tagScan,
        ),
      );

      await pump(tester, const CareTagScreen(id: itemId));
      final controller = container.read(
        careTagControllerProvider(itemId).notifier,
      );
      await controller.capture();
      await controller.readCollected();
      await tester.pumpAndSettle();

      expect(find.textContaining('has been kept'), findsOneWidget);
    });

    testWidgets('a label silent about fabric says so', (tester) async {
      // The case that earns the section. Saying nothing would look identical
      // whether the label was silent or the reading missed it, and those want
      // different responses — one is the label's fault, one is worth another
      // photograph.
      await withLabel(const CareConstraint(maxTempC: 30));
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(maxTempC: 40),
        confidence: 0.95,
      );

      await pump(tester, const CareTagScreen(id: itemId));
      final controller = container.read(
        careTagControllerProvider(itemId).notifier,
      );
      await controller.capture();
      await controller.readCollected();
      await tester.pumpAndSettle();

      expect(find.textContaining('did not state a fabric'), findsOneWidget);
      // And what is still on record, so the row is not simply blank.
      expect(find.textContaining('worked out earlier'), findsOneWidget);
    });
  });

  group('the care-label review screen', () {
    testWidgets('shows the prohibition it just announced in the diff', (
      tester,
    ) async {
      // The asymmetry that hid this: the diff above the summary *did* report
      // the change, so the screen looked like it had understood the label.
      await withLabel(const CareConstraint(maxTempC: 30));
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(maxTempC: 40, doNotDryClean: true),
        confidence: 0.95,
      );

      await pump(tester, const CareTagScreen(id: itemId));
      final controller = container.read(
        careTagControllerProvider(itemId).notifier,
      );
      await controller.capture();
      await controller.readCollected();
      await tester.pumpAndSettle();

      expect(find.text('Do not dry clean'), findsOneWidget);
    });

    testWidgets('shows the words the label printed', (tester) async {
      // Warnings are prose rather than symbols. Nothing rendered them here
      // before, so even once the server started reporting them they would have
      // gone unseen on the screen where the user decides whether to accept the
      // reading.
      await withLabel(const CareConstraint(maxTempC: 30));
      gateway.reading = const CareTagScanResult(
        instructions: CareConstraint(
          maxTempC: 40,
          warnings: {
            CareWarning.washInsideOut,
            CareWarning.washWithLikeColours,
          },
        ),
        confidence: 0.95,
      );

      await pump(tester, const CareTagScreen(id: itemId));
      final controller = container.read(
        careTagControllerProvider(itemId).notifier,
      );
      await controller.capture();
      await controller.readCollected();
      await tester.pumpAndSettle();

      expect(find.text('Take care'), findsOneWidget);
      expect(find.textContaining('inside out'), findsWidgets);
    });
  });
}

class _LabelGateway extends AiGateway {
  _LabelGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  CareTagScanResult reading = const CareTagScanResult(
    instructions: CareConstraint(maxTempC: 40),
    confidence: 0.9,
  );

  @override
  Future<CareTagScanResult> scanCareTag(List<ScanImage> images) async =>
      reading;
}

/// A fact the app knows nothing about.
///
/// Reported from a real phone, in dark mode: an item whose colour scan came
/// back empty rendered the Color row as a label, a gap and a lone
/// "Unsure · assumed" chip. That reads as a rendering fault rather than as
/// missing information — it was reported as one — and it had nothing to do
/// with the theme.
void _missingFacts() {
  testWidgets('a fact with no value says so rather than showing nothing', (
    tester,
  ) async {
    final repository = InMemoryWardrobeRepository();
    await repository.save(
      confidentItem(id: 'nocolor', name: 'Grey tee').copyWith(
        colors: Confident(
          ColorPalette.empty(),
          confidence: 0,
          source: Provenance.fallbackDefault,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
        ],
        child: const MaterialApp(home: ItemDetailScreen(id: ItemId('nocolor'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not known'), findsWidgets);
    // And offers to fix it. Colour is the one missing fact that changes what
    // the app *does*: with no palette the garment sorts by a default.
    expect(find.text('Set it'), findsOneWidget);
    // Which the laundry section admits to, rather than presenting a default as
    // a decision somebody made about this garment.
    expect(find.textContaining('assumed, no color recorded'), findsOneWidget);
  });

  testWidgets('a garment whose color is known is not nagged about it', (
    tester,
  ) async {
    final repository = InMemoryWardrobeRepository();
    await repository.save(confidentItem(id: 'navy', name: 'Navy tee'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
        ],
        child: const MaterialApp(home: ItemDetailScreen(id: ItemId('navy'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set it'), findsNothing);
    expect(find.textContaining('assumed'), findsNothing);
  });
}
