/// Taking several garments to the basket at once.
///
/// The laundry screen could always take one garment at a time from its own
/// page, which is fine for one shirt and hopeless for a full basket — and a
/// full basket is the ordinary case. This is the route that makes the pile
/// worth keeping.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/router.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog log;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    log = InMemoryEventLog();
  });

  Future<void> seed(int count, {LifecycleState? lifecycle}) async {
    for (var i = 0; i < count; i++) {
      final item = confidentItem(id: 'item-$i', name: 'Cotton tee $i');
      await repository.save(
        lifecycle == null ? item : item.copyWith(lifecycle: lifecycle),
      );
    }
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(log),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'ev'),
          ),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<WardrobeItem>> basket() => repository.query(
    const WardrobeQuery(lifecycleStates: {LifecycleState.inLaundry}),
  );

  group('picking several garments out of the wardrobe', () {
    testWidgets('a long press starts selecting', (tester) async {
      await seed(3);
      await pump(tester);

      await tester.longPress(find.text('Cotton tee 0'));
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('a tap then adds to the selection rather than opening', (
      tester,
    ) async {
      // The important half. Navigating away mid-selection would throw the
      // selection out, which is not what a tap means once you have started
      // picking things.
      await seed(3);
      await pump(tester);

      await tester.longPress(find.text('Cotton tee 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cotton tee 1'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('tapping a selected garment takes it back out', (tester) async {
      await seed(3);
      await pump(tester);

      await tester.longPress(find.text('Cotton tee 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cotton tee 0'));
      await tester.pumpAndSettle();

      // Back to the ordinary wardrobe once nothing is picked.
      expect(find.text('Wardrobe'), findsOneWidget);
    });

    testWidgets('the whole selection goes to the basket at once', (
      tester,
    ) async {
      await seed(3);
      await pump(tester);

      await tester.longPress(find.text('Cotton tee 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Put 3 in the wash'));
      await tester.pumpAndSettle();

      expect(await basket(), hasLength(3));
      // And the selection ends, rather than leaving three ticks on garments
      // that are no longer where they were.
      expect(find.text('Wardrobe'), findsOneWidget);
    });

    testWidgets('a garment already in the machine is not offered', (
      tester,
    ) async {
      // `transitionTo` would refuse it anyway, so a live button here would be
      // one that silently does nothing.
      await seed(2, lifecycle: LifecycleState.beingWashed);
      await pump(tester);

      await tester.longPress(find.text('Cotton tee 0'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing here can go in the wash'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Nothing here can go in the wash'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the move is recorded, not only applied to the row', (
      tester,
    ) async {
      // The log is the record and the row is a projection of it — the same
      // relationship wears and washes have. A bulk move must not be the one
      // place that skips it.
      await seed(2);
      await pump(tester);

      await tester.longPress(find.text('Cotton tee 0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Put 1 in the wash'));
      await tester.pumpAndSettle();

      expect(await log.all(), hasLength(1));
      expect((await log.all()).single, isA<LifecycleChanged>());
    });
  });
}
