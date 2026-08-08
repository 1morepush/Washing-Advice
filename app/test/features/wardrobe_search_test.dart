/// The search box and the query it belongs to, kept in step.
///
/// The box owns a `TextEditingController`, but the query is owned by a
/// provider that other things also write to — "Clear all" in the filter
/// sheet, and the "Clear filters" button on the empty state, both reset it to
/// [WardrobeScreen.baseline]. When that happens the field has to follow, or
/// the wardrobe shows every item while the box still displays the search that
/// is no longer being applied.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/features/wardrobe/wardrobe_screen.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    repository = InMemoryWardrobeRepository();
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'White cotton tee'),
      confidentItem(id: 'jeans', name: 'Selvedge jeans', type: ItemType.jeans),
    ]);

    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WardrobeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('typing filters the wardrobe', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'jeans');
    await tester.pumpAndSettle();

    expect(container.read(wardrobeQueryProvider).text, 'jeans');
    expect(find.text('Selvedge jeans'), findsOneWidget);
    expect(find.text('White cotton tee'), findsNothing);
  });

  testWidgets('clearing the query elsewhere empties the search box too', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'jeans');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'jeans'), findsOneWidget);

    // What "Clear all" in the filter sheet does, and what the empty state's
    // "Clear filters" button does — neither goes through the search field.
    container.read(wardrobeQueryProvider.notifier).state =
        WardrobeScreen.baseline;
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'jeans'), findsNothing);
    expect(find.text('White cotton tee'), findsOneWidget);
  });
}
