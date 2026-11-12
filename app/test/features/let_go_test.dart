/// The "not worn in a year" suggestion: the list, Keep, Sell this, and where
/// it is mentioned.
///
/// Which garments qualify is the core's rule and is tested there, edge by edge.
/// What is pinned here is what a person would notice: that the list is what the
/// rule says and in its order, that Keep hides a garment and goes on hiding it
/// after the app restarts, that Sell this opens a listing for that garment, and
/// that the suggestion is mentioned in Insights and on Sell only when there is
/// something to say.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncValueX;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/features/insights/insights_screen.dart';
import 'package:washing_advice/features/let_go/let_go_providers.dart';
import 'package:washing_advice/features/let_go/let_go_screen.dart';
import 'package:washing_advice/features/sell/listing_editor_screen.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';

import '../support/history_harness.dart';
import 'sell/sell_list_harness.dart' show loadAppFont;

void main() {
  late HistoryHarness h;

  setUpAll(loadAppFont);

  setUp(() async {
    h = await HistoryHarness.create(now: DateTime(2026, 11, 11, 12));

    // Not worn for seventeen months.
    await h.addGarment(
      'jumper',
      name: 'Grey jumper',
      type: ItemType.sweater,
      addedAt: DateTime(2024, 1, 1),
      usage: UsageStats(timesWorn: 4, lastWornAt: DateTime(2025, 6, 1)),
      photo: true,
    );
    // Never worn at all, added before that: the longest unworn.
    await h.addGarment(
      'coat',
      name: 'Green coat',
      type: ItemType.coat,
      addedAt: DateTime(2024, 5, 1),
      usage: const UsageStats(),
    );
    // Everything that should not appear.
    await h.addGarment(
      'blazer',
      name: 'Navy blazer',
      type: ItemType.blazer,
      addedAt: DateTime(2023, 1, 1),
      usage: UsageStats(timesWorn: 1, lastWornAt: DateTime(2024, 1, 1)),
    );
    await h.addGarment(
      'tee',
      name: 'White tee',
      addedAt: DateTime(2024, 1, 1),
      usage: UsageStats(timesWorn: 30, lastWornAt: DateTime(2026, 10, 30)),
    );
    await h.addGarment(
      'new',
      name: 'New shirt',
      addedAt: DateTime(2026, 6, 1),
      usage: const UsageStats(),
    );
    await h.addGarment(
      'gone',
      name: 'Sold skirt',
      type: ItemType.skirt,
      addedAt: DateTime(2023, 1, 1),
      usage: UsageStats(timesWorn: 1, lastWornAt: DateTime(2023, 6, 1)),
      lifecycle: LifecycleState.sold,
    );
  });

  group('the list', () {
    testWidgets('offers what the rule says, longest unworn first', (
      tester,
    ) async {
      await h.open(tester, location: '/sell/unworn');

      expect(
        find.textContaining('2 things you haven’t worn in a year, longest'),
        findsOneWidget,
      );
      expect(find.text('Green coat'), findsOneWidget);
      expect(find.text('Grey jumper'), findsOneWidget);
      for (final left in [
        'Navy blazer',
        'White tee',
        'New shirt',
        'Sold skirt',
      ]) {
        expect(find.text(left), findsNothing, reason: left);
      }
      expect(
        tester.getTopLeft(find.text('Green coat')).dy,
        lessThan(tester.getTopLeft(find.text('Grey jumper')).dy),
      );
    });

    testWidgets('says when each was last worn, or that it never was', (
      tester,
    ) async {
      await h.open(tester, location: '/sell/unworn');

      expect(find.text('Last worn 1 Jun 2025'), findsOneWidget);
      expect(find.text('Never worn. Added 1 May 2024'), findsOneWidget);
    });

    testWidgets('never tells anybody what to do', (tester) async {
      await h.open(tester, location: '/sell/unworn');

      expect(find.textContaining('should'), findsNothing);
      expect(find.textContaining('ready to part'), findsOneWidget);
    });

    testWidgets('Open goes to the garment', (tester) async {
      await h.open(tester, location: '/sell/unworn');

      await tester.tap(find.text('Open').first);
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(
        tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).id,
        const ItemId('coat'),
      );
    });

    testWidgets('tapping the garment opens it too', (tester) async {
      await h.open(tester, location: '/sell/unworn');

      await tester.tap(find.text('Grey jumper'));
      await tester.pumpAndSettle();
      expect(find.byType(ItemDetailScreen), findsOneWidget);
    });

    testWidgets('an empty list says so, and why it might be', (tester) async {
      final none = await HistoryHarness.create(now: DateTime(2026, 11, 11));
      await none.open(tester, location: '/sell/unworn');

      expect(find.text('Nothing to suggest'), findsOneWidget);
    });
  });

  group('Sell this', () {
    testWidgets('starts a listing for that garment and opens it', (
      tester,
    ) async {
      await h.open(tester, location: '/sell/unworn');

      // The jumper is the second card, and the one with a photograph.
      await tester.tap(find.text('Sell this').last);
      await tester.pumpAndSettle();

      expect(find.byType(ListingEditorScreen), findsOneWidget);
      final made = await h.listings.forItem(const ItemId('jumper'));
      expect(made, hasLength(1));
      expect(
        tester.widget<ListingEditorScreen>(find.byType(ListingEditorScreen)).id,
        made.single.id,
      );

      // Back lands on the list again, with the garment still on it: selling
      // is not the same as having sold.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(LetGoScreen), findsOneWidget);
      expect(find.text('Grey jumper'), findsOneWidget);
    });
  });

  group('Keep', () {
    testWidgets('hides that garment and leaves the rest', (tester) async {
      await h.open(tester, location: '/sell/unworn');

      await tester.tap(find.text('Keep').first);
      await tester.pumpAndSettle();

      expect(find.text('Green coat'), findsNothing);
      expect(find.text('Grey jumper'), findsOneWidget);
      expect(
        find.textContaining('Green coat will not be suggested for six months'),
        findsOneWidget,
      );
    });

    testWidgets('is remembered across a restart', (tester) async {
      await h.open(tester, location: '/sell/unworn');
      await tester.tap(find.text('Keep').first);
      await tester.pumpAndSettle();

      // The stored form: the id and the day, in the preferences.
      final stored =
          jsonDecode(
                (await SharedPreferences.getInstance()).getString(
                  'letGoKeptOn',
                )!,
              )
              as Map<String, Object?>;
      expect(stored.keys, ['coat']);
      expect(DateTime.parse(stored['coat']! as String), h.now.toUtc());

      // A new process: nothing in memory, the same preferences and wardrobe.
      final restarted = h.newApp();
      await restarted.read(letGoKeepsProvider.future);
      await restarted.read(ownedItemsProvider.future);
      final again = restarted.read(letGoProvider).valueOrNull!;
      expect(again.map((c) => c.item.id.value), ['jumper']);
    });

    testWidgets('lapses after six months', (tester) async {
      SharedPreferences.setMockInitialValues({
        'letGoKeptOn': jsonEncode({
          'coat': DateTime(2026, 5, 1).toUtc().toIso8601String(),
          'jumper': DateTime(2026, 6, 1).toUtc().toIso8601String(),
        }),
      });
      await h.open(tester, location: '/sell/unworn');

      // Kept in May: the six months ended on the 1st of November. Kept in
      // June: still running.
      expect(find.text('Green coat'), findsOneWidget);
      expect(find.text('Grey jumper'), findsNothing);
    });

    testWidgets('Undo takes it back', (tester) async {
      await h.open(tester, location: '/sell/unworn');
      await tester.tap(find.text('Keep').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.text('Green coat'), findsOneWidget);
    });

    testWidgets('a store that cannot be read means nothing was kept', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'letGoKeptOn': 'not json'});
      await h.open(tester, location: '/sell/unworn');

      expect(find.text('Green coat'), findsOneWidget);
      expect(find.text('Grey jumper'), findsOneWidget);
    });
  });

  group('where it is mentioned', () {
    testWidgets('a card in Insights, which leads to the list', (tester) async {
      await h.open(tester, location: '/insights', size: const Size(400, 3000));

      expect(find.text('Not worn in a year'), findsOneWidget);
      expect(
        find.textContaining('2 things you haven’t worn in a year.'),
        findsOneWidget,
      );

      await tester.tap(find.text('See them'));
      await tester.pumpAndSettle();
      expect(find.byType(LetGoScreen), findsOneWidget);
    });

    testWidgets('Insights is silent when there is nothing to offer', (
      tester,
    ) async {
      final none = await HistoryHarness.create(now: DateTime(2026, 11, 11));
      await none.addGarment('tee', name: 'White tee');
      await none.open(tester, location: '/insights');

      expect(find.byType(InsightsScreen), findsOneWidget);
      expect(find.text('Not worn in a year'), findsNothing);
    });

    testWidgets('a line on the Sell tab\'s empty state', (tester) async {
      await h.open(tester, location: '/sell');

      expect(find.text('2 things you haven’t worn in a year'), findsOneWidget);
      await tester.tap(find.text('2 things you haven’t worn in a year'));
      await tester.pumpAndSettle();
      expect(find.byType(LetGoScreen), findsOneWidget);
    });

    testWidgets('and above the list once there are listings', (tester) async {
      await h.listings.save(
        Listing(
          id: const ListingId('d'),
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          title: 'Nike crewneck',
          itemType: ItemType.sweatshirt,
        ),
      );
      await h.open(tester, location: '/sell');

      expect(find.text('2 things you haven’t worn in a year'), findsOneWidget);
      expect(find.text('Drafts'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('2 things you haven’t worn in a year')).dy,
        lessThan(tester.getTopLeft(find.text('Drafts')).dy),
      );
    });

    testWidgets('the Sell tab says nothing when there is nothing', (
      tester,
    ) async {
      final none = await HistoryHarness.create(now: DateTime(2026, 11, 11));
      await none.open(tester, location: '/sell');
      expect(find.textContaining('haven’t worn in a year'), findsNothing);
    });

    testWidgets('one thing is "1 thing"', (tester) async {
      await h.wardrobe.delete(const ItemId('coat'));
      await h.open(tester, location: '/sell');
      expect(find.text('1 thing you haven’t worn in a year'), findsOneWidget);
    });
  });

  group('fits a phone', () {
    for (final entry in {
      'Light': Appearance.light,
      'Dark': Appearance.dark,
      'AMOLED': Appearance.amoled,
    }.entries) {
      for (final location in ['/sell/unworn', '/sell', '/insights']) {
        testWidgets('$location at 320 wide and 1.6 text, ${entry.key}', (
          tester,
        ) async {
          await h.open(
            tester,
            location: location,
            size: const Size(320, 3000),
            textScale: 1.6,
            appearance: entry.value,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the Sell list with a line above it', (tester) async {
      await h.listings.save(
        Listing(
          id: const ListingId('d'),
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          title: 'Nike crewneck',
          itemType: ItemType.sweatshirt,
        ),
      );
      await h.open(
        tester,
        location: '/sell',
        size: const Size(320, 1600),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
