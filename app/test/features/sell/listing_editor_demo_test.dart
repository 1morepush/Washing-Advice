/// The editor on the demo's three listings.
///
/// The demo build seeds one listing in each state so that the Sell tab and the
/// screens behind it show real behaviour and not an empty page, and what a
/// reviewer opens first is exactly these. They are built by the demo, not by
/// these tests, so they are the one place the editor meets listings it did not
/// write itself: a draft with a price search attached, a listing that has sat
/// long enough to be nudged, and a sale.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/main_demo.dart';

import 'listing_editor_harness.dart';

void main() {
  late List<WardrobeItem> wardrobe;
  late List<Listing> listings;

  setUp(() {
    wardrobe = demoWardrobe();
    listings = demoListings(wardrobe);
  });

  Listing demo(String id) =>
      listings.singleWhere((listing) => listing.id.value == id);

  testWidgets('the draft has its prices, a suggestion and what is left', (
    tester,
  ) async {
    await openEditor(
      tester,
      listing: demo('demo-listing-1'),
      garments: wardrobe,
      size: tallScreen,
    );

    expect(find.textContaining('Prices checked'), findsOneWidget);
    expect(find.text(r'Use $30.00'), findsOneWidget);
    // The price it is already priced at, and what is left of it.
    expect(
      find.text("You get \$28.56 after Depop's fees (3.3%\u00a0+\u00a0\$0.45)"),
      findsOneWidget,
    );
    expect(find.text('Draft'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the draft looks up prices through the demo server', (
    tester,
  ) async {
    final app = await openEditor(
      tester,
      listing: demo('demo-listing-1').copyWith(clearPriceSearch: true),
      garments: wardrobe,
      server: demoGateway(),
      size: tallScreen,
    );
    expect(find.textContaining('Not looked up yet'), findsOneWidget);

    await tester.tap(find.text('Look up prices'));
    await tester.pumpAndSettle();

    expect(find.text('Prices checked just now'), findsOneWidget);
    expect(find.text('On Depop'), findsOneWidget);
    final stored = (await app.stored('demo-listing-1'))!;
    expect(stored.priceSearch!.status, PriceSearchStatus.ok);
    expect(stored.priceSearch!.comparables, isNotEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the listing that has sat is nudged to be refreshed', (
    tester,
  ) async {
    await openEditor(
      tester,
      listing: demo('demo-listing-2'),
      garments: wardrobe,
      size: tallScreen,
    );

    expect(find.text('Listed 16 days ago'), findsOneWidget);
    expect(find.textContaining("It's been up for 16 days"), findsOneWidget);
    expect(find.text("I've refreshed it on Depop"), findsOneWidget);
    // Jeans: so waist and inseam are asked for.
    expect(find.text('Waist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sale shows what it fetched and what was left', (
    tester,
  ) async {
    await openEditor(
      tester,
      listing: demo('demo-listing-3'),
      garments: wardrobe,
      size: tallScreen,
    );

    expect(find.text(r'Sold for $34.00'), findsOneWidget);
    expect(
      find.text(
        "You got ${formatUsd(DepopFees.us.netCents(3400))} after Depop's fees "
        '(3.3%\u00a0+\u00a0\$0.45)',
      ),
      findsOneWidget,
    );
    // The blouse is still in the wardrobe, so the sale offers to take it out.
    expect(find.text('Mark the Cream silk blouse as sold'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a garment in the demo wardrobe can be marked sold from its '
      'listing', (tester) async {
    final jumper = demo('demo-listing-1');
    final app = await openEditor(
      tester,
      listing: jumper.markSold(DateTime.now().toUtc(), priceCents: 2800),
      garments: wardrobe,
      size: tallScreen,
    );
    final garment = wardrobe.singleWhere((item) => item.id == jumper.itemId);

    await tester.tap(find.text('Mark the ${garment.displayName} as sold'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as sold').last);
    await tester.pumpAndSettle();

    expect(
      (await app.wardrobe.byId(garment.id))!.lifecycle,
      LifecycleState.sold,
    );
    expect(
      find.text("Marked as sold — it's no longer in your wardrobe"),
      findsOneWidget,
    );
  });
}
