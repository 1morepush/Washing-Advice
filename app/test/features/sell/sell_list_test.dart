/// The Sell tab: where a seller's listings stand.
///
/// The sums are the core's and are tested there; what is pinned here is that the
/// tab shows them as it should — the right listings in the right sections, the
/// net beside every price, a nudge at a fortnight and not a day before — and
/// that the ways to start a listing go where they say. The last group is about
/// whether any of it fits a small phone at a large text size, which a screenshot
/// of a roomy one would never show.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/features/sell/listing_editor_screen.dart';
import 'package:washing_advice/features/sell/new_listing_screen.dart';
import 'package:washing_advice/features/sell/pick_garment_screen.dart';
import 'package:washing_advice/features/sell/sell_screen.dart';

import 'sell_list_harness.dart';

void main() {
  late SellHarness h;

  setUpAll(loadAppFont);
  setUp(() async => h = await SellHarness.create());

  /// Tall enough that every card is built, for the tests that read all of them.
  const tall = Size(400, 2000);

  Listing draft(String id, {String title = '', int? price, DateTime? at}) =>
      Listing(
        id: ListingId(id),
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: at ?? DateTime.utc(2026, 10, 1),
        title: title,
        itemType: ItemType.sweatshirt,
        priceCents: price,
      );

  Listing listed(
    String id, {
    required DateTime at,
    String title = 'Levi\'s 501 jeans',
    int? price = 3800,
  }) => draft(id, title: title, price: price).markListed(at);

  Listing sold(
    String id, {
    required DateTime at,
    required int? paid,
    String title = 'Silk blouse',
    int? asked = 3800,
  }) => listed(
    id,
    at: at.subtract(const Duration(days: 12)),
    title: title,
    price: asked,
  ).markSold(at, priceCents: paid);

  Future<void> have(Iterable<Listing> all) async {
    for (final listing in all) {
      await h.listings.save(listing);
    }
  }

  group('the sections', () {
    testWidgets('are Drafts, Listed and Sold, in that order', (tester) async {
      await have([
        sold('s', at: h.now.subtract(const Duration(days: 22)), paid: 3400),
        listed('l', at: h.now.subtract(const Duration(days: 5))),
        draft('d', title: 'Nike crewneck', price: 3000),
      ]);

      await h.open(tester, size: tall);

      final drafts = tester.getTopLeft(find.text('Drafts')).dy;
      final listedAt = tester.getTopLeft(find.text('Listed')).dy;
      final soldAt = tester.getTopLeft(find.text('Sold')).dy;
      expect(drafts, lessThan(listedAt));
      expect(listedAt, lessThan(soldAt));
    });

    testWidgets('each hold their own listings and nobody else\'s', (
      tester,
    ) async {
      await have([
        draft('d1', title: 'Nike crewneck', price: 3000),
        draft('d2'),
        listed('l', at: h.now.subtract(const Duration(days: 5))),
        sold('s', at: h.now.subtract(const Duration(days: 22)), paid: 3400),
      ]);

      await h.open(tester, size: tall);

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      final listedLabel = top('Listed');
      final soldLabel = top('Sold');

      expect(top('Nike crewneck'), lessThan(listedLabel));
      expect(top('Untitled draft'), lessThan(listedLabel));
      expect(
        top('Levi\'s 501 jeans'),
        inExclusiveRange(listedLabel, soldLabel),
      );
      expect(top('Silk blouse'), greaterThan(soldLabel));
    });

    testWidgets('leave out a section with nothing in it', (tester) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);

      await h.open(tester, size: tall);

      expect(find.text('Drafts'), findsOneWidget);
      expect(find.text('Listed'), findsNothing);
      expect(find.text('Sold'), findsNothing);
    });

    testWidgets('keep a section\'s listings in the order they come in', (
      tester,
    ) async {
      // Most recently changed first, which is the repository's order: what was
      // just edited is what somebody is working on.
      await have([
        draft('a', title: 'Edited long ago', at: DateTime.utc(2026, 10, 2)),
        draft('b', title: 'Edited today', at: DateTime.utc(2026, 10, 16)),
        draft('c', title: 'Edited last week', at: DateTime.utc(2026, 10, 9)),
      ]);

      await h.open(tester, size: tall);

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('Edited today'), lessThan(top('Edited last week')));
      expect(top('Edited last week'), lessThan(top('Edited long ago')));
    });

    testWidgets('move a listing when it moves on, without a refresh', (
      tester,
    ) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);
      await h.open(tester, size: tall);
      expect(find.text('Listed'), findsNothing);

      // Posted on Depop, through the controller the editor will use.
      await h.listings.save(
        draft('d', title: 'Nike crewneck', price: 3000).markListed(h.now),
      );
      await tester.pumpAndSettle();

      expect(find.text('Drafts'), findsNothing);
      expect(find.text('Listed'), findsOneWidget);
      expect(find.text('Nike crewneck'), findsOneWidget);
    });
  });

  group('each card', () {
    testWidgets('shows the asking price and what Depop leaves of it', (
      tester,
    ) async {
      await have([
        draft('d1', title: 'Nike crewneck', price: 3000),
        listed('l', at: h.now.subtract(const Duration(days: 5)), price: 3800),
      ]);

      await h.open(tester, size: tall);

      // $30.00 less 3.3% and $0.45, which is the briefing's own example.
      expect(find.text(r'$30.00 · you get $28.56'), findsOneWidget);
      expect(find.text(r'$38.00 · you get $36.30'), findsOneWidget);
    });

    testWidgets('says so when there is no price yet', (tester) async {
      await have([draft('d', title: 'Nike crewneck')]);

      await h.open(tester, size: tall);

      expect(find.text('No price yet'), findsOneWidget);
      expect(find.textContaining('you get'), findsNothing);
    });

    testWidgets('says Untitled draft for a draft nobody has named', (
      tester,
    ) async {
      await have([draft('d')]);

      await h.open(tester, size: tall);

      expect(find.text('Untitled draft'), findsOneWidget);
    });

    testWidgets('mutes Untitled draft, which is not a title', (tester) async {
      await have([draft('d'), draft('e', title: 'Nike crewneck')]);

      await h.open(tester, size: tall);

      Color? ink(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;
      final scheme = Theme.of(
        tester.element(find.byType(SellScreen)),
      ).colorScheme;
      expect(ink('Untitled draft'), scheme.onSurfaceVariant);
      expect(ink('Nike crewneck'), isNot(scheme.onSurfaceVariant));
    });

    testWidgets('says how long a listing has been up', (tester) async {
      await have([
        listed('l', at: h.now.subtract(const Duration(days: 5))),
        listed(
          'm',
          title: 'Wool coat',
          at: h.now.subtract(const Duration(hours: 3)),
        ),
      ]);

      await h.open(tester, size: tall);

      expect(find.text('Listed 5 days ago'), findsOneWidget);
      expect(find.text('Listed 3 hours ago'), findsOneWidget);
    });

    testWidgets('shows what a sale was for, what was left, and when', (
      tester,
    ) async {
      await have([
        sold('s', at: h.now.subtract(const Duration(days: 22)), paid: 3400),
      ]);

      await h.open(tester, size: tall);

      // Asked $38.00 and sold for less, as a buyer's offer leaves it: the card
      // shows what it sold for, not what it was asked.
      expect(find.text(r'Sold for $34.00 · you got $32.43'), findsOneWidget);
      expect(find.text('Sold 25 Sep 2026'), findsOneWidget);
      expect(find.textContaining(r'$38.00'), findsNothing);
    });

    testWidgets('says so for a sale with no price recorded', (tester) async {
      await have([
        sold(
          's',
          at: h.now.subtract(const Duration(days: 3)),
          paid: null,
          asked: null,
        ),
      ]);

      await h.open(tester, size: tall);

      expect(find.text('No sale price recorded'), findsOneWidget);
    });

    testWidgets('opens its listing', (tester) async {
      await have([draft('d1', title: 'Nike crewneck', price: 3000)]);
      await h.open(tester, size: tall);

      await tester.tap(find.text('Nike crewneck'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ListingEditorScreen>(find.byType(ListingEditorScreen)).id,
        const ListingId('d1'),
      );
      // And Back is Sell, not somewhere else.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SellScreen), findsOneWidget);
    });

    testWidgets('shows a silhouette where there is no photograph', (
      tester,
    ) async {
      await have([draft('d', title: 'Nike crewneck')]);

      await h.open(tester, size: tall);

      // A drawing, not a gap. No colour is hard-coded in it, so the check is
      // that something is drawn in the picture's place.
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('the refresh nudge', () {
    const advice =
        'Listed 2 weeks — refresh it: drop the price a little or relist it so '
        'it shows as new.';
    final up = DateTime.utc(2026, 10, 3, 9);

    testWidgets('is not there at thirteen days', (tester) async {
      await have([listed('l', at: up)]);
      h.now = up.add(const Duration(days: 13));

      await h.open(tester, size: tall);

      expect(find.text('Listed 13 days ago'), findsOneWidget);
      expect(find.textContaining('refresh it'), findsNothing);
    });

    testWidgets('nor a second before fourteen', (tester) async {
      await have([listed('l', at: up)]);
      h.now = up
          .add(const Duration(days: 14))
          .subtract(const Duration(seconds: 1));

      await h.open(tester, size: tall);

      expect(find.textContaining('refresh it'), findsNothing);
    });

    testWidgets('is there at exactly fourteen', (tester) async {
      await have([listed('l', at: up)]);
      h.now = up.add(const Duration(days: 14));

      await h.open(tester, size: tall);

      expect(find.text(advice), findsOneWidget);
      expect(find.text('Listed 14 days ago'), findsOneWidget);
    });

    testWidgets('counts the weeks', (tester) async {
      await have([listed('l', at: up)]);
      h.now = up.add(const Duration(days: 23));

      await h.open(tester, size: tall);

      expect(
        find.textContaining('Listed 3 weeks — refresh it'),
        findsOneWidget,
      );
    });

    testWidgets('is on the card, so it is seen without opening it', (
      tester,
    ) async {
      await have([
        listed('l', at: up, title: 'Wool coat'),
        listed('m', at: h.now.subtract(const Duration(days: 2))),
      ]);
      h.now = up.add(const Duration(days: 16));

      await h.open(tester, size: tall);

      // One nudge, and it is inside the old listing's card, not the new one's.
      expect(find.textContaining('refresh it'), findsOneWidget);
      final card = find.ancestor(
        of: find.text('Wool coat'),
        matching: find.byType(Card),
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('refresh it')),
        findsOneWidget,
      );
    });

    testWidgets('looks like advice and not an error', (tester) async {
      await have([listed('l', at: up)]);
      h.now = up.add(const Duration(days: 16));

      await h.open(tester, size: tall);

      final scheme = Theme.of(
        tester.element(find.byType(SellScreen)),
      ).colorScheme;
      final panel = tester.widget<Container>(
        find
            .ancestor(
              of: find.textContaining('refresh it'),
              matching: find.byType(Container),
            )
            .first,
      );
      final fill = (panel.decoration! as BoxDecoration).color;
      expect(fill, scheme.tertiaryContainer);
      expect(fill, isNot(scheme.errorContainer));
    });

    testWidgets('is not given to a draft, or to a sale', (tester) async {
      await have([
        draft('d', title: 'Nike crewneck', price: 3000),
        sold('s', at: up, paid: 3400),
      ]);
      h.now = up.add(const Duration(days: 60));

      await h.open(tester, size: tall);

      expect(find.textContaining('refresh it'), findsNothing);
    });

    testWidgets('is there after the app comes back, though nothing changed', (
      tester,
    ) async {
      // A phone left with the app open for a few days comes back to a list that
      // was drawn before them.
      await have([listed('l', at: up)]);
      h.now = up.add(const Duration(days: 13));
      await h.open(tester, size: tall);
      expect(find.textContaining('refresh it'), findsNothing);

      h.now = up.add(const Duration(days: 14, hours: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text(advice), findsOneWidget);
    });
  });

  group('the sold total', () {
    testWidgets('is the count and what Depop\'s fees left', (tester) async {
      await have([
        sold('a', at: h.now.subtract(const Duration(days: 22)), paid: 3400),
        sold(
          'b',
          title: 'Wool coat',
          at: h.now.subtract(const Duration(days: 9)),
          paid: 5000,
        ),
      ]);

      await h.open(tester, size: tall);

      // $32.43 and $47.90.
      expect(find.text('2 sold · you got \$80.33 after fees'), findsOneWidget);
    });

    testWidgets('sits at the top of Sold', (tester) async {
      await have([
        listed('l', at: h.now.subtract(const Duration(days: 5))),
        sold('a', at: h.now.subtract(const Duration(days: 22)), paid: 3400),
      ]);

      await h.open(tester, size: tall);

      final label = tester.getTopLeft(find.text('Sold')).dy;
      final total = tester.getTopLeft(find.textContaining('sold · you got')).dy;
      final first = tester.getTopLeft(find.text('Silk blouse')).dy;
      expect(total, greaterThan(label));
      expect(total, lessThan(first));
    });

    testWidgets('is for a single sale as well', (tester) async {
      await have([
        sold('a', at: h.now.subtract(const Duration(days: 22)), paid: 3400),
      ]);

      await h.open(tester, size: tall);

      expect(find.text('1 sold · you got \$32.43 after fees'), findsOneWidget);
    });

    testWidgets('owns up to a sale that had no price', (tester) async {
      await have([
        sold('a', at: h.now.subtract(const Duration(days: 22)), paid: 3400),
        sold(
          'b',
          title: 'Wool coat',
          at: h.now.subtract(const Duration(days: 9)),
          paid: null,
          asked: null,
        ),
      ]);

      await h.open(tester, size: tall);

      expect(
        find.text(
          '2 sold · you got \$32.43 after fees · 1 has no price recorded',
        ),
        findsOneWidget,
      );
    });

    testWidgets('is not shown when nothing has sold', (tester) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);

      await h.open(tester, size: tall);

      expect(find.textContaining('sold ·'), findsNothing);
    });
  });

  group('the fee', () {
    testWidgets('is named once, with the day it was checked', (tester) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);

      await h.open(tester, size: tall);

      final note = find.textContaining('after Depop\'s fee of');
      expect(note, findsOneWidget);
      expect(
        tester.widget<Text>(note).data,
        allOf(contains('3.3%\u00a0+\u00a0\$0.45'), contains('17 October 2026')),
      );
    });
  });

  group('starting a listing', () {
    testWidgets('is a floating button once there is a list, and not before', (
      tester,
    ) async {
      await h.open(tester);
      // The empty state has the two ways to start in buttons of its own.
      expect(find.byType(FloatingActionButton), findsNothing);

      await have([draft('d', title: 'Nike crewneck', price: 3000)]);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FloatingActionButton, 'New listing'),
        findsOneWidget,
      );
    });

    testWidgets('offers photographing it or choosing from the wardrobe', (
      tester,
    ) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);
      await h.open(tester);

      await tester.tap(find.text('New listing'));
      await tester.pumpAndSettle();

      expect(find.text('Take photos'), findsOneWidget);
      expect(find.text('Choose from my wardrobe'), findsOneWidget);
    });

    testWidgets('Take photos goes to the camera checklist', (tester) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);
      await h.open(tester);
      await tester.tap(find.text('New listing'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Take photos'));
      await tester.pumpAndSettle();

      expect(find.byType(NewListingScreen), findsOneWidget);
      // Over the bar, and Back is Sell.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SellScreen), findsOneWidget);
    });

    testWidgets('Choose from my wardrobe goes to the picker', (tester) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);
      await h.open(tester);
      await tester.tap(find.text('New listing'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose from my wardrobe'));
      await tester.pumpAndSettle();

      expect(find.byType(PickGarmentScreen), findsOneWidget);
    });

    testWidgets('dismissing the choice goes nowhere', (tester) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);
      await h.open(tester);
      await tester.tap(find.text('New listing'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Take photos'), findsNothing);
      expect(find.byType(SellScreen), findsOneWidget);
    });
  });

  group('with nothing on it', () {
    testWidgets('says what the tab does, and that nothing is posted', (
      tester,
    ) async {
      await h.open(tester);

      expect(find.text('Sell what you no longer wear'), findsOneWidget);
      expect(
        find.textContaining('writes the Depop description'),
        findsOneWidget,
      );
      expect(find.textContaining('suggests a price'), findsOneWidget);
      expect(find.textContaining('what has sold'), findsOneWidget);
      expect(find.textContaining('Nothing is posted for you'), findsOneWidget);
    });

    testWidgets('has no sections and no fee note to explain', (tester) async {
      await h.open(tester);

      expect(find.text('Drafts'), findsNothing);
      expect(find.textContaining('Depop\'s fee of'), findsNothing);
    });

    testWidgets('Photograph something to sell goes to the camera', (
      tester,
    ) async {
      await h.open(tester);

      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();

      expect(find.byType(NewListingScreen), findsOneWidget);
    });

    testWidgets('Choose from my wardrobe goes to the picker', (tester) async {
      await h.open(tester);

      await tester.tap(find.text('Choose from my wardrobe'));
      await tester.pumpAndSettle();

      expect(find.byType(PickGarmentScreen), findsOneWidget);
    });

    testWidgets('gives way to the list once there is a listing', (
      tester,
    ) async {
      await h.open(tester);
      expect(find.text('Sell what you no longer wear'), findsOneWidget);

      await have([draft('d', title: 'Nike crewneck', price: 3000)]);
      await tester.pumpAndSettle();

      expect(find.text('Sell what you no longer wear'), findsNothing);
      expect(find.text('Nike crewneck'), findsOneWidget);
    });
  });

  group('on a small phone at a large text size', () {
    const phone = Size(320, 640);
    const scale = 1.6;

    /// Scrolls the list from top to bottom, failing on the first overflow: the
    /// cards are built as they come into view, so one below the fold has not
    /// been laid out until it is scrolled to.
    Future<void> scrollThrough(WidgetTester tester) async {
      expect(tester.takeException(), isNull);
      final list = find.byType(Scrollable).first;
      for (var step = 0; step < 14; step++) {
        await tester.drag(list, const Offset(0, -260));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after scroll $step');
      }
    }

    /// Whether [finder]'s text kept every word whole: a name cut in half is
    /// worse than one that wraps.
    void expectWhole(WidgetTester tester, Finder finder) {
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      expect(paragraph.didExceedMaxLines, isFalse);
      for (final word in paragraph.text.toPlainText().split(' ')) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: paragraph.text.style),
          textDirection: TextDirection.ltr,
          textScaler: paragraph.textScaler,
        )..layout();
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(painter.width - 0.5),
          reason: '"$word" was broken or cut',
        );
        painter.dispose();
      }
    }

    testWidgets('the list, with all three sections, lays out', (tester) async {
      final up = h.now.subtract(const Duration(days: 17));
      await have([
        draft(
          'd1',
          title: 'Nike vintage crewneck sweatshirt grey',
          price: 3000,
        ),
        draft('d2'),
        listed(
          'l',
          at: up,
          title: 'Levi\'s 501 straight leg jeans medium wash W32 L32',
        ),
        sold('s1', at: h.now.subtract(const Duration(days: 22)), paid: 3400),
        sold(
          's2',
          title: 'Wool coat',
          at: h.now.subtract(const Duration(days: 9)),
          paid: 5000,
        ),
      ]);

      await h.open(tester, size: phone, textScale: scale);

      await scrollThrough(tester);
    });

    testWidgets('keeps the words of a card whole', (tester) async {
      await have([listed('l', at: h.now.subtract(const Duration(days: 17)))]);

      await h.open(tester, size: phone, textScale: scale);

      expect(tester.takeException(), isNull);
      expectWhole(tester, find.text('Listed 17 days ago'));
      expectWhole(tester, find.textContaining('refresh it'));
      expectWhole(tester, find.text(r'$38.00 · you get $36.30'));
    });

    testWidgets('the empty state lays out, and can be scrolled to its end', (
      tester,
    ) async {
      await h.open(tester, size: phone, textScale: scale);

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Choose from my wardrobe'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expectWhole(tester, find.text('Sell what you no longer wear'));
    });

    testWidgets('a long title is given more lines at a large text size', (
      tester,
    ) async {
      const title = "Vintage Nike grey crewneck sweatshirt women's medium";
      await have([draft('d', title: title, price: 3000)]);
      await h.open(tester, size: phone, textScale: scale);

      final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.maxLines, greaterThan(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the empty state has no floating button over its own', (
      tester,
    ) async {
      await h.open(tester, size: phone, textScale: scale);
      // As far as it goes.
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, -2000),
        3000,
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      // And the last button is where it can be tapped.
      final button = tester.getRect(
        find.widgetWithText(FilledButton, 'Choose from my wardrobe'),
      );
      expect(button.bottom, lessThanOrEqualTo(phone.height));
    });

    testWidgets('the two ways to start lay out', (tester) async {
      await have([draft('d', title: 'Nike crewneck', price: 3000)]);
      await h.open(tester, size: phone, textScale: scale);

      await tester.tap(find.text('New listing'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Choose from my wardrobe'),
        100,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
