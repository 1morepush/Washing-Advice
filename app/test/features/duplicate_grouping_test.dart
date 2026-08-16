/// Six identical socks as one row, and what that does to everything else.
///
/// The grouping itself is a pure function tested in the core. What is tested
/// here is the part the README warned about: grouping "touches selection,
/// counts, filtering and the pile flow", and a collapse that got any of those
/// wrong would be worse than the crowding it fixes — a count that lies, or a
/// bulk action that moves one sock and leaves five behind.
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

  /// [count] copies of one garment, plus [others] distinguishable ones.
  Future<void> seed({required int count, int others = 0}) async {
    for (var i = 0; i < count; i++) {
      await repository.save(
        confidentItem(
          id: 'sock-$i',
          name: 'Black socks',
        ).copyWith(brand: Confident.fromUser('Uniqlo'), sizeLabel: 'M'),
      );
    }
    for (var i = 0; i < others; i++) {
      await repository.save(
        confidentItem(id: 'other-$i', name: 'Cotton tee $i').copyWith(
          brand: Confident.fromUser('Uniqlo'),
          sizeLabel: 'L',
          type: Confident.fromUser(ItemType.tShirt),
        ),
      );
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    WardrobeView view = WardrobeView.list,
  }) async {
    tester.view.physicalSize = const Size(420, 1600);
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
          // Pinned rather than left to the default: the two views say the
          // count differently — a subtitle in the list, a badge on a card —
          // and a test that did not choose would be asserting whichever
          // happened to be the default that day.
          wardrobeViewProvider.overrideWith((ref) => view),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('six identical socks are one row', (tester) async {
    // The complaint this answers: six tiles saying the same thing crowd out
    // the garment somebody was actually looking for.
    await seed(count: 6);
    await pump(tester);

    expect(find.text('Black socks'), findsOneWidget);
    expect(find.textContaining('6 of these'), findsOneWidget);
  });

  testWidgets('and the count still says six', (tester) async {
    // The row is a display decision. A wardrobe that reported "1 item" because
    // it had drawn one tile would be lying about what is in it.
    await seed(count: 6);
    await pump(tester);

    expect(find.text('6 items'), findsOneWidget);
  });

  testWidgets('tapping opens the group rather than a garment', (tester) async {
    // A collapsed group has no single garment to show: its members have their
    // own histories and wear counts, and picking one to stand for the rest
    // would be inventing an answer.
    await seed(count: 3);
    await pump(tester);

    await tester.tap(find.text('Black socks'));
    await tester.pumpAndSettle();

    expect(find.text('Black socks'), findsNWidgets(3));
    expect(find.textContaining('of these'), findsNothing);
  });

  testWidgets('and then a second tap opens one', (tester) async {
    await seed(count: 3);
    await pump(tester);

    await tester.tap(find.text('Black socks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black socks').first);
    await tester.pumpAndSettle();

    // On the garment's own page, which the wardrobe list does not have.
    expect(find.text('What it is'), findsOneWidget);
  });

  testWidgets('selecting a group takes every copy', (tester) async {
    // The one that would be worst to get wrong: a bulk move that took one sock
    // and left five in the drawer.
    await seed(count: 4);
    await pump(tester);

    await tester.longPress(find.text('Black socks'));
    await tester.pumpAndSettle();

    expect(find.text('4 selected'), findsOneWidget);
  });

  testWidgets('and deselecting gives every copy back', (tester) async {
    await seed(count: 4);
    await pump(tester);

    await tester.longPress(find.text('Black socks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Black socks'));
    await tester.pumpAndSettle();

    // Back to the ordinary wardrobe: half a group selected is a state nothing
    // on this screen can show.
    expect(find.text('Wardrobe'), findsOneWidget);
  });

  testWidgets('the whole group reaches the basket', (tester) async {
    await seed(count: 4);
    await pump(tester);

    await tester.longPress(find.text('Black socks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Put 4 in the wash'));
    await tester.pumpAndSettle();

    final basket = await repository.query(
      const WardrobeQuery(lifecycleStates: {LifecycleState.inLaundry}),
    );
    expect(basket, hasLength(4));
  });

  testWidgets('garments that merely look similar stay apart', (tester) async {
    await seed(count: 2, others: 2);
    await pump(tester);

    // Two socks collapsed, two tees collapsed — the tees differ from each
    // other by name only, which is not part of the signature. Two rows, each
    // standing for two garments, rather than one row standing for four.
    expect(find.textContaining('2 of these'), findsNWidgets(2));
    expect(find.text('Black socks'), findsOneWidget);
  });

  testWidgets('grouping can be turned off', (tester) async {
    // Inferred from facts the app happens to hold, so somebody whose wardrobe
    // it reads wrongly needs a way to stop it rather than to keep tapping
    // groups open.
    await seed(count: 3);
    await pump(tester);
    expect(find.text('Black socks'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Group identical items'));
    await tester.pumpAndSettle();

    expect(find.text('Black socks'), findsNWidgets(3));
  });
}
