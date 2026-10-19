/// Shipping, and where a listing has got to: posted, sold, and the garment
/// taken out of the wardrobe.
///
/// Depop cannot be told anything, so these buttons are the only way the app
/// learns what has happened, and what they leave behind is the whole record: a
/// listing marked sold at the wrong price, or a garment still in the wardrobe
/// that has gone, is wrong for as long as nobody looks. So the tests read what
/// was stored, in the listing and in the wardrobe, and not only what is shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/features/sell/editor/status_section.dart';

import '../../support/fixtures.dart';
import 'listing_editor_harness.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);

  Future<void> saved(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  DateTime daysAgo(int days) =>
      DateTime.now().toUtc().subtract(Duration(days: days));

  Listing listed({int days = 3, int? price = 3000, ItemId? itemId}) =>
      sampleListing(
        status: ListingStatus.listed,
        listedAt: daysAgo(days),
        priceCents: price,
        itemId: itemId,
      );

  Listing sold({int? soldPrice = 3400, int? price = 3800, ItemId? itemId}) =>
      sampleListing(
        status: ListingStatus.sold,
        listedAt: DateTime.utc(2026, 9, 9, 12),
        soldAt: DateTime.utc(2026, 9, 25, 12),
        soldPriceCents: soldPrice,
        priceCents: price,
        itemId: itemId,
      );

  WardrobeItem garment({LifecycleState lifecycle = LifecycleState.active}) =>
      confidentItem(
        id: 'sweat',
        name: 'Grey crewneck',
        type: ItemType.sweatshirt,
        lifecycle: lifecycle,
      );

  group('shipping', () {
    testWidgets('estimates the packed weight, in pounds and ounces', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(itemType: ItemType.tShirt),
        size: tallScreen,
      );

      // 150 g and a mailer is 7.4 oz, labelled at 8: the band is the lowest the
      // parcel can honestly be in.
      expect(find.text('About 8 oz packed (under 8 oz label)'), findsOneWidget);
    });

    testWidgets('writes a weight over a pound as pounds and ounces', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      final estimate = estimateShipping(ItemType.sweatshirt);
      expect(estimate.ounces, greaterThan(16));
      expect(
        find.text('About 1 lb 4 oz packed (1–2 lb label)'),
        findsOneWidget,
      );
    });

    testWidgets('says to weigh it, and what Depop does', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(
        find.text(
          'Weigh it packed to be sure. A label for the wrong weight means '
          'postage due.',
        ),
        findsOneWidget,
      );
      expect(find.text("Depop's prepaid USPS label."), findsOneWidget);
      expect(find.text('Ship within about 5 days.'), findsOneWidget);
      expect(
        find.text(
          "You're paid about 2 business days after delivery is confirmed.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('follows the item type', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      await tester.tap(find.byType(DropdownButtonFormField<ItemType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jeans').last);
      await tester.pumpAndSettle();

      final estimate = estimateShipping(ItemType.jeans);
      expect(
        find.text('About 1 lb 10 oz packed (${estimate.band} label)'),
        findsOneWidget,
      );
      await saved(tester);
    });
  });

  group('a draft', () {
    testWidgets('is not on Depop yet, and can open it', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Not on Depop yet.'), findsOneWidget);

      await tester.tap(find.text('Open Depop'));
      await tester.pump();

      expect(app.links.opened, [Uri.parse('https://www.depop.com/')]);
      expect(app.links.last, depopHome);
      // Opening Depop is not posting.
      expect((await app.stored('draft-1'))!.status, ListingStatus.draft);
    });

    testWidgets('is posted, and says how long it has been up', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await tester.tap(find.text("I've posted it"));
      await tester.pumpAndSettle();

      expect(find.text('Listed today'), findsOneWidget);
      expect(find.text("I've posted it"), findsNothing);
      final stored = (await app.stored('draft-1'))!;
      expect(stored.status, ListingStatus.listed);
      expect(stored.listedAt, isNotNull);
    });

    testWidgets('is stored with what was typed just before it was posted', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await tester.enterText(field('Title'), 'Typed, then posted');
      await tester.tap(find.text("I've posted it"));
      await tester.pumpAndSettle();

      final stored = (await app.stored('draft-1'))!;
      expect(stored.title, 'Typed, then posted');
      expect(stored.status, ListingStatus.listed);
    });
  });

  group('a listing that is up', () {
    testWidgets('says how long it has been', (tester) async {
      await openEditor(tester, listing: listed(days: 3), size: tallScreen);

      expect(find.text('Listed 3 days ago'), findsOneWidget);
      expect(find.text("I've posted it"), findsNothing);
      expect(find.text('Open Depop'), findsNothing);
    });

    testWidgets('does not nudge until it has been up for two weeks', (
      tester,
    ) async {
      await openEditor(tester, listing: listed(days: 13), size: tallScreen);

      expect(find.textContaining('Refreshing or relisting'), findsNothing);
      expect(find.text("I've refreshed it on Depop"), findsNothing);
    });

    testWidgets('nudges to refresh it after two weeks, and records that it '
        'was', (tester) async {
      final app = await openEditor(
        tester,
        listing: listed(days: 16),
        size: tallScreen,
      );

      expect(find.text('Listed 16 days ago'), findsOneWidget);
      expect(
        find.text(
          "It's been up for 16 days. Refreshing or relisting it on Depop puts "
          'it back in front of buyers.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text("I've refreshed it on Depop"));
      await tester.pumpAndSettle();

      expect(find.text('Listed today'), findsOneWidget);
      expect(find.textContaining('Refreshing or relisting'), findsNothing);
      expect(
        (await app.stored('draft-1'))!.listedAt!.isAfter(daysAgo(1)),
        isTrue,
      );
    });

    testWidgets('can go back to a draft', (tester) async {
      final app = await openEditor(
        tester,
        listing: listed(days: 3),
        size: tallScreen,
      );

      await tester.tap(find.text('Back to draft'));
      await tester.pumpAndSettle();

      expect(find.text('Draft'), findsOneWidget);
      expect(find.text("I've posted it"), findsOneWidget);
      final stored = (await app.stored('draft-1'))!;
      expect(stored.status, ListingStatus.draft);
      expect(stored.listedAt, isNull);
    });
  });

  group('it sold', () {
    testWidgets('asks for the price, which starts as the asking price', (
      tester,
    ) async {
      await openEditor(tester, listing: listed(price: 3000), size: tallScreen);

      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();

      expect(find.text('What did it sell for?'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Sold for')).controller!.text,
        '30',
      );
      // In the dialog; the page behind it says the same of the same price.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            "You get \$28.56 after Depop's fees (3.3%\u00a0+\u00a0\$0.45)",
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows what is left as the price is typed', (tester) async {
      await openEditor(tester, listing: listed(price: 3000), size: tallScreen);
      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();

      await tester.enterText(field('Sold for'), '27');
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(
            "You get ${formatUsd(DepopFees.us.netCents(2700))} after "
            "Depop's fees (3.3%\u00a0+\u00a0\$0.45)",
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('records the sale at the price typed', (tester) async {
      final app = await openEditor(
        tester,
        listing: listed(price: 3000),
        size: tallScreen,
      );
      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Sold for'), '27');
      await tester.pump();

      await tester.tap(find.text('Mark as sold'));
      await tester.pumpAndSettle();

      final stored = (await app.stored('draft-1'))!;
      expect(stored.status, ListingStatus.sold);
      expect(stored.soldPriceCents, 2700);
      // What it was asked at is not rewritten by what it fetched.
      expect(stored.priceCents, 3000);
      expect(stored.soldAt, isNotNull);
      expect(find.text(r'Sold for $27.00'), findsOneWidget);
    });

    testWidgets('records the asking price when it sold for that', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: listed(price: 3000),
        size: tallScreen,
      );
      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark as sold'));
      await tester.pumpAndSettle();

      expect((await app.stored('draft-1'))!.soldPriceCents, 3000);
    });

    testWidgets('can be left without a price when there is none to start '
        'from', (tester) async {
      final app = await openEditor(
        tester,
        listing: listed(price: null),
        size: tallScreen,
      );
      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Sold for')).controller!.text,
        isEmpty,
      );
      expect(
        find.text('Type what it sold for to see what you get.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Mark as sold'));
      await tester.pumpAndSettle();

      expect((await app.stored('draft-1'))!.status, ListingStatus.sold);
      expect((await app.stored('draft-1'))!.soldPriceCents, isNull);
      expect(find.text("The price wasn't recorded."), findsOneWidget);
    });

    testWidgets('will not record a price that is not one', (tester) async {
      await openEditor(tester, listing: listed(price: 3000), size: tallScreen);
      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();

      await tester.enterText(field('Sold for'), '0');
      await tester.pump();

      expect(find.text('Use an amount like 32 or 32.50.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Mark as sold'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('changes nothing when it is cancelled', (tester) async {
      final app = await openEditor(
        tester,
        listing: listed(price: 3000),
        size: tallScreen,
      );
      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect((await app.stored('draft-1'))!.status, ListingStatus.listed);
      expect(find.text('It sold'), findsOneWidget);
    });
  });

  group('a sale', () {
    testWidgets('shows the price, what was left, and when', (tester) async {
      await openEditor(tester, listing: sold(), size: tallScreen);

      expect(find.text(r'Sold for $34.00'), findsOneWidget);
      expect(
        find.text(
          "You got ${formatUsd(DepopFees.us.netCents(3400))} after Depop's "
          'fees (3.3%\u00a0+\u00a0\$0.45)',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Sold 25 Sep 2026 · listed for 16 days'),
        findsOneWidget,
      );
      expect(find.text('It sold'), findsNothing);
    });

    testWidgets('sold the day it was posted says under a day, not 0 days', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          status: ListingStatus.sold,
          listedAt: DateTime.utc(2026, 9, 25, 9),
          soldAt: DateTime.utc(2026, 9, 25, 12),
          soldPriceCents: 3400,
          priceCents: 3800,
        ),
        size: tallScreen,
      );

      expect(
        find.text('Sold 25 Sep 2026 · listed for under a day'),
        findsOneWidget,
      );
      expect(find.textContaining('0 days'), findsNothing);
    });

    testWidgets('can be taken back, after asking', (tester) async {
      final app = await openEditor(tester, listing: sold(), size: tallScreen);

      await tester.tap(find.text('Back to draft'));
      await tester.pumpAndSettle();
      expect(find.text('Back to draft?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await app.stored('draft-1'))!.status, ListingStatus.sold);

      await tester.tap(find.text('Back to draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Back to draft'));
      await tester.pumpAndSettle();

      final stored = (await app.stored('draft-1'))!;
      expect(stored.status, ListingStatus.draft);
      expect(stored.soldPriceCents, isNull);
      expect(stored.soldAt, isNull);
      expect(find.text('Draft'), findsOneWidget);
    });

    testWidgets('has no wardrobe to speak of when it has no garment', (
      tester,
    ) async {
      await openEditor(tester, listing: sold(), size: tallScreen);

      expect(find.text('Your wardrobe'), findsNothing);
      expect(find.textContaining('Mark the'), findsNothing);
    });
  });

  group('the garment', () {
    testWidgets('is offered for sale, with what will happen', (tester) async {
      final item = garment();
      await openEditor(
        tester,
        listing: sold(itemId: item.id),
        garments: [item],
        size: tallScreen,
      );

      expect(find.text('Mark the Grey crewneck as sold'), findsOneWidget);
      expect(
        find.text(
          'Marking the garment as sold takes it out of your wardrobe, '
          'laundry and outfits. It stays in its history.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining("it's no longer in your wardrobe"),
        findsNothing,
      );
    });

    testWidgets('is not touched by Cancel', (tester) async {
      final item = garment();
      final app = await openEditor(
        tester,
        listing: sold(itemId: item.id),
        garments: [item],
        size: tallScreen,
      );

      await tester.tap(find.text('Mark the Grey crewneck as sold'));
      await tester.pumpAndSettle();
      expect(find.text('Mark the Grey crewneck as sold?'), findsOneWidget);
      expect(find.textContaining('It stays in its history'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        (await app.wardrobe.byId(item.id))!.lifecycle,
        LifecycleState.active,
      );
      expect(await app.events.all(), isEmpty);
    });

    testWidgets('leaves the wardrobe when it is confirmed, and says so', (
      tester,
    ) async {
      final item = garment();
      final app = await openEditor(
        tester,
        listing: sold(itemId: item.id),
        garments: [item],
        size: tallScreen,
      );

      await tester.tap(find.text('Mark the Grey crewneck as sold'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as sold'));
      await tester.pumpAndSettle();

      final after = (await app.wardrobe.byId(item.id))!;
      expect(after.lifecycle, LifecycleState.sold);
      final moves = (await app.events.all()).whereType<LifecycleChanged>();
      expect(moves.map((event) => event.to), [LifecycleState.sold]);
      expect(moves.single.itemId, item.id);

      expect(
        find.text("Marked as sold — it's no longer in your wardrobe"),
        findsOneWidget,
      );
      expect(find.text('Mark the Grey crewneck as sold'), findsNothing);
    });

    testWidgets('is already sold: says so, and offers nothing', (tester) async {
      final item = garment(lifecycle: LifecycleState.sold);
      await openEditor(
        tester,
        listing: sold(itemId: item.id),
        garments: [item],
        size: tallScreen,
      );

      expect(
        find.text("Marked as sold — it's no longer in your wardrobe"),
        findsOneWidget,
      );
      expect(find.textContaining('Mark the'), findsNothing);
    });

    testWidgets('has already gone some other way: says so, and offers '
        'nothing', (tester) async {
      final item = garment(lifecycle: LifecycleState.donated);
      await openEditor(
        tester,
        listing: sold(itemId: item.id),
        garments: [item],
        size: tallScreen,
      );

      expect(
        find.textContaining(
          'Grey crewneck has already left your wardrobe (donated)',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Mark the'), findsNothing);
    });

    testWidgets('has been deleted: says so, and offers nothing', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sold(itemId: const ItemId('gone')),
        size: tallScreen,
      );

      expect(
        find.textContaining('The garment this was made from has been deleted'),
        findsOneWidget,
      );
      expect(find.textContaining('Mark the'), findsNothing);
    });

    testWidgets('is only offered once the listing has sold', (tester) async {
      final item = garment();
      await openEditor(
        tester,
        listing: listed(itemId: item.id),
        garments: [item],
        size: tallScreen,
      );

      expect(find.textContaining('Mark the'), findsNothing);
    });
  });

  group('from posting to a garment that has gone', () {
    testWidgets('posted, sold, and the garment marked as sold', (tester) async {
      final item = garment();
      final app = await openEditor(
        tester,
        listing: sampleListing(itemId: item.id, priceCents: 3000),
        garments: [item],
        size: tallScreen,
      );

      await tester.tap(find.text("I've posted it"));
      await tester.pumpAndSettle();
      expect(find.text('Listed today'), findsOneWidget);

      await tester.tap(find.text('It sold'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Sold for'), '28');
      await tester.pump();
      await tester.tap(find.text('Mark as sold'));
      await tester.pumpAndSettle();
      expect(find.text(r'Sold for $28.00'), findsOneWidget);

      await tester.tap(find.text('Mark the Grey crewneck as sold'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Mark as sold'));
      await tester.pumpAndSettle();

      final listing = (await app.stored('draft-1'))!;
      expect(listing.status, ListingStatus.sold);
      expect(listing.soldPriceCents, 2800);
      expect(
        (await app.wardrobe.byId(item.id))!.lifecycle,
        LifecycleState.sold,
      );
      expect(
        (await app.events.all()).whereType<LifecycleChanged>().map((e) => e.to),
        [LifecycleState.sold],
      );
      expect(
        find.text("Marked as sold — it's no longer in your wardrobe"),
        findsOneWidget,
      );
    });
  });
}
