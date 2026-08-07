/// Recording that a garment has worn, and what that changes.
///
/// The rules being reached here — `warrantsGentlerCare`, the fabric-class
/// downgrade, `effectiveCare` — have been written and tested in the core since
/// M1 with nothing in the app able to trigger them. A pilling jumper was washed
/// exactly like a new one, because there was no way to say it was pilling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/history/wear_recorder.dart';
import 'package:washing_advice/features/wardrobe/report_wear_sheet.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog events;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    events = InMemoryEventLog();
    await repository.save(
      confidentItem(id: 'jumper', name: 'Wool jumper', type: ItemType.sweater),
    );

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(events),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'ev'),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<WardrobeItem> item() async =>
      (await repository.byId(const ItemId('jumper')))!;

  Future<void> report(WearType type, WearSeverity severity) => container
      .read(wearRecorderProvider)
      .recordCondition(const ItemId('jumper'), type: type, severity: severity);

  test('an observation is recorded as an event and as state', () async {
    // Both, and in that order: the log is the record and the assessment is a
    // projection of it, the same relationship wears and washes have.
    await report(WearType.pilling, WearSeverity.moderate);

    final logged = await events.all();
    expect(logged.single, isA<ConditionObserved>());
    expect((await item()).condition.observations, hasLength(1));
  });

  test('a pilling jumper is washed more gently than its label says', () async {
    final before = (await item()).effectiveCare;

    await report(WearType.pilling, WearSeverity.moderate);
    final after = (await item()).effectiveCare;

    expect(after.dry.tumbleDryAllowed, isFalse);
    expect(after.wash.agitation, Agitation.veryMild);
    expect(after.wash.maxTempC, lessThanOrEqualTo(before.wash.maxTempC ?? 60));
  });

  test('and drops a fabric class, so it sorts into a gentler load', () async {
    await repository.save(
      confidentItem(id: 'jeans', name: 'Jeans', type: ItemType.jeans),
    );
    final jeans = (await repository.byId(const ItemId('jeans')))!;
    expect(jeans.fabricClass, FabricClass.heavy);

    await container
        .read(wearRecorderProvider)
        .recordCondition(
          const ItemId('jeans'),
          type: WearType.looseSeam,
          severity: WearSeverity.moderate,
        );

    final worn = (await repository.byId(const ItemId('jeans')))!;
    expect(worn.fabricClass, FabricClass.normal);
  });

  test('a slight problem changes nothing about the wash', () async {
    // The threshold is in the core and this pins that the app respects it: a
    // little fading is worth recording and is not worth changing a cycle for.
    final before = (await item()).effectiveCare;

    await report(WearType.fading, WearSeverity.slight);

    expect(
      (await item()).effectiveCare.dry.tumbleDryAllowed,
      before.dry.tumbleDryAllowed,
    );
  });

  test('a problem the wash cannot worsen changes nothing either', () async {
    // A broken zip is a repair, not a laundry decision.
    final before = (await item()).effectiveCare;

    await report(WearType.brokenFastener, WearSeverity.severe);

    final after = (await item()).effectiveCare;
    expect(after.wash.agitation, before.wash.agitation);
    expect((await item()).condition.observations, hasLength(1));
  });

  test('repeated reports of the same kind do not stack', () async {
    // Only the latest observation of each type describes the present state;
    // the earlier ones stay for history.
    await report(WearType.pilling, WearSeverity.slight);
    await report(WearType.pilling, WearSeverity.severe);

    final condition = (await item()).condition;
    expect(condition.observations, hasLength(2));
    expect(condition.current[WearType.pilling]!.severity, WearSeverity.severe);
  });

  test('the grade reflects what has been reported', () async {
    expect((await item()).condition.grade, ConditionGrade.pristine);

    await report(WearType.pilling, WearSeverity.severe);

    expect((await item()).condition.grade, ConditionGrade.damaged);
  });

  test('reporting on an item that is gone is not an error', () async {
    // Events outlive items, and a race between a delete and a report should
    // not crash the app.
    await container
        .read(wearRecorderProvider)
        .recordCondition(
          const ItemId('nope'),
          type: WearType.stain,
          severity: WearSeverity.slight,
        );

    expect(await events.all(), hasLength(1));
  });

  test('the sorter puts a worn item in a gentler load', () async {
    // The end of the chain: a report changes which load the garment lands in,
    // which is the only reason any of this matters.
    await report(WearType.pilling, WearSeverity.moderate);

    final plan = container
        .read(laundrySorterProvider)
        .sort(await repository.query(const WardrobeQuery.launderable()));

    expect(plan.loads.single.washSpec.agitation, Agitation.veryMild);
    expect(plan.loads.single.drySpec.tumbleDryAllowed, isFalse);
  });

  group('the sheet', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async =>
                      showReportWearSheet(context, await item()),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('says what the report will do before it is made', (
      tester,
    ) async {
      // The point of the sheet. Marking something as pilling changes how it is
      // washed from the next load onward, and altering laundry advice without
      // saying so is exactly the surprise this app exists to prevent.
      await open(tester);

      expect(find.textContaining('cooler and gentler'), findsOneWidget);
    });

    testWidgets('and says when it will not', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Broken fastener'));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not change how'), findsOneWidget);
    });

    testWidgets('severity moves the line', (tester) async {
      // Pilling at moderate changes the wash; the same pilling reported as
      // slight does not, and the sheet has to track that rather than guess.
      await open(tester);
      expect(find.textContaining('cooler and gentler'), findsOneWidget);

      await tester.tap(find.text('Slight'));
      await tester.pumpAndSettle();

      expect(find.textContaining('does not change how'), findsOneWidget);
    });

    testWidgets('recording closes it and writes the event', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Record'));
      await tester.pumpAndSettle();

      expect(find.text('Report wear'), findsNothing);
      expect(await events.all(), hasLength(1));
    });

    testWidgets('cancelling writes nothing', (tester) async {
      await open(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(await events.all(), isEmpty);
    });
  });
}
