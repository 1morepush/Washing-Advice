/// The photographs of a listing: the strip, looking at one, adding another,
/// and which ones are still missing.
///
/// Photographs are the part of a listing a buyer decides on, and the part the
/// app can least check for itself: it cannot tell a good photograph from a
/// blurred one. What it can do is know which shots a buyer asks for, and say
/// which are not there. So these hold that line, the order the photographs are
/// shown in, and that a photograph that is added is both kept and on the
/// listing, with what it is of.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/features/sell/editor/photo_views.dart';
import 'package:washing_advice/features/sell/editor/photos_section.dart';

import '../../support/photos.dart';
import 'listing_editor_harness.dart';

void main() {
  /// Real pictures in the store, under the names [shots] are given.
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

  ListingPhoto photo(ListingShot shot) =>
      ListingPhoto(uri: 'wa-memory:${shot.name}', shot: shot);

  /// A camera that hands back one photograph.
  FixedImageCaptureSource camera() => FixedImageCaptureSource([
    ScanImage(bytes: Uint8List.fromList([1, 2, 3])),
  ]);

  Finder strip() => find.byType(PhotosSection);

  Future<void> saved(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 1));

  group('the strip', () {
    testWidgets('shows every photograph, in order, with what it is of', (
      tester,
    ) async {
      final names = ['cover', 'brandTag', 'back'];
      await openEditor(
        tester,
        listing: sampleListing(
          photos: [
            photo(ListingShot.cover),
            photo(ListingShot.brandTag),
            photo(ListingShot.back),
          ],
        ),
        storedImages: await pictures(tester, names),
        size: tallScreen,
      );
      await settleImages(tester);

      final captions = tester
          .widgetList<Text>(
            find.descendant(of: strip(), matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .whereType<String>()
          .where((text) => ['Cover', 'Brand tag', 'Back'].contains(text))
          .toList();
      expect(captions, ['Cover', 'Brand tag', 'Back']);
      expect(
        find.text('3 of 8. The first one is the cover buyers see first.'),
        findsOneWidget,
      );
      // And they are drawn, not stood in for.
      expect(
        find.descendant(of: strip(), matching: find.byType(Image)),
        findsNWidgets(3),
      );
    });

    testWidgets('stands in a silhouette for a photograph that is gone', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(photos: [photo(ListingShot.cover)]),
        size: tallScreen,
      );

      expect(find.byType(PhotoSilhouette), findsOneWidget);
    });

    testWidgets('asks for the cover first when there are none', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(flaws: const []),
        size: tallScreen,
      );

      expect(find.text('No photos yet. Add the cover first.'), findsOneWidget);
    });
  });

  group('the shots buyers ask for', () {
    testWidgets('are named when they are missing, with why', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(
          flaws: const [],
          photos: [photo(ListingShot.cover), photo(ListingShot.brandTag)],
        ),
        size: tallScreen,
      );

      expect(
        find.text('Missing: back, size label — buyers ask for these'),
        findsOneWidget,
      );
    });

    testWidgets('all four are missing from a listing with no photographs', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(flaws: const []),
        size: tallScreen,
      );

      expect(
        find.text(
          'Missing: cover, back, brand tag, size label — buyers ask for these',
        ),
        findsOneWidget,
      );
    });

    testWidgets('include a flaw, when flaws are listed and none is pictured', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          photos: [
            photo(ListingShot.cover),
            photo(ListingShot.back),
            photo(ListingShot.brandTag),
            photo(ListingShot.sizeLabel),
          ],
        ),
        size: tallScreen,
      );

      expect(find.text('Missing: flaw — buyers ask for these'), findsOneWidget);
    });

    testWidgets('are not mentioned when none is missing', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(
          photos: [
            for (final shot in [
              ListingShot.cover,
              ListingShot.back,
              ListingShot.brandTag,
              ListingShot.sizeLabel,
              ListingShot.flaw,
            ])
              photo(shot),
          ],
        ),
        size: tallScreen,
      );

      expect(find.textContaining('Missing:'), findsNothing);
    });
  });

  group('looking at one', () {
    testWidgets('shows it large, and pages through the rest', (tester) async {
      final names = ['cover', 'brandTag', 'back'];
      await openEditor(
        tester,
        listing: sampleListing(
          photos: [
            photo(ListingShot.cover),
            photo(ListingShot.brandTag),
            photo(ListingShot.back),
          ],
        ),
        storedImages: await pictures(tester, names),
        size: tallScreen,
      );
      await settleImages(tester);

      await tester.tap(find.text('Brand tag'));
      await tester.pumpAndSettle();

      expect(find.byType(ListingPhotoPager), findsOneWidget);
      expect(find.text('Brand tag · 2 of 3'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsWidgets);

      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Back · 3 of 3'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Cover · 1 of 3'), findsOneWidget);
    });

    testWidgets('closes back to the listing, which is as it was', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(photos: [photo(ListingShot.cover)]),
        size: tallScreen,
      );

      await tester.tap(find.text('Cover'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      expect(find.byType(ListingPhotoPager), findsNothing);
      expect(find.text('Photos'), findsOneWidget);
      expect((await app.stored('draft-1'))!.photos, hasLength(1));
    });
  });

  group('adding one', () {
    testWidgets('asks what it is of, with the shots buyers want first', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          flaws: const [],
          photos: [photo(ListingShot.cover), photo(ListingShot.brandTag)],
        ),
        camera: camera(),
        size: tallScreen,
      );

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();

      expect(find.text('What is the photo of?'), findsOneWidget);
      expect(find.text('Buyers are waiting for these'), findsOneWidget);
      expect(find.text('Anything else'), findsOneWidget);
      // Each with the reason a buyer wants it.
      expect(find.text(ListingShot.back.why), findsOneWidget);
      expect(find.text(ListingShot.sizeLabel.why), findsOneWidget);
      expect(find.text(ListingShot.careLabel.why), findsOneWidget);

      // The two that are missing are above everything else.
      final titles = tester
          .widgetList<ListTile>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(ListTile),
            ),
          )
          .map((tile) => (tile.title! as Text).data)
          .toList();
      expect(titles.take(2), ['Back', 'Size label']);
      expect(titles, hasLength(ListingShot.values.length));
    });

    testWidgets('keeps the photograph, and puts it on the listing', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(
          flaws: const [],
          photos: [photo(ListingShot.cover), photo(ListingShot.brandTag)],
        ),
        camera: camera(),
        size: tallScreen,
      );

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();
      await saved(tester);

      // In the store, named for the listing and the shot.
      expect(app.images.length, 1);
      final stored = (await app.stored('draft-1'))!;
      expect(stored.photos.map((p) => p.shot), [
        ListingShot.cover,
        ListingShot.brandTag,
        ListingShot.back,
      ]);
      expect(stored.photos.last.uri, startsWith('wa-memory:draft-1-back-'));
      expect(await app.images.read(stored.photos.last.uri), [1, 2, 3]);
      // And in the strip, and off the list of what is missing.
      expect(
        find.text('3 of 8. The first one is the cover buyers see first.'),
        findsOneWidget,
      );
      expect(
        find.text('Missing: size label — buyers ask for these'),
        findsOneWidget,
      );
    });

    testWidgets('puts a cover first', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(
          flaws: const [],
          photos: [photo(ListingShot.back)],
        ),
        camera: camera(),
        size: tallScreen,
      );

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cover').last);
      await tester.pumpAndSettle();
      await saved(tester);

      final stored = (await app.stored('draft-1'))!;
      expect(stored.photos.map((p) => p.shot), [
        ListingShot.cover,
        ListingShot.back,
      ]);
    });

    testWidgets('does nothing when the person changes their mind at the '
        'picker', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(photos: [photo(ListingShot.cover)]),
        camera: camera(),
        size: tallScreen,
      );

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('What is the photo of?'), findsNothing);
      expect(app.images.length, 0);
      expect((await app.stored('draft-1'))!.photos, hasLength(1));
    });

    testWidgets('does nothing when the person backs out of the camera', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(photos: [photo(ListingShot.cover)]),
        camera: FixedImageCaptureSource(const []),
        size: tallScreen,
      );

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();

      expect(app.images.length, 0);
      expect(find.textContaining('could not be saved'), findsNothing);
      expect((await app.stored('draft-1'))!.photos, hasLength(1));
    });

    testWidgets('says why when the camera cannot be opened', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(photos: [photo(ListingShot.cover)]),
        camera: _BrokenCamera(),
        size: tallScreen,
      );

      await tester.tap(find.text('Add photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back').last);
      await tester.pumpAndSettle();

      expect(find.text('The camera is switched off.'), findsOneWidget);
      // And the button is there to try again.
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add photo'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('stops at what Depop takes', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(
          photos: [
            for (var i = 0; i < depopPhotoLimit; i++)
              ListingPhoto(uri: 'wa-memory:p$i', shot: ListingShot.other),
          ],
        ),
        camera: camera(),
        size: tallScreen,
      );

      expect(
        find.text('8 of 8. The first one is the cover buyers see first.'),
        findsOneWidget,
      );
      expect(find.text('Depop takes up to 8 photos.'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Add photo'),
            )
            .onPressed,
        isNull,
      );
    });
  });
}

/// A camera that cannot be opened.
class _BrokenCamera implements ImageCaptureSource {
  @override
  Future<ScanImage?> capture() async => throw const CaptureFailure(
    'The camera is switched off.',
    isRetryable: false,
  );

  @override
  Future<List<ScanImage>> pickMultiple() async => const [];
}
