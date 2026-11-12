/// Taking photographs off a listing, choosing the cover, and putting them in
/// order.
///
/// What these hold is the part a person would notice going wrong: a picture
/// deleted that a garment still shows, a cover that is not first, a change
/// that was made and then lost because Back was pressed a moment too soon.
/// The rules for what a move does to the cover are the core's and are tested
/// there; here it is that the screen asks them, says what will happen, and
/// stores the answer.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/features/sell/editor/photo_views.dart';

import '../../support/fixtures.dart';
import '../../support/photos.dart';
import 'listing_editor_harness.dart';

void main() {
  ListingPhoto photo(String name, ListingShot shot) =>
      ListingPhoto(uri: 'wa-memory:$name', shot: shot);

  Future<Map<String, Uint8List>> pictures(
    WidgetTester tester,
    List<String> names,
  ) async {
    final stored = <String, Uint8List>{};
    await tester.runAsync(() async {
      for (final name in names) {
        stored[name] = await pngBytes(300, 400);
      }
    });
    return stored;
  }

  /// A cover, a back and a brand tag, all with pictures.
  Future<EditorApp> three(
    WidgetTester tester, {
    Size size = tallScreen,
    double textScale = 1,
  }) async => openEditor(
    tester,
    listing: sampleListing(
      flaws: const [],
      photos: [
        photo('cover', ListingShot.cover),
        photo('back', ListingShot.back),
        photo('tag', ListingShot.brandTag),
      ],
    ),
    storedImages: await pictures(tester, ['cover', 'back', 'tag']),
    size: size,
    textScale: textScale,
  );

  Future<void> saved(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  Finder options(int index) => find.byKey(ValueKey('photo-options-$index'));

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<List<String>> storedOrder(EditorApp app) async => [
    for (final p in (await app.stored('draft-1'))!.photos)
      '${p.uri.substring(10)}:${p.shot.name}',
  ];

  group('removing a photo from the strip', () {
    testWidgets('asks first, and says what will happen', (tester) async {
      final app = await three(tester);

      await tester.tap(options(1));
      await tester.pumpAndSettle();
      await choose(tester, 'Remove photo');

      expect(find.text('Remove the back photo?'), findsOneWidget);
      expect(find.textContaining('deleted from this phone'), findsOneWidget);

      await choose(tester, 'Keep it');
      await saved(tester);

      expect(await storedOrder(app), [
        'cover:cover',
        'back:back',
        'tag:brandTag',
      ]);
      expect(app.images.length, 3);
    });

    testWidgets('takes it off the listing and deletes its picture', (
      tester,
    ) async {
      final app = await three(tester);

      await tester.tap(options(1));
      await tester.pumpAndSettle();
      await choose(tester, 'Remove photo');
      await choose(tester, 'Remove');
      await saved(tester);

      expect(await storedOrder(app), ['cover:cover', 'tag:brandTag']);
      expect(await app.images.read('wa-memory:back'), isNull);
      expect(app.images.length, 2);
      // And the strip and the list of what is missing follow.
      expect(
        find.text('2 of 8. The first one is the cover buyers see first.'),
        findsOneWidget,
      );
      expect(
        find.text('Missing: back, size label — buyers ask for these'),
        findsOneWidget,
      );
    });

    testWidgets('the cover makes the next photo the cover', (tester) async {
      final app = await three(tester);

      await tester.tap(options(0));
      await tester.pumpAndSettle();
      await choose(tester, 'Remove photo');
      expect(
        find.textContaining('The next photo becomes the cover.'),
        findsOneWidget,
      );
      await choose(tester, 'Remove');
      await saved(tester);

      expect(await storedOrder(app), ['back:cover', 'tag:brandTag']);
      expect(await app.images.read('wa-memory:cover'), isNull);
      // The back was the back; now it is the cover, and a back is wanted.
      expect(
        find.text('Missing: back, size label — buyers ask for these'),
        findsOneWidget,
      );
    });

    testWidgets('the last one leaves none, and asks for the cover', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(
          flaws: const [],
          photos: [photo('only', ListingShot.cover)],
        ),
        storedImages: await pictures(tester, ['only']),
        size: tallScreen,
      );

      await tester.tap(options(0));
      await tester.pumpAndSettle();
      await choose(tester, 'Remove photo');
      await choose(tester, 'Remove');
      await saved(tester);

      expect((await app.stored('draft-1'))!.photos, isEmpty);
      expect(find.text('No photos yet. Add the cover first.'), findsOneWidget);
    });

    testWidgets('keeps a picture the garment also holds', (tester) async {
      final garment = confidentItem(id: 'sweat', name: 'Grey sweatshirt')
          .copyWith(
            photos: PhotoSet([
              ItemPhoto(
                uri: 'wa-memory:g-front',
                role: PhotoRole.front,
                capturedAt: DateTime.utc(2026, 1, 1),
              ),
            ]),
          );
      final app = await openEditor(
        tester,
        listing: sampleListing(
          flaws: const [],
          itemId: garment.id,
          photos: [
            photo('g-front', ListingShot.cover),
            photo('own-back', ListingShot.back),
          ],
        ),
        garments: [garment],
        storedImages: await pictures(tester, ['g-front', 'own-back']),
        size: tallScreen,
      );

      // The garment's: said so, and kept.
      await tester.tap(options(0));
      await tester.pumpAndSettle();
      await choose(tester, 'Remove photo');
      expect(find.textContaining('stays with the garment'), findsOneWidget);
      expect(find.textContaining('deleted from this phone'), findsNothing);
      await choose(tester, 'Remove');
      await saved(tester);

      expect(await storedOrder(app), ['own-back:cover']);
      expect(await app.images.read('wa-memory:g-front'), isNotNull);

      // The listing's own is deleted.
      await tester.tap(options(0));
      await tester.pumpAndSettle();
      await choose(tester, 'Remove photo');
      expect(find.textContaining('deleted from this phone'), findsOneWidget);
      await choose(tester, 'Remove');
      await saved(tester);

      expect(await app.images.read('wa-memory:own-back'), isNull);
      expect(await app.images.read('wa-memory:g-front'), isNotNull);
    });
  });

  group('choosing the cover and the order', () {
    testWidgets('make this the cover puts it first and demotes the old one', (
      tester,
    ) async {
      final app = await three(tester);

      await tester.tap(options(2));
      await tester.pumpAndSettle();
      await choose(tester, 'Make this the cover');
      await saved(tester);

      expect(await storedOrder(app), ['tag:cover', 'cover:other', 'back:back']);
      // Nothing was deleted by reordering.
      expect(app.images.length, 3);
    });

    testWidgets('does not offer what would do nothing', (tester) async {
      await three(tester);

      await tester.tap(options(0));
      await tester.pumpAndSettle();

      expect(find.text('Make this the cover'), findsNothing);
      expect(find.text('Move earlier'), findsNothing);
      expect(find.text('Move later'), findsOneWidget);
      expect(find.text('Remove photo'), findsOneWidget);
    });

    testWidgets('move later and move earlier shift it by one', (tester) async {
      final app = await three(tester);

      await tester.tap(options(1));
      await tester.pumpAndSettle();
      await choose(tester, 'Move later');
      await saved(tester);
      expect(await storedOrder(app), [
        'cover:cover',
        'tag:brandTag',
        'back:back',
      ]);

      await tester.tap(options(2));
      await tester.pumpAndSettle();
      await choose(tester, 'Move earlier');
      await saved(tester);
      expect(await storedOrder(app), [
        'cover:cover',
        'back:back',
        'tag:brandTag',
      ]);
    });

    testWidgets('moving the second earlier makes it the cover', (tester) async {
      final app = await three(tester);

      await tester.tap(options(1));
      await tester.pumpAndSettle();
      expect(find.text('It becomes the cover.'), findsOneWidget);
      await choose(tester, 'Move earlier');
      await saved(tester);

      expect(await storedOrder(app), [
        'back:cover',
        'cover:other',
        'tag:brandTag',
      ]);
    });

    testWidgets('a change is stored even if Back is pressed at once', (
      tester,
    ) async {
      final app = await three(tester);

      await tester.tap(options(2));
      await tester.pumpAndSettle();
      await choose(tester, 'Make this the cover');
      // No pause for the timer: straight out.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect((await storedOrder(app)).first, 'tag:cover');
    });

    testWidgets('a removal is stored even if Back is pressed at once', (
      tester,
    ) async {
      final app = await three(tester);

      await tester.tap(options(1));
      await tester.pumpAndSettle();
      await choose(tester, 'Remove photo');
      await choose(tester, 'Remove');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(await storedOrder(app), ['cover:cover', 'tag:brandTag']);
    });
  });

  group('in the full-screen viewer', () {
    Future<void> open(WidgetTester tester, String caption) async {
      await settleImages(tester);
      await tester.tap(find.text(caption));
      await tester.pumpAndSettle();
      expect(find.byType(ListingPhotoPager), findsOneWidget);
    }

    testWidgets('make cover follows the photo to the front', (tester) async {
      final app = await three(tester);
      await open(tester, 'Brand tag');
      expect(find.text('Brand tag · 3 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pager-makeCover')));
      await tester.pumpAndSettle();
      await saved(tester);

      expect(find.text('Cover · 1 of 3'), findsOneWidget);
      expect(await storedOrder(app), ['tag:cover', 'cover:other', 'back:back']);
      // The first photo has nothing to move earlier to, or to be made.
      expect(find.byKey(const ValueKey('pager-earlier')), findsNothing);
      expect(find.byKey(const ValueKey('pager-makeCover')), findsNothing);
    });

    testWidgets('move later keeps looking at the same photo', (tester) async {
      final app = await three(tester);
      await open(tester, 'Back');

      await tester.tap(find.byKey(const ValueKey('pager-later')));
      await tester.pumpAndSettle();
      await saved(tester);

      expect(find.text('Back · 3 of 3'), findsOneWidget);
      expect(await storedOrder(app), [
        'cover:cover',
        'tag:brandTag',
        'back:back',
      ]);
    });

    testWidgets('remove asks, deletes, and shows the next photo', (
      tester,
    ) async {
      final app = await three(tester);
      await open(tester, 'Back');

      await tester.tap(find.byKey(const ValueKey('pager-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove the back photo?'), findsOneWidget);
      await choose(tester, 'Remove');
      await saved(tester);

      expect(find.byType(ListingPhotoPager), findsOneWidget);
      expect(find.text('Brand tag · 2 of 2'), findsOneWidget);
      expect(await storedOrder(app), ['cover:cover', 'tag:brandTag']);
      expect(await app.images.read('wa-memory:back'), isNull);
    });

    testWidgets('removing the only photo closes the viewer', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(
          flaws: const [],
          photos: [photo('only', ListingShot.cover)],
        ),
        storedImages: await pictures(tester, ['only']),
        size: tallScreen,
      );
      await open(tester, 'Cover');

      await tester.tap(find.byKey(const ValueKey('pager-remove')));
      await tester.pumpAndSettle();
      await choose(tester, 'Remove');
      await saved(tester);

      expect(find.byType(ListingPhotoPager), findsNothing);
      expect(find.text('No photos yet. Add the cover first.'), findsOneWidget);
    });
  });

  group('on a small phone with large text', () {
    setUpAll(loadAppFont);

    for (final appearance in [Appearance.light, Appearance.amoled]) {
      testWidgets('the strip, the sheet, the dialog and the viewer fit in '
          '${appearance.name}', (tester) async {
        await openEditor(
          tester,
          listing: sampleListing(
            photos: [
              for (final shot in ListingShot.values) photo(shot.name, shot),
            ],
          ),
          size: const Size(320, 640),
          textScale: 1.6,
          appearance: appearance,
        );

        await tester.ensureVisible(options(2));
        await tester.pumpAndSettle();
        await tester.tap(options(2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Remove photo'));
        await choose(tester, 'Remove photo');
        expect(find.text('Remove the brand tag photo?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await choose(tester, 'Keep it');

        await tester.ensureVisible(find.text('Care label'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Care label'));
        await tester.pumpAndSettle();
        expect(find.byType(ListingPhotoPager), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final key in [
          'pager-makeCover',
          'pager-earlier',
          'pager-later',
          'pager-remove',
        ]) {
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
        }
      });
    }
  });
}
