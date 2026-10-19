/// The editor on a small phone with large text, in every theme.
///
/// The listing editor is the longest screen in the app and the one most likely
/// to be used by somebody holding a phone in one hand over a pile of clothes.
/// Earlier screens were caught out on a 320 px phone with the system text
/// enlarged: pills that overflowed, labels broken in the middle of a word, a
/// field scrolled out of reach by the keyboard, two buttons in a row that
/// wrapped to different heights.
///
/// So this opens the editor on a listing written to be as wordy as a real one
/// can be, on a 320 x 640 phone at 1.6 times text, and scrolls it from top to
/// bottom, in Light, Dark and the true black. A layout that does not fit is an
/// exception, which fails the test; the real typeface is loaded because the
/// test one draws every letter a full em wide and would fail on anything.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/theme.dart';

import '../../support/fixtures.dart';
import 'listing_editor_harness.dart';

void main() {
  setUpAll(loadAppFont);

  const phone = Size(320, 640);
  const largeText = 1.6;

  /// A listing with something in every part, and all of it as long as it gets.
  Listing wordy({
    ListingStatus status = ListingStatus.draft,
    ItemId? itemId,
    ItemType type = ItemType.sweatshirt,
  }) {
    final now = DateTime.now().toUtc();
    return sampleListing(
      title:
          'Nike vintage 90s embroidered swoosh crewneck sweatshirt heather '
          'grey oversized fit size medium',
      itemType: type,
      itemId: itemId,
      status: status,
      listedAt: status == ListingStatus.draft
          ? null
          : now.subtract(const Duration(days: 20)),
      soldAt: status == ListingStatus.sold
          ? now.subtract(const Duration(days: 2))
          : null,
      soldPriceCents: status == ListingStatus.sold ? 123456 : null,
      priceCents: 500,
      department: null,
      colours: const [DepopColour.burgundy, DepopColour.multi],
      flaws: const [
        'a small pale mark on the left cuff that did not wash out, pictured',
        'light pilling under both arms and across the back of the shoulders',
        'the neck ribbing is slightly stretched from being worn a lot',
      ],
      measurements: const Measurements(
        pitToPitIn: 22.25,
        lengthIn: 27.5,
        waistIn: 32,
        inseamIn: 30,
      ),
      typedComparableCents: const [3250, 2800, 4500, 2900, 3100, 123456],
      typedComparablesSold: true,
      photos: [
        for (final shot in ListingShot.values)
          ListingPhoto(uri: 'wa-memory:${shot.name}', shot: shot),
        const ListingPhoto(uri: 'wa-memory:more', shot: ListingShot.flaw),
      ],
      priceSearch: sampleSearch(
        at: now.subtract(const Duration(days: 40)),
        comparables: [
          for (var i = 0; i < 4; i++)
            SaleComparable(
              title:
                  'Vintage Nike 90s embroidered swoosh heather grey crewneck '
                  'sweatshirt size medium in very good condition #$i',
              url: Uri.parse('https://www.depop.com/products/long-$i/'),
              priceCents: 123456,
              sold: i.isEven ? true : (i == 1 ? false : null),
              condition: 'Used - Excellent condition, barely worn at all',
              match: i.isEven ? ComparableMatch.same : ComparableMatch.similar,
              why:
                  'Same Nike crewneck in the same heather grey colour, with '
                  'the same embroidered swoosh on the chest',
            ),
        ],
        retail: [
          RetailReference(
            title:
                'Nike Sportswear Club Fleece Crew-Neck Sweatshirt in Dark '
                'Grey Heather',
            url: Uri.parse('https://www.nike.com/t/club-fleece-crew'),
            priceCents: 123456,
            match: ComparableMatch.similar,
            seller: 'a-very-long-shop-name-dot-example.com',
          ),
        ],
        excluded: const ExcludedCounts(
          notUsd: 12,
          unverifiedPrice: 345,
          notComparable: 6789,
        ),
      ),
    );
  }

  /// Whether every word in [finder]'s text is whole: the paragraph is at least
  /// as wide as its widest word, so nothing was broken inside one.
  void expectWhole(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder.first);
    expect(paragraph.didExceedMaxLines, isFalse);
    for (final word in paragraph.text.toPlainText().split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
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

  /// The editor's own scroll position.
  ScrollPosition editorScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  /// Scrolls to the end in steps of most of a screen, looking at every one.
  Future<int> scrollThrough(WidgetTester tester) async {
    final position = editorScroll(tester);
    var steps = 0;
    position.jumpTo(0);
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'at the top');

    while (position.pixels < position.maxScrollExtent) {
      position.jumpTo(
        (position.pixels + 400).clamp(0, position.maxScrollExtent),
      );
      await tester.pump();
      steps++;
      expect(
        tester.takeException(),
        isNull,
        reason: 'after scrolling to ${position.pixels}',
      );
    }
    return steps;
  }

  for (final appearance in [
    Appearance.light,
    Appearance.dark,
    Appearance.amoled,
  ]) {
    testWidgets('a draft scrolls through at 320 px and 1.6x text in '
        '${appearance.name}', (tester) async {
      await openEditor(
        tester,
        listing: wordy(),
        size: phone,
        textScale: largeText,
        appearance: appearance,
      );

      final steps = await scrollThrough(tester);

      // It really is long: this was not a screen that fitted without scrolling.
      expect(steps, greaterThan(10));
      expect(tester.takeException(), isNull);
      // And it settles after, as it would on a phone.
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('a listing that is up, and needs a refresh, scrolls through', (
    tester,
  ) async {
    await openEditor(
      tester,
      listing: wordy(status: ListingStatus.listed),
      size: phone,
      textScale: largeText,
    );

    await scrollThrough(tester);

    expect(find.text('Listed 20 days ago'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sale of a garment with a long name scrolls through', (
    tester,
  ) async {
    final garment = confidentItem(
      id: 'sweat',
      name: 'Heather grey Nike vintage embroidered swoosh crewneck sweatshirt',
      type: ItemType.sweatshirt,
    );
    await openEditor(
      tester,
      listing: wordy(status: ListingStatus.sold, itemId: garment.id),
      garments: [garment],
      size: phone,
      textScale: largeText,
      appearance: Appearance.dark,
    );

    await scrollThrough(tester);

    expect(
      find.textContaining('Mark the Heather grey Nike vintage'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty listing scrolls through', (tester) async {
    final blank = Listing(
      id: const ListingId('blank'),
      createdAt: DateTime.utc(2026, 10, 15),
      updatedAt: DateTime.utc(2026, 10, 15),
    );
    await openEditor(tester, listing: blank, size: phone, textScale: largeText);

    await scrollThrough(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('a listing for a blouse with no department scrolls through', (
    tester,
  ) async {
    await openEditor(
      tester,
      listing: wordy(type: ItemType.blouse),
      size: phone,
      textScale: largeText,
    );

    await scrollThrough(tester);

    expect(
      find.text('Pick Men or Women to see where Depop files this.'),
      findsOneWidget,
    );
  });

  testWidgets('holds at twice the text size, too', (tester) async {
    await openEditor(tester, listing: wordy(), size: phone, textScale: 2);

    await scrollThrough(tester);
  });

  testWidgets('keeps its words whole at 1.6x', (tester) async {
    await openEditor(
      tester,
      listing: wordy(),
      size: phone,
      textScale: largeText,
    );
    final position = editorScroll(tester);

    for (final label in [
      'Copy description',
      'Add photo',
      'Look up prices',
      'Copy category',
      'What do these mean?',
      'Delete listing',
      "I've posted it",
    ]) {
      final finder = find.text(label, skipOffstage: false);
      expect(finder, findsOneWidget, reason: label);
      await tester.ensureVisible(finder);
      await tester.pump();
      expectWhole(tester, finder);
    }
    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('shows the same price and net at the top of a price tile as '
      'the figures in the lists', (tester) async {
    // The widest figure there is, $1,234.56, beside a long title.
    await openEditor(
      tester,
      listing: wordy(),
      size: phone,
      textScale: largeText,
    );

    final price = find.text(r'$1,234.56', skipOffstage: false);
    expect(price, findsWidgets);
    await tester.ensureVisible(price.first);
    await tester.pump();
    expectWhole(tester, price.first);
    expect(tester.takeException(), isNull);
  });

  group('with the keyboard up', () {
    testWidgets('the field being typed in stays in view', (tester) async {
      await openEditor(
        tester,
        listing: wordy(),
        size: phone,
        textScale: largeText,
      );
      final brand = find.widgetWithText(TextField, 'Brand');
      await tester.ensureVisible(brand);
      await tester.pump();

      // The keyboard, a little under half the screen as on a phone.
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.tap(brand);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final field = tester.getRect(brand);
      expect(field.top, greaterThanOrEqualTo(0));
      expect(field.bottom, lessThanOrEqualTo(phone.height - 280));

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('does not leave a gap under the last of the page', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: wordy(),
        size: phone,
        textScale: largeText,
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final position = editorScroll(tester);
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();

      // The end of the page sits on the keyboard, not above empty space: what
      // is visible is the last of the page and its own bottom padding, and
      // no more.
      final delete = tester.getRect(
        find.text('Delete listing', skipOffstage: false),
      );
      expect(delete.bottom, lessThanOrEqualTo(phone.height - 280));
      expect(delete.bottom, greaterThan(phone.height - 280 - 120));

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
    });
  });
}
