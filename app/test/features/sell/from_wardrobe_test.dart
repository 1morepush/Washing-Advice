/// Selling something already in the wardrobe: choosing it, and starting from it.
///
/// Two ways in — the picker, and "Sell this" on a garment's page — and one
/// screen they both end at, which asks the controller for the garment's listing.
/// What is pinned is what a person would notice: the garments that are offered,
/// and in what order; that asking twice for the same garment gives the same
/// listing and not a second; and that when the server cannot read the photographs
/// the person still gets a draft, and is told why it is thinner than it might be.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/features/sell/listing_editor_screen.dart';
import 'package:washing_advice/features/sell/new_listing_screen.dart';
import 'package:washing_advice/features/sell/pick_garment_screen.dart';
import 'package:washing_advice/features/sell/sell_screen.dart';
import 'package:washing_advice/features/sell/start/least_worn.dart';
import 'package:washing_advice/features/sell/start_from_garment_screen.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';

import '../../support/fixtures.dart';
import 'sell_list_harness.dart';

void main() {
  late SellHarness h;

  setUpAll(loadAppFont);
  setUp(() async => h = await SellHarness.create());

  /// Tall enough that every garment in the picker is built.
  const tall = Size(400, 2400);

  Future<void> openPicker(
    WidgetTester tester, {
    Size size = tall,
    double textScale = 1,
  }) => h.open(
    tester,
    location: '/sell/from-wardrobe',
    size: size,
    textScale: textScale,
  );

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  void expectOnEditor(WidgetTester tester, ListingId id) {
    expect(find.byType(ListingEditorScreen), findsOneWidget);
    expect(
      tester.widget<ListingEditorScreen>(find.byType(ListingEditorScreen)).id,
      id,
    );
  }

  group('least worn first', () {
    WardrobeItem garment(
      String id, {
      required int worn,
      DateTime? last,
      String? name,
    }) => confidentItem(
      id: id,
      name: name ?? id,
      usage: UsageStats(timesWorn: worn, lastWornAt: last),
    );

    List<String> order(Iterable<WardrobeItem> items) => [
      for (final item in leastWornFirst(items)) item.id.value,
    ];

    test('puts what was never worn before what was', () {
      expect(
        order([
          garment('often', worn: 40, last: DateTime.utc(2026, 10, 1)),
          garment('never', worn: 0),
          garment('twice', worn: 2, last: DateTime.utc(2026, 5, 1)),
        ]),
        ['never', 'twice', 'often'],
      );
    });

    test('orders by how many times, whenever they were worn', () {
      // A garment worn once last week is still worn less than one worn twice
      // last year.
      expect(
        order([
          garment('twice-long-ago', worn: 2, last: DateTime.utc(2025, 1, 1)),
          garment('once-lately', worn: 1, last: DateTime.utc(2026, 10, 10)),
        ]),
        ['once-lately', 'twice-long-ago'],
      );
    });

    test('puts the one longest unworn first among those worn as often', () {
      expect(
        order([
          garment('lately', worn: 5, last: DateTime.utc(2026, 10, 1)),
          garment('long-ago', worn: 5, last: DateTime.utc(2026, 1, 1)),
          garment('between', worn: 5, last: DateTime.utc(2026, 6, 1)),
        ]),
        ['long-ago', 'between', 'lately'],
      );
    });

    test(
      'puts one with no date after those with one, as the wardrobe does',
      () {
        // Not a very old date, but none at all.
        expect(
          order([
            garment('undated', worn: 5),
            garment('dated', worn: 5, last: DateTime.utc(2026, 10, 1)),
          ]),
          ['dated', 'undated'],
        );
      },
    );

    test(
      'puts everything never worn in name order, so the list holds still',
      () {
        expect(
          order([
            garment('c', worn: 0, name: 'Zip hoodie'),
            garment('a', worn: 0, name: 'blue shirt'),
            garment('b', worn: 0, name: 'Anorak'),
          ]),
          ['b', 'a', 'c'],
        );
      },
    );

    test('settles a tie of name by id', () {
      expect(
        order([
          garment('two', worn: 0, name: 'Black socks'),
          garment('one', worn: 0, name: 'Black socks'),
        ]),
        ['one', 'two'],
      );
    });

    test('is a new list and leaves the one it was given alone', () {
      final given = [garment('b', worn: 3), garment('a', worn: 1)];

      final sorted = leastWornFirst(given);

      expect(sorted.map((i) => i.id.value), ['a', 'b']);
      expect(given.map((i) => i.id.value), ['b', 'a']);
    });

    test('is empty for no garments', () {
      expect(leastWornFirst(const []), isEmpty);
    });
  });

  group('the picker', () {
    testWidgets('offers what is owned, least worn first', (tester) async {
      await h.addGarment(
        'a',
        name: 'Often worn coat',
        worn: 5,
        lastWornDaysAgo: 10,
      );
      await h.addGarment('b', name: 'Never worn shirt', worn: 0);
      await h.addGarment(
        'c',
        name: 'Long forgotten cardigan',
        worn: 5,
        lastWornDaysAgo: 100,
      );
      await h.addGarment(
        'd',
        name: 'Twice worn scarf',
        worn: 2,
        lastWornDaysAgo: 40,
      );

      await openPicker(tester);

      final names = [
        'Never worn shirt',
        'Twice worn scarf',
        'Long forgotten cardigan',
        'Often worn coat',
      ];
      for (var i = 1; i < names.length; i++) {
        expect(
          top(tester, names[i - 1]),
          lessThan(top(tester, names[i])),
          reason: '${names[i - 1]} before ${names[i]}',
        );
      }
    });

    testWidgets('says how often each was worn, and when last', (tester) async {
      await h.addGarment('a', name: 'Coat', worn: 5, lastWornDaysAgo: 100);
      await h.addGarment('b', name: 'Shirt', worn: 0);
      await h.addGarment('c', name: 'Scarf', worn: 1, lastWornDaysAgo: 3);

      await openPicker(tester);

      expect(find.text('Sweater · never worn'), findsOneWidget);
      expect(find.text('Sweater · worn once'), findsOneWidget);
      expect(find.text('Sweater · worn 5 times'), findsOneWidget);
      expect(find.text('Last worn 100 days ago'), findsOneWidget);
      expect(find.text('Last worn 3 days ago'), findsOneWidget);
      // Nothing to say about when something never worn was last worn.
      expect(find.textContaining('Last worn'), findsNWidgets(2));
    });

    testWidgets('does not offer what has gone', (tester) async {
      await h.addGarment('mine', name: 'In the wardrobe');
      await h.addGarment(
        'wash',
        name: 'In the basket',
        lifecycle: LifecycleState.inLaundry,
      );
      await h.addGarment(
        'sold',
        name: 'Already sold',
        lifecycle: LifecycleState.sold,
      );
      await h.addGarment(
        'gift',
        name: 'Given away',
        lifecycle: LifecycleState.donated,
      );
      await h.addGarment(
        'gone',
        name: 'Deleted',
        lifecycle: LifecycleState.removed,
      );

      await openPicker(tester);

      expect(find.text('In the wardrobe'), findsOneWidget);
      // Dirty is still owned.
      expect(find.text('In the basket'), findsOneWidget);
      expect(find.text('Already sold'), findsNothing);
      expect(find.text('Given away'), findsNothing);
      expect(find.text('Deleted'), findsNothing);
    });

    testWidgets('explains the order it uses', (tester) async {
      await h.addGarment('a');

      await openPicker(tester);

      expect(find.textContaining('Worn least first'), findsOneWidget);
    });

    testWidgets('picking one starts its listing', (tester) async {
      final shirt = await h.addGarment('b', name: 'Never worn shirt', worn: 0);
      await h.addGarment('a', name: 'Often worn coat', worn: 9);

      await openPicker(tester);
      await tester.tap(find.text('Never worn shirt'));
      await tester.pumpAndSettle();

      expectOnEditor(tester, const ListingId('listing-1'));
      final listing = (await h.listings.all()).single;
      expect(listing.itemId, shirt.id);
      // What the wardrobe knows went up with the photographs.
      expect(
        h.gateway.described.single.context,
        describeContextForItem((await h.wardrobe.byId(shirt.id))!),
      );
    });

    testWidgets('replaces itself, so Back from the listing is Sell', (
      tester,
    ) async {
      await h.addGarment('b', name: 'Never worn shirt', worn: 0);
      await h.open(tester, size: tall);
      await tester.tap(find.text('Choose from my wardrobe'));
      await tester.pumpAndSettle();
      expect(find.byType(PickGarmentScreen), findsOneWidget);

      await tester.tap(find.text('Never worn shirt'));
      await tester.pumpAndSettle();
      expect(find.byType(PickGarmentScreen), findsNothing);
      expect(find.byType(StartFromGarmentScreen), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
      // And the draft is the first thing on it.
      expect(
        find.text('Nike vintage crewneck sweatshirt grey'),
        findsOneWidget,
      );
    });

    testWidgets('an empty wardrobe says so, and offers the camera instead', (
      tester,
    ) async {
      await openPicker(tester);

      expect(find.text('Nothing in your wardrobe yet'), findsOneWidget);
      expect(find.textContaining('Worn least first'), findsNothing);

      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();
      expect(find.byType(NewListingScreen), findsOneWidget);
      expect(find.byType(PickGarmentScreen), findsNothing);
    });

    testWidgets('has a Back arrow to Sell', (tester) async {
      await h.addGarment('a');
      await h.open(tester);
      await tester.tap(find.text('Choose from my wardrobe'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
    });
  });

  group('starting from a garment', () {
    const asleep = ScanFailure('The server is asleep.');

    testWidgets('makes the garment\'s listing and opens it', (tester) async {
      final coat = await h.addGarment('a', name: 'Wool coat');

      await h.open(tester, location: '/sell/from-wardrobe/a');

      expectOnEditor(tester, const ListingId('listing-1'));
      final listing = (await h.listings.all()).single;
      expect(listing.itemId, coat.id);
      expect(listing.status, ListingStatus.draft);
      // The reading's title and the garment's own photograph, pointed at and
      // not copied.
      expect(listing.title, h.gateway.facts.title);
      expect(listing.facts, h.gateway.facts);
      expect(listing.photos.map((p) => p.uri), [coat.photos.photos.single.uri]);
      expect(h.images.length, 1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('asks the controller once', (tester) async {
      await h.addGarment('a');
      h.gateway.hold = Completer<void>();

      await h.open(tester, location: '/sell/from-wardrobe/a', settle: false);
      expect(h.gateway.described, hasLength(1));
      // A rebuild — a phone turned, a text size changed — is not a new request.
      tester.view.physicalSize = const Size(800, 400);
      await tester.pump(const Duration(milliseconds: 100));
      tester.view.physicalSize = const Size(400, 800);
      await tester.pump(const Duration(milliseconds: 100));

      expect(h.gateway.described, hasLength(1));
      h.gateway.hold!.complete();
      await tester.pumpAndSettle();
      expect(h.listings.length, 1);
    });

    testWidgets('shows that it is working, and then, if it is slow, why', (
      tester,
    ) async {
      await h.addGarment('a');
      h.gateway.hold = Completer<void>();

      await h.open(tester, location: '/sell/from-wardrobe/a', settle: false);

      expect(find.text('Starting your listing…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('The server sleeps'), findsNothing);

      await tester.pump(wakingAfter - const Duration(seconds: 1));
      expect(find.textContaining('The server sleeps'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.text(
          'The server sleeps when it is not in use, so the first scan in a '
          'while takes longer while it wakes up.',
        ),
        findsOneWidget,
      );

      h.gateway.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ListingEditorScreen), findsOneWidget);
    });

    testWidgets('when the photographs cannot be read, still opens a draft and '
        'says why it is thin', (tester) async {
      final coat = await h.addGarment('a', name: 'Wool coat');
      h.gateway.describeError = asleep;

      await h.open(tester, location: '/sell/from-wardrobe/a');

      expectOnEditor(tester, const ListingId('listing-1'));
      expect(
        find.text(
          'Could not read the photos, so this was filled in from your '
          'wardrobe.',
        ),
        findsOneWidget,
      );
      // A usable draft, made from the garment alone.
      final listing = (await h.listings.all()).single;
      expect(listing.itemId, coat.id);
      expect(listing.facts, isNull);
      expect(listing.title, isNotEmpty);
    });

    testWidgets('says the same for a garment with no photographs to read', (
      tester,
    ) async {
      await h.addGarment('a', photo: false);

      await h.open(tester, location: '/sell/from-wardrobe/a');

      expectOnEditor(tester, const ListingId('listing-1'));
      expect(find.textContaining('Could not read the photos'), findsOneWidget);
      expect(h.gateway.described, isEmpty);
    });

    testWidgets('opens the listing already started, and says so', (
      tester,
    ) async {
      final coat = await h.addGarment('a', name: 'Wool coat');
      await h.listings.save(
        Listing(
          id: const ListingId('mine'),
          itemId: coat.id,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          title: 'Already started',
        ),
      );

      await h.open(tester, location: '/sell/from-wardrobe/a');

      expectOnEditor(tester, const ListingId('mine'));
      expect(
        find.text('Opened the listing already started for this garment.'),
        findsOneWidget,
      );
      // Not another, and the server was not asked.
      expect(h.listings.length, 1);
      expect(h.gateway.described, isEmpty);
    });

    testWidgets('does the same for one that is up for sale', (tester) async {
      final coat = await h.addGarment('a', name: 'Wool coat');
      await h.listings.save(
        Listing(
          id: const ListingId('up'),
          itemId: coat.id,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          title: 'On Depop',
        ).markListed(DateTime.utc(2026, 10, 2)),
      );

      await h.open(tester, location: '/sell/from-wardrobe/a');

      expectOnEditor(tester, const ListingId('up'));
      expect(h.listings.length, 1);
    });

    testWidgets('makes a new one for a garment whose last listing sold', (
      tester,
    ) async {
      final coat = await h.addGarment('a', name: 'Wool coat');
      await h.listings.save(
        Listing(
          id: const ListingId('old'),
          itemId: coat.id,
          createdAt: DateTime.utc(2026, 9, 1),
          updatedAt: DateTime.utc(2026, 9, 1),
        ).markSold(DateTime.utc(2026, 9, 20), priceCents: 2800),
      );

      await h.open(tester, location: '/sell/from-wardrobe/a');

      expectOnEditor(tester, const ListingId('listing-1'));
      expect(h.listings.length, 2);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a garment that is not there says so and makes nothing', (
      tester,
    ) async {
      await h.open(tester, location: '/sell/from-wardrobe/ghost');

      // The words the stain screen uses for the same thing.
      expect(
        find.text('That item is no longer in your wardrobe.'),
        findsOneWidget,
      );
      expect(find.byType(ListingEditorScreen), findsNothing);
      expect(h.listings.length, 0);
      expect(h.gateway.described, isEmpty);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(PickGarmentScreen), findsOneWidget);
    });

    testWidgets('nor one that was deleted', (tester) async {
      await h.addGarment('a', lifecycle: LifecycleState.removed);

      await h.open(tester, location: '/sell/from-wardrobe/a');

      expect(
        find.text('That item is no longer in your wardrobe.'),
        findsOneWidget,
      );
      expect(h.listings.length, 0);
    });

    testWidgets('a failure that is not the garment\'s can be tried again', (
      tester,
    ) async {
      await h.addGarment('a');
      h.lookupFailure = const FileSystemException('No space left on device');

      await h.open(tester, location: '/sell/from-wardrobe/a');

      expect(find.textContaining('could not be started'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(ListingEditorScreen), findsNothing);

      h.lookupFailure = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expectOnEditor(tester, const ListingId('listing-1'));
    });
  });

  group('Sell this', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
    }

    testWidgets('is in the menu of a garment that is owned', (tester) async {
      await h.addGarment('a', name: 'Wool coat');
      await h.open(tester, location: '/item/a');

      await openMenu(tester);

      expect(find.text('Sell this'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.byIcon(Icons.sell_outlined),
        ),
        findsOneWidget,
      );
    });

    testWidgets('comes above Delete and below the rest', (tester) async {
      await h.addGarment('a', name: 'Wool coat');
      await h.open(tester, location: '/item/a');

      await openMenu(tester);

      expect(top(tester, 'Check for wear'), lessThan(top(tester, 'Sell this')));
      expect(top(tester, 'Sell this'), lessThan(top(tester, 'Delete')));
    });

    testWidgets('is in the menu of a garment in the wash too', (tester) async {
      await h.addGarment('a', lifecycle: LifecycleState.inLaundry);
      await h.open(tester, location: '/item/a');

      await openMenu(tester);

      expect(find.text('Sell this'), findsOneWidget);
    });

    for (final state in [
      LifecycleState.sold,
      LifecycleState.donated,
      LifecycleState.discarded,
      LifecycleState.lost,
    ]) {
      testWidgets('is not in the menu of a garment that is ${state.name}', (
        tester,
      ) async {
        await h.addGarment('a', name: 'Wool coat', lifecycle: state);
        await h.open(tester, location: '/item/a');

        await openMenu(tester);

        expect(find.text('Sell this'), findsNothing);
        // The rest of the menu is as it was.
        expect(find.text('Report wear'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
      });
    }

    testWidgets('reads no listing until it is chosen', (tester) async {
      // The garment page is opened by a great many tests that override the
      // wardrobe and nothing else, so it must not reach for the listings.
      await h.addGarment('a', name: 'Wool coat');
      await h.open(tester, location: '/item/a');

      await openMenu(tester);

      expect(h.app.exists(listingRepositoryProvider), isFalse);
      expect(h.app.exists(listingsProvider), isFalse);
    });

    testWidgets('opens the garment\'s listing', (tester) async {
      final coat = await h.addGarment('a', name: 'Wool coat');
      await h.open(tester, location: '/item/a');

      await openMenu(tester);
      await tester.tap(find.text('Sell this'));
      await tester.pumpAndSettle();

      expectOnEditor(tester, const ListingId('listing-1'));
      expect((await h.listings.all()).single.itemId, coat.id);
    });

    testWidgets('Back from the listing is the garment', (tester) async {
      await h.addGarment('a', name: 'Wool coat');
      await h.open(tester, location: '/item/a');
      await openMenu(tester);
      await tester.tap(find.text('Sell this'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(find.byType(StartFromGarmentScreen), findsNothing);
    });

    testWidgets('pressed twice opens the same listing and not a second', (
      tester,
    ) async {
      await h.addGarment('a', name: 'Wool coat');
      await h.open(tester, location: '/item/a');

      // The first time: a listing is made.
      await openMenu(tester);
      await tester.tap(find.text('Sell this'));
      await tester.pumpAndSettle();
      final first = tester
          .widget<ListingEditorScreen>(find.byType(ListingEditorScreen))
          .id;
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // The second: the same one, and the server is not asked again.
      await openMenu(tester);
      await tester.tap(find.text('Sell this'));
      await tester.pumpAndSettle();

      expectOnEditor(tester, first);
      expect(h.listings.length, 1);
      expect(h.gateway.described, hasLength(1));
      expect(
        find.text('Opened the listing already started for this garment.'),
        findsOneWidget,
      );
    });
  });

  group('on a small phone at a large text size', () {
    const phone = Size(320, 640);
    const scale = 1.6;

    Future<void> scrollThrough(WidgetTester tester) async {
      expect(tester.takeException(), isNull);
      final list = find.byType(Scrollable).first;
      for (var step = 0; step < 14; step++) {
        await tester.drag(list, const Offset(0, -240));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after scroll $step');
      }
    }

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

    testWidgets('the picker lays out, with long names', (tester) async {
      for (var i = 0; i < 6; i++) {
        await h.addGarment(
          'g$i',
          name:
              'Vintage oversized washed-out charcoal merino wool crewneck '
              'sweater number $i',
          worn: i,
          lastWornDaysAgo: i == 0 ? null : 30 * i,
        );
      }

      await openPicker(tester, size: phone, textScale: scale);

      await scrollThrough(tester);
    });

    testWidgets('the empty picker lays out', (tester) async {
      await openPicker(tester, size: phone, textScale: scale);

      expect(tester.takeException(), isNull);
      expectWhole(tester, find.text('Nothing in your wardrobe yet'));
    });

    testWidgets('the wait, with its sleeping-server line, lays out', (
      tester,
    ) async {
      await h.addGarment('a');
      h.gateway.hold = Completer<void>();

      await h.open(
        tester,
        location: '/sell/from-wardrobe/a',
        size: phone,
        textScale: scale,
        settle: false,
      );
      await tester.pump(wakingAfter + const Duration(seconds: 1));

      expect(find.textContaining('The server sleeps'), findsOneWidget);
      expect(tester.takeException(), isNull);
      h.gateway.hold!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a garment that is not there lays out', (tester) async {
      await h.open(
        tester,
        location: '/sell/from-wardrobe/ghost',
        size: phone,
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      expectWhole(
        tester,
        find.text('That item is no longer in your wardrobe.'),
      );
    });

    testWidgets('the garment\'s menu, with Sell this in it, lays out', (
      tester,
    ) async {
      await h.addGarment('a', name: 'Wool coat');
      await h.open(tester, location: '/item/a', size: phone, textScale: scale);

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Sell this'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
