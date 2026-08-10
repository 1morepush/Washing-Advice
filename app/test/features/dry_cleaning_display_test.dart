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
      await container
          .read(careTagControllerProvider(itemId).notifier)
          .captureAndRead();
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
      await container
          .read(careTagControllerProvider(itemId).notifier)
          .captureAndRead();
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
  Future<CareTagScanResult> scanCareTag(ScanImage image) async => reading;
}
