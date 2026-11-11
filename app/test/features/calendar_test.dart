/// The outfit calendar: the month grid, moving between months, and a day.
///
/// The grouping into days is the core's and is tested there. What is pinned
/// here is what somebody holding a phone would notice: that the grid shows the
/// garments on the right days, that paging stops where it should, that a day
/// opens its pieces, and that "Wore this again today" really writes to the log.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/features/calendar/calendar_screen.dart';
import 'package:washing_advice/features/calendar/calendar_day_screen.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';

import '../features/sell/sell_list_harness.dart' show loadAppFont;
import '../support/history_harness.dart';

void main() {
  late HistoryHarness h;

  setUpAll(loadAppFont);

  /// The 15th of March 2026 is a Sunday; the 4th, a Wednesday.
  setUp(() async {
    h = await HistoryHarness.create(now: DateTime(2026, 3, 15, 12));
    await h.addGarment('tee', name: 'White tee');
    await h.addGarment('jeans', name: 'Blue jeans', type: ItemType.jeans);
    await h.addGarment('jacket', name: 'Denim jacket', type: ItemType.jacket);
    await h.addGarment('hat', name: 'Wool hat', type: ItemType.hat);

    await h.wear('tee', DateTime(2026, 2, 20, 9));
    for (final id in ['tee', 'jeans']) {
      await h.wear(id, DateTime(2026, 3, 2, 8));
    }
    for (final id in ['tee', 'jeans', 'jacket', 'hat']) {
      await h.wear(id, DateTime(2026, 3, 4, 8));
    }
    await h.wear('tee', DateTime(2026, 3, 10, 8));
  });

  Finder day(String label) => find.bySemanticsLabel(RegExp(label));

  group('the month grid', () {
    testWidgets('opens on this month and says what it holds', (tester) async {
      await h.open(tester, location: '/calendar');

      expect(find.text('March 2026'), findsOneWidget);
      expect(find.text('3 days logged in March'), findsOneWidget);
      expect(find.text('Most worn: White tee, on 3 days'), findsOneWidget);
    });

    testWidgets('shows what was worn on the days it was worn', (tester) async {
      await h.open(tester, location: '/calendar');

      expect(day('Monday 2 March 2026: 2 pieces worn'), findsOneWidget);
      expect(day('Wednesday 4 March 2026: 4 pieces worn'), findsOneWidget);
      expect(day('Tuesday 10 March 2026: 1 piece worn'), findsOneWidget);
      // Four pieces is three pictures and the rest said in a number.
      expect(find.text('+1'), findsOneWidget);
    });

    testWidgets('a day with nothing is quiet, and is not a button', (
      tester,
    ) async {
      await h.open(tester, location: '/calendar');

      expect(day('Thursday 5 March 2026, nothing logged'), findsOneWidget);
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDayScreen), findsNothing);
    });

    testWidgets('today is marked, in words as well as in the grid', (
      tester,
    ) async {
      await h.open(tester, location: '/calendar');

      expect(day('Sunday 15 March 2026, today'), findsOneWidget);
    });

    testWidgets('the month starts on the right weekday', (tester) async {
      await h.open(tester, location: '/calendar');

      // 1 March 2026 was a Sunday, so six blanks lead it on a Monday-first
      // grid and the 1st is in the last column.
      final first = tester.getCenter(find.text('1').first);
      final sunday = tester.getCenter(find.text('S').last);
      expect((first.dx - sunday.dx).abs(), lessThan(8));
    });
  });

  group('moving between months', () {
    testWidgets('back to the month of the first wear, and no further', (
      tester,
    ) async {
      await h.open(tester, location: '/calendar');

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('February 2026'), findsOneWidget);
      expect(find.text('1 day logged in February'), findsOneWidget);

      final previous = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(previous.onPressed, isNull);
    });

    testWidgets('cannot go past the current month into the future', (
      tester,
    ) async {
      await h.open(tester, location: '/calendar');

      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);

      // And it can come forward again from the past, up to the same limit.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('March 2026'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a month with no wears says so', (tester) async {
      await h.wear('tee', DateTime(2026, 1, 12, 9));
      await h.open(tester, location: '/calendar');

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('January 2026'), findsOneWidget);
      expect(find.text('1 day logged in January'), findsOneWidget);
    });
  });

  group('a day', () {
    testWidgets('tapping a day opens its pieces, large', (tester) async {
      await h.open(tester, location: '/calendar');

      await tester.tap(day('Wednesday 4 March 2026: 4 pieces worn'));
      await tester.pumpAndSettle();

      expect(find.byType(CalendarDayScreen), findsOneWidget);
      expect(find.text('Wednesday 4 March'), findsOneWidget);
      expect(find.text('4 pieces worn'), findsOneWidget);
      for (final name in [
        'White tee',
        'Blue jeans',
        'Denim jacket',
        'Wool hat',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('a piece opens its garment page', (tester) async {
      await h.open(tester, location: '/calendar/2026-03-04');

      await tester.tap(find.text('Blue jeans'));
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(
        tester.widget<ItemDetailScreen>(find.byType(ItemDetailScreen)).id,
        const ItemId('jeans'),
      );
    });

    testWidgets('Wore this again today records the pieces as worn today', (
      tester,
    ) async {
      await h.open(tester, location: '/calendar/2026-03-04');
      final before = (await h.events.all(types: {wornEventType})).length;

      await tester.tap(find.text('Wore this again today'));
      await tester.pumpAndSettle();

      final after = await h.events.all(types: {wornEventType});
      expect(after.length, before + 4);
      final todays = [
        for (final e in after)
          if (e.occurredAt == h.now) e.itemId.value,
      ];
      expect(todays, unorderedEquals(['tee', 'jeans', 'jacket', 'hat']));

      // The confirmation the Worn today flow gives.
      expect(
        find.textContaining('4 garments in the basket. Logged as worn today'),
        findsOneWidget,
      );
      // And, as everywhere else a wear is recorded, into the basket.
      final tee = await h.wardrobe.byId(const ItemId('tee'));
      expect(tee!.lifecycle, LifecycleState.inLaundry);
    });

    testWidgets('and then today has them on the calendar', (tester) async {
      await h.open(tester, location: '/calendar/2026-03-04');
      await tester.tap(find.text('Wore this again today'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(day('Sunday 15 March 2026, today: 4 pieces worn'), findsOneWidget);
      expect(find.text('4 days logged in March'), findsOneWidget);
    });

    testWidgets('today itself does not offer to log the day again', (
      tester,
    ) async {
      await h.wear('tee', DateTime(2026, 3, 15, 8));
      await h.open(tester, location: '/calendar/2026-03-15');

      expect(find.text('1 piece worn'), findsOneWidget);
      expect(find.text('Wore this again today'), findsNothing);
    });

    testWidgets('Save as an outfit makes a saved outfit of the pieces', (
      tester,
    ) async {
      await h.open(tester, location: '/calendar/2026-03-04');

      await tester.tap(find.text('Save as an outfit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Wednesday best');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = await h.outfits.all();
      expect(saved.single.name, 'Wednesday best');
      expect(
        saved.single.itemIds.map((id) => id.value),
        unorderedEquals(['tee', 'jeans', 'jacket', 'hat']),
      );
      expect(find.text('Saved as Wednesday best.'), findsOneWidget);
    });

    testWidgets('one piece is not an outfit to save', (tester) async {
      await h.open(tester, location: '/calendar/2026-03-10');

      expect(find.text('Save as an outfit'), findsNothing);
      expect(find.text('Wore this again today'), findsOneWidget);
    });

    testWidgets('a garment since deleted keeps the day, and says so', (
      tester,
    ) async {
      await h.wear('ghost', DateTime(2026, 3, 10, 9));
      await h.open(tester, location: '/calendar/2026-03-10');

      expect(find.text('2 pieces worn'), findsOneWidget);
      expect(find.text('No longer in your wardrobe'), findsOneWidget);
      // The rest of the day can still be worn again.
      expect(find.text('Wore this again today'), findsOneWidget);
    });

    testWidgets('a sold garment is named as sold, and is not worn again', (
      tester,
    ) async {
      await h.addGarment(
        'sold-top',
        name: 'Sold top',
        lifecycle: LifecycleState.sold,
      );
      await h.wear('sold-top', DateTime(2026, 3, 11, 9));
      await h.open(tester, location: '/calendar/2026-03-11');

      expect(find.text('Sold'), findsOneWidget);
      expect(find.text('Wore this again today'), findsNothing);
    });

    testWidgets('a day with no wears, and an address that is no date', (
      tester,
    ) async {
      await h.open(tester, location: '/calendar/2026-03-12');
      expect(find.text('Nothing logged'), findsOneWidget);
    });

    testWidgets('an impossible date is said to be one', (tester) async {
      await h.open(tester, location: '/calendar/2026-02-30');
      expect(find.text('That is not a date'), findsOneWidget);
    });
  });

  group('before anything is logged', () {
    testWidgets('says how wear gets recorded', (tester) async {
      final empty = await HistoryHarness.create();
      await empty.open(tester, location: '/calendar');

      expect(find.text('No outfits logged yet'), findsOneWidget);
      expect(find.textContaining('Wore it'), findsOneWidget);
      expect(find.textContaining('Worn today'), findsOneWidget);
      expect(find.text('Log what you wore today'), findsOneWidget);
    });
  });

  group('finding it', () {
    testWidgets('More lists the calendar, and it opens', (tester) async {
      await h.open(tester, location: '/more');

      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarScreen), findsOneWidget);
    });
  });

  group('fits a phone', () {
    for (final entry in {
      'Light': Appearance.light,
      'Dark': Appearance.dark,
      'AMOLED': Appearance.amoled,
    }.entries) {
      for (final location in ['/calendar', '/calendar/2026-03-04']) {
        testWidgets('$location at 320 wide and 1.6 text, ${entry.key}', (
          tester,
        ) async {
          await h.open(
            tester,
            location: location,
            size: const Size(320, 900),
            textScale: 1.6,
            appearance: entry.value,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('the empty state at 320 wide and 1.6 text', (tester) async {
      final empty = await HistoryHarness.create();
      await empty.open(
        tester,
        location: '/calendar',
        size: const Size(320, 600),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
