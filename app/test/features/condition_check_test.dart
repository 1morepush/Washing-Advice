/// Photographing a garment to see whether it has worn.
///
/// The assertion that matters is the negative one, as it is for stains: what
/// the model reported must not be what gets recorded. A wear observation moves
/// the condition grade and changes how the garment is washed from the next load
/// onward, so a finding that slipped through unconfirmed is not a display bug —
/// it is somebody's laundry quietly changing on the strength of a shadow.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';

import '../support/fixtures.dart';

const _jumper = ItemId('jumper');

/// A gateway whose reader answers with whatever the test decided.
class _Reader extends AiGateway {
  _Reader({this.observed = const [], this.fails = false})
    : super(baseUrl: Uri.parse('http://test.invalid/'));

  final List<ObservedWear> observed;
  final bool fails;

  /// What the request carried, so a test can check the garment was described
  /// rather than only that the call happened.
  String? sentGarment;
  String? sentFabric;
  String? sentKnown;
  int sentImages = 0;

  @override
  Future<List<ObservedWear>> readCondition({
    required List<ScanImage> images,
    required String garment,
    String? fabric,
    String? known,
  }) async {
    if (fails) throw const ScanFailure('The server is having a moment.');

    sentGarment = garment;
    sentFabric = fabric;
    sentKnown = known;
    sentImages = images.length;
    return observed;
  }
}

