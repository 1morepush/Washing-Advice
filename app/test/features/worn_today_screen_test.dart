/// The Worn Today grid as the Rinse look draws it: a garment well per tile,
/// ringed and ticked when picked, with the button naming what will happen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/features/laundry/worn_today_screen.dart';
import 'package:washing_advice/widgets/rinse_kit.dart';

import '../support/fixtures.dart';

void main() {
  testWidgets('picked tiles are ringed and ticked, the others are not', (
    tester,
  ) async {
    final repository = InMemoryWardrobeRepository();
    for (final (id, name) in [('a', 'Navy hoodie'), ('b', 'Stone chinos')]) {
      await repository.save(confidentItem(id: id, name: name));
    }
    final container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WornTodayScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Thumbnails draw their own wells too; only a picked tile's is ringed.
    int ringed() => tester
        .widgetList<GarmentWell>(find.byType(GarmentWell))
        .where((well) => well.selected)
        .length;

    expect(ringed(), 0);
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('Pick what you wore'), findsOneWidget);

    await tester.tap(find.text('Navy hoodie'));
    await tester.pumpAndSettle();

    expect(ringed(), 1);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('Log 1 and put it in the basket'), findsOneWidget);
  });
}