ObservedWear seen(
  WearType type,
  WearSeverity severity, {
  double confidence = 0.9,
  String? note,
}) => ObservedWear(
  type: type,
  severity: severity,
  confidence: confidence,
  note: note,
);

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog events;
  late _Reader reader;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    events = InMemoryEventLog();
    reader = _Reader();
  });

  Future<void> seedItem({List<WearObservation> condition = const []}) async {
    final item = confidentItem(
      id: _jumper.value,
      name: 'Navy jumper',
      type: ItemType.sweater,
      composition: const {Fiber.wool: 100},
    );
    await repository.save(
      condition.isEmpty
          ? item
          : item.copyWith(condition: ConditionAssessment(condition)),
    );
  }

  Future<void> pump(WidgetTester tester, {int photos = 2}) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(events),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'ev'),
          ),
          aiGatewayProvider.overrideWithValue(reader),
          imageCaptureProvider.overrideWithValue(
            FixedImageCaptureSource([
              for (var i = 0; i < photos; i++) ScanImage(bytes: [i, i, i]),
            ]),
          ),
        ],
        child: MaterialApp(home: ItemDetailScreen(id: _jumper)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for wear'));
    await tester.pumpAndSettle();
  }

  Future<void> look(WidgetTester tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Take photos'));
    await tester.pumpAndSettle();
  }

  testWidgets('the camera is not opened until somebody asks', (tester) async {
    await seedItem();
    await pump(tester);
    await openSheet(tester);

    expect(reader.sentImages, 0);
    expect(find.text('Take photos'), findsOneWidget);
  });

  testWidgets('what it finds is put as a question, not recorded', (
    tester,
  ) async {
    // The whole design. A finding that recorded itself would change how this
    // jumper is washed on evidence the owner never agreed with.
    reader = _Reader(
      observed: [
        seen(
          WearType.pilling,
          WearSeverity.moderate,
          note: 'along the inner sleeve',
        ),
      ],
    );
    await seedItem();
    await pump(tester);
    await look(tester);

    expect(find.text('Moderate pilling'), findsOneWidget);
    expect(find.text('along the inner sleeve'), findsOneWidget);

    final item = await repository.byId(_jumper);
    expect(item!.condition.isPristine, isTrue);
  });

  testWidgets('and is recorded only once it is accepted', (tester) async {
    reader = _Reader(
      observed: [seen(WearType.pilling, WearSeverity.moderate, note: 'cuffs')],
    );
    await seedItem();
    await pump(tester);
    await look(tester);

    await tester.tap(find.text('Record it'));
    await tester.pumpAndSettle();

    final item = await repository.byId(_jumper);
    expect(
      item!.condition.current[WearType.pilling]?.severity,
      WearSeverity.moderate,
    );
    // Where the model said to look, kept with the observation so the next
    // check can be compared against it rather than against a memory.
    expect(item.condition.current[WearType.pilling]?.note, 'cuffs');
  });

  testWidgets('saying "not there" records nothing', (tester) async {
    reader = _Reader(
      observed: [seen(WearType.hole, WearSeverity.severe, note: 'the hem')],
    );
    await seedItem();
    await pump(tester);
    await look(tester);

    await tester.tap(find.text('Not there'));
    await tester.pumpAndSettle();

    final item = await repository.byId(_jumper);
    expect(item!.condition.isPristine, isTrue);
  });

  testWidgets('each finding is answered on its own', (tester) async {
    // One "accept everything" button would collect agreement it had not been
    // given: these are separate claims and somebody may believe one and not
    // the next.
    reader = _Reader(
      observed: [
        seen(WearType.pilling, WearSeverity.moderate),
        seen(WearType.fading, WearSeverity.slight),
      ],
    );
    await seedItem();
    await pump(tester);
    await look(tester);

    expect(find.text('Record it'), findsNWidgets(2));

    await tester.tap(find.text('Record it').first);
    await tester.pumpAndSettle();

    final item = await repository.byId(_jumper);
    expect(item!.condition.current.keys, [WearType.pilling]);
  });

  testWidgets('a finding it was unsure about never reaches the screen', (
    tester,
  ) async {
    // A feature that cried pilling at shadows is one people learn to ignore,
    // and then they miss the real one.
    reader = _Reader(
      observed: [seen(WearType.hole, WearSeverity.severe, confidence: 0.2)],
    );
    await seedItem();
    await pump(tester);
    await look(tester);

    expect(find.text('Severe hole'), findsNothing);
    expect(find.text('Nothing to report'), findsOneWidget);
    // But said rather than hidden: somebody who can see the hole deserves to
    // know the app saw something and was not sure enough to say.
    expect(find.textContaining('set aside 1 thing'), findsOneWidget);
  });

  testWidgets('a clean garment is an answer rather than a blank', (
    tester,
  ) async {
    // The commonest outcome by far, and a panel that went empty on it would
    // read as a feature that had failed.
    await seedItem();
    await pump(tester);
    await look(tester);

    expect(find.text('Nothing to report'), findsOneWidget);
    expect(find.textContaining('the usual answer'), findsOneWidget);
  });

  testWidgets('a finding that changes the wash says so before the button', (
    tester,
  ) async {
    reader = _Reader(observed: [seen(WearType.pilling, WearSeverity.moderate)]);
    await seedItem();
    await pump(tester);
    await look(tester);

    expect(find.textContaining('cooler and gentler'), findsOneWidget);
  });

  testWidgets('and one that changes nothing does not claim to', (tester) async {
    reader = _Reader(observed: [seen(WearType.shrunk, WearSeverity.moderate)]);
    await seedItem();
    await pump(tester);
    await look(tester);

    expect(find.text('Moderate shrunk'), findsOneWidget);
    expect(find.textContaining('cooler and gentler'), findsNothing);
  });

  testWidgets('the model is told what it is looking at', (tester) async {
    // Pilling on wool and pilling on polyester look different, and a reader
    // told nothing about the fabric is guessing.
    await seedItem();
    await pump(tester);
    await look(tester);

    expect(reader.sentGarment, contains('Navy jumper'));
    expect(reader.sentFabric, '100% Wool');
  });

  testWidgets('and what is already on record', (tester) async {
    // So it is not asked to re-find what the owner already knows.
    await seedItem(
      condition: [
        WearObservation(
          type: WearType.pilling,
          severity: WearSeverity.moderate,
          observedAt: DateTime.utc(2026, 8, 9),
        ),
      ],
    );
    await pump(tester);
    await look(tester);

    expect(reader.sentKnown, contains('pilling'));
  });

  testWidgets('every photograph is sent, not just the first', (tester) async {
    // Wear is not evenly distributed — cuffs, underarms, the seat — and a
    // reader given only the front shot reports a jumper as fine.
    await seedItem();
    await pump(tester, photos: 3);
    await look(tester);

    expect(reader.sentImages, 3);
  });

  testWidgets('a failure offers another go rather than a dead end', (
    tester,
  ) async {
    reader = _Reader(fails: true);
    await seedItem();
    await pump(tester);
    await look(tester);

    expect(find.text('The server is having a moment.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
