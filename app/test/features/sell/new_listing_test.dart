/// Starting a listing from photographs.
///
/// The camera and the server are the two things that cannot be had in a test,
/// and both are replaced: a camera that hands back numbered photographs, and a
/// server that answers, fails or is slow as it is told to. Everything between —
/// the checklist, the limit, storing the photographs before sending them, the
/// listing the core makes, the editor it opens — is the app's own.
///
/// Most of what matters here is what happens when something goes wrong: the
/// server asleep, the server unable to read a photograph, the camera refused.
/// A seller with a garment in one hand should never be stopped by any of them,
/// and should never have to photograph it twice.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/api/scan_dto.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/features/scan/scan_parts.dart' show ScanThumb;
import 'package:washing_advice/features/sell/listing_editor_screen.dart';
import 'package:washing_advice/features/sell/new_listing_screen.dart';
import 'package:washing_advice/features/sell/sell_screen.dart';

import 'sell_list_harness.dart';

void main() {
  late SellHarness h;

  setUpAll(loadAppFont);
  setUp(() async => h = await SellHarness.create());

  /// Tall enough that every row of the checklist is built and on screen.
  const tall = Size(400, 1900);

  Future<void> openChecklist(
    WidgetTester tester, {
    Size size = tall,
    double textScale = 1,
  }) => h.open(tester, location: '/sell/new', size: size, textScale: textScale);

  Finder row(String name) => find.byKey(ValueKey('shot-$name'));

  /// The picture taken for [shot], when there is one.
  Finder photoIn(String shot) =>
      find.descendant(of: row(shot), matching: find.byType(ScanThumb));

  /// Taps [label] in the row for [shot].
  Future<void> tapIn(WidgetTester tester, String shot, String label) async {
    await tester.tap(
      find.descendant(of: row(shot), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> takeCover(WidgetTester tester) => tapIn(tester, 'cover', 'Take');

  FilledButton write(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Write the listing'),
  );

  Future<void> tapWrite(WidgetTester tester) async {
    await tester.tap(find.text('Write the listing'));
    await tester.pumpAndSettle();
  }

  Future<void> expectOnEditor(WidgetTester tester, ListingId id) async {
    expect(find.byType(ListingEditorScreen), findsOneWidget);
    expect(
      tester.widget<ListingEditorScreen>(find.byType(ListingEditorScreen)).id,
      id,
    );
  }

  group('the checklist', () {
    testWidgets('asks for the cover, the back, the brand tag and the size '
        'label, and says why', (tester) async {
      await openChecklist(tester);

      for (final shot in ListingShot.values.where((s) => s.isChecklist)) {
        expect(find.text(shot.label), findsOneWidget, reason: shot.name);
        // In the core's own words, not a copy of them.
        expect(find.text(shot.why), findsOneWidget, reason: shot.name);
        expect(
          find.descendant(of: row(shot.name), matching: find.text('Take')),
          findsOneWidget,
          reason: shot.name,
        );
      }
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets(
      'asks for no more than those four, and then the optional ones',
      (tester) async {
        await openChecklist(tester);

        expect(find.text('Care label'), findsNothing);
        expect(find.text('Flaws (optional)'), findsOneWidget);
        expect(find.text(ListingShot.flaw.why), findsOneWidget);
        expect(find.text('Add a flaw photo'), findsOneWidget);
        expect(find.text('More photos'), findsOneWidget);
        expect(find.text('Add more photos'), findsOneWidget);
      },
    );

    testWidgets('says nothing is sent yet', (tester) async {
      await openChecklist(tester);

      expect(find.textContaining('Nothing is sent until'), findsOneWidget);
      expect(h.gateway.described, isEmpty);
    });

    testWidgets('counts the photographs against what Depop takes', (
      tester,
    ) async {
      await openChecklist(tester);
      expect(find.text('0 of 8 photos'), findsOneWidget);

      await takeCover(tester);
      expect(find.text('1 of 8 photos'), findsOneWidget);
    });

    testWidgets('shows a photograph once it is taken, and Retake in place of '
        'Take', (tester) async {
      await openChecklist(tester);
      expect(photoIn('cover'), findsNothing);

      await takeCover(tester);

      expect(photoIn('cover'), findsOneWidget);
      expect(
        find.descendant(of: row('cover'), matching: find.text('Retake')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row('cover'), matching: find.text('Take')),
        findsNothing,
      );
      // Only that row.
      expect(photoIn('back'), findsNothing);
    });

    testWidgets('Retake replaces the photograph and is not another one', (
      tester,
    ) async {
      await openChecklist(tester);
      await takeCover(tester);

      await tapIn(tester, 'cover', 'Retake');

      expect(find.text('1 of 8 photos'), findsOneWidget);
      expect(h.camera.taken, 2);
      await tapWrite(tester);
      // The second photograph, and only that.
      expect(h.gateway.described.single.images.map(markOf), ['shot-2']);
    });

    testWidgets('removing a photograph takes it back', (tester) async {
      await openChecklist(tester);
      await takeCover(tester);
      await tapIn(tester, 'back', 'Take');
      expect(find.text('2 of 8 photos'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove the back photo'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 8 photos'), findsOneWidget);
      expect(
        find.descendant(of: row('back'), matching: find.text('Take')),
        findsOneWidget,
      );
      expect(find.byTooltip('Remove the back photo'), findsNothing);
    });

    testWidgets('backing out of the camera changes nothing', (tester) async {
      await openChecklist(tester);
      h.camera.backOut = true;

      await takeCover(tester);

      expect(find.text('0 of 8 photos'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // And it can be tried again.
      await takeCover(tester);
      expect(find.text('1 of 8 photos'), findsOneWidget);
    });

    testWidgets('a camera that will not open says why and keeps what is '
        'there', (tester) async {
      await openChecklist(tester);
      await takeCover(tester);
      h.camera.failure = const CaptureFailure(
        'Washing Advice does not have permission to use the camera. Turn it '
        'on in your phone settings, then try again.',
        isRetryable: false,
      );

      await tapIn(tester, 'back', 'Take');

      expect(find.textContaining('does not have permission'), findsOneWidget);
      expect(find.text('1 of 8 photos'), findsOneWidget);
      expect(photoIn('cover'), findsOneWidget);
    });

    testWidgets('can take several flaws, and take one back', (tester) async {
      await openChecklist(tester);

      await tapIn(tester, 'flaw', 'Add a flaw photo');
      await tapIn(tester, 'flaw', 'Add a flaw photo');
      expect(find.text('2 of 8 photos'), findsOneWidget);
      expect(find.byTooltip('Remove flaw photo 1'), findsOneWidget);
      expect(find.byTooltip('Remove flaw photo 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove flaw photo 1'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 8 photos'), findsOneWidget);
      expect(find.byTooltip('Remove flaw photo'), findsOneWidget);
    });

    testWidgets('Add more photos picks several at once', (tester) async {
      await openChecklist(tester);
      h.camera.picks = [photoOf('p1'), photoOf('p2'), photoOf('p3')];

      await tapIn(tester, 'other', 'Add more photos');

      expect(find.text('3 of 8 photos'), findsOneWidget);
      expect(find.byTooltip('Remove photo 3'), findsOneWidget);
    });

    testWidgets('picking none changes nothing', (tester) async {
      await openChecklist(tester);

      await tapIn(tester, 'other', 'Add more photos');

      expect(find.text('0 of 8 photos'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('the limit Depop sets', () {
    /// Seven photographs: the four asked for, and three flaws.
    Future<void> takeSeven(WidgetTester tester) async {
      for (final shot in ['cover', 'back', 'brandTag', 'sizeLabel']) {
        await tapIn(tester, shot, 'Take');
      }
      for (var i = 0; i < 3; i++) {
        await tapIn(tester, 'flaw', 'Add a flaw photo');
      }
    }

    bool enabled(WidgetTester tester, String shot) =>
        tester
            .widget<FilledButton>(
              find.descendant(
                of: row(shot),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed !=
        null;

    testWidgets('is eight, and says so when it is reached', (tester) async {
      await openChecklist(tester);
      await takeSeven(tester);
      expect(find.textContaining('photos Depop takes'), findsNothing);

      await tapIn(tester, 'flaw', 'Add a flaw photo');

      expect(find.text('8 of 8 photos'), findsOneWidget);
      expect(
        find.text(
          'That is the 8 photos Depop takes. Remove one to add another.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('stops every way of adding another', (tester) async {
      await openChecklist(tester);
      await takeSeven(tester);
      await tapIn(tester, 'flaw', 'Add a flaw photo');

      expect(enabled(tester, 'flaw'), isFalse);
      expect(enabled(tester, 'other'), isFalse);
      // A shot with no photograph yet is a new one too: here every asked-for
      // shot has its photograph, so take the back away to see it.
      await tester.tap(find.byTooltip('Remove the back photo'));
      await tester.pumpAndSettle();
      expect(enabled(tester, 'back'), isTrue);
      await tapIn(tester, 'back', 'Take');
      expect(find.text('8 of 8 photos'), findsOneWidget);
    });

    testWidgets('still lets a shot be retaken, which adds nothing', (
      tester,
    ) async {
      await openChecklist(tester);
      await takeSeven(tester);
      await tapIn(tester, 'flaw', 'Add a flaw photo');

      expect(enabled(tester, 'cover'), isTrue);
      await tapIn(tester, 'cover', 'Retake');

      expect(find.text('8 of 8 photos'), findsOneWidget);
    });

    testWidgets('lets another in when one is taken back', (tester) async {
      await openChecklist(tester);
      await takeSeven(tester);
      await tapIn(tester, 'flaw', 'Add a flaw photo');
      expect(enabled(tester, 'other'), isFalse);

      await tester.tap(find.byTooltip('Remove flaw photo 1'));
      await tester.pumpAndSettle();

      expect(find.textContaining('photos Depop takes'), findsNothing);
      expect(enabled(tester, 'other'), isTrue);
    });

    testWidgets('takes as many of a pick as fit, and says how many did not', (
      tester,
    ) async {
      await openChecklist(tester);
      await takeSeven(tester);
      h.camera.picks = [photoOf('p1'), photoOf('p2'), photoOf('p3')];

      await tapIn(tester, 'other', 'Add more photos');

      expect(find.text('8 of 8 photos'), findsOneWidget);
      expect(
        find.text('Depop takes 8 photos, so 2 were left out.'),
        findsOneWidget,
      );
      // The first of them, not the last.
      await tapWrite(tester);
      final listing = (await h.listings.all()).single;
      expect(listing.photos, hasLength(8));
      expect(markOfBytes(await h.images.read(listing.photos.last.uri)), 'p1');
    });

    testWidgets('says one was left out when it was one', (tester) async {
      await openChecklist(tester);
      await takeSeven(tester);
      h.camera.picks = [photoOf('p1'), photoOf('p2')];

      await tapIn(tester, 'other', 'Add more photos');

      expect(
        find.text('Depop takes 8 photos, so one was left out.'),
        findsOneWidget,
      );
    });

    testWidgets('no more than eight are ever stored, or sent to be read', (
      tester,
    ) async {
      await openChecklist(tester);
      await takeSeven(tester);
      h.camera.picks = [for (var i = 0; i < 6; i++) photoOf('p$i')];
      await tapIn(tester, 'other', 'Add more photos');

      await tapWrite(tester);

      expect(h.images.length, 8);
      expect(h.gateway.described.single.images, hasLength(4));
    });
  });

  group('writing the listing', () {
    testWidgets('is not ready without a cover', (tester) async {
      await openChecklist(tester);

      expect(write(tester).onPressed, isNull);
      expect(
        find.text('Take the cover photo to write the listing.'),
        findsOneWidget,
      );

      // The other shots are not the cover.
      await tapIn(tester, 'back', 'Take');
      await tapIn(tester, 'brandTag', 'Take');
      expect(write(tester).onPressed, isNull);
      expect(h.gateway.described, isEmpty);
    });

    testWidgets('is ready once the cover is taken', (tester) async {
      await openChecklist(tester);

      await takeCover(tester);

      expect(write(tester).onPressed, isNotNull);
      expect(find.textContaining('Take the cover photo'), findsNothing);
    });

    testWidgets('is not ready again if the cover is taken back', (
      tester,
    ) async {
      await openChecklist(tester);
      await takeCover(tester);

      await tester.tap(find.byTooltip('Remove the cover photo'));
      await tester.pumpAndSettle();

      expect(write(tester).onPressed, isNull);
    });

    testWidgets('reads the photographs, makes the draft and opens it', (
      tester,
    ) async {
      await openChecklist(tester);
      await takeCover(tester);
      await tapIn(tester, 'brandTag', 'Take');

      await tapWrite(tester);

      await expectOnEditor(tester, const ListingId('listing-1'));
      // What the server was given, cover first.
      expect(h.gateway.described.single.images.map(markOf), [
        'shot-1',
        'shot-2',
      ]);
      expect(h.gateway.described.single.context, isNull);

      // The listing, as the core makes one from what was read.
      final listing = (await h.listings.all()).single;
      expect(listing.id, const ListingId('listing-1'));
      expect(listing.status, ListingStatus.draft);
      expect(listing.title, h.gateway.facts.title);
      expect(listing.brand, 'Nike');
      expect(listing.itemId, isNull);
      expect(listing.photos.map((p) => p.shot), [
        ListingShot.cover,
        ListingShot.brandTag,
      ]);
      // The photographs are the ones taken, kept on the phone.
      expect(h.images.length, 2);
      expect(
        markOfBytes(await h.images.read(listing.photos.first.uri)),
        'shot-1',
      );
    });

    testWidgets('keeps the listing\'s photographs cover first, whatever order '
        'they were taken in', (tester) async {
      await openChecklist(tester);
      await tapIn(tester, 'back', 'Take'); // shot-1
      await takeCover(tester); // shot-2
      await tapIn(tester, 'flaw', 'Add a flaw photo'); // shot-3
      await tapIn(tester, 'sizeLabel', 'Take'); // shot-4
      h.camera.picks = [photoOf('p1')];
      await tapIn(tester, 'other', 'Add more photos');

      await tapWrite(tester);

      final listing = (await h.listings.all()).single;
      expect(listing.photos.map((p) => p.shot), [
        ListingShot.cover,
        ListingShot.back,
        ListingShot.sizeLabel,
        ListingShot.flaw,
        ListingShot.other,
      ]);
      expect(
        [
          for (final photo in listing.photos)
            markOfBytes(await h.images.read(photo.uri)),
        ],
        ['shot-2', 'shot-1', 'shot-4', 'shot-3', 'p1'],
      );
    });

    testWidgets('leaves the camera, so Back from the editor is Sell', (
      tester,
    ) async {
      await h.open(tester);
      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();
      expect(find.byType(NewListingScreen), findsOneWidget);
      await takeCover(tester);

      await tapWrite(tester);
      expect(find.byType(NewListingScreen), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(NewListingScreen), findsNothing);
      expect(find.byType(SellScreen), findsOneWidget);
      // And the new draft is on it.
      expect(find.text(h.gateway.facts.title), findsOneWidget);
    });

    testWidgets('opened directly, Back still goes to Sell', (tester) async {
      await openChecklist(tester);
      await takeCover(tester);
      await tapWrite(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
    });

    testWidgets('shows that it is working, and then, if it is slow, why', (
      tester,
    ) async {
      h.gateway.hold = Completer<void>();
      await openChecklist(tester);
      await takeCover(tester);

      await tester.tap(find.text('Write the listing'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Writing the listing…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(NewListingScreen), findsOneWidget);
      expect(find.textContaining('The server sleeps'), findsNothing);

      // Not before the scan screens say it...
      await tester.pump(wakingAfter - const Duration(seconds: 1));
      expect(find.textContaining('The server sleeps'), findsNothing);
      // ...and then, in their words.
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
      await expectOnEditor(tester, const ListingId('listing-1'));
    });

    testWidgets('does not say the server is asleep when it answers promptly', (
      tester,
    ) async {
      await openChecklist(tester);
      await takeCover(tester);

      await tapWrite(tester);

      expect(find.textContaining('The server sleeps'), findsNothing);
      // And nothing is left ticking for the next test to trip over.
      await tester.pump(wakingAfter * 2);
    });

    testWidgets('twice in a row makes one listing', (tester) async {
      h.gateway.hold = Completer<void>();
      await openChecklist(tester);
      await takeCover(tester);

      await tester.tap(find.text('Write the listing'));
      await tester.pump(const Duration(milliseconds: 100));
      // The button is gone while it works; a second tap has nothing to land on.
      expect(find.text('Write the listing'), findsNothing);

      h.gateway.hold!.complete();
      await tester.pumpAndSettle();

      expect(h.gateway.described, hasLength(1));
      expect(h.listings.length, 1);
    });
  });

  group('when the server cannot read them', () {
    const asleep = ScanFailure('The server is asleep. Try again in a moment.');

    Future<void> failToWrite(WidgetTester tester) async {
      await openChecklist(tester);
      await takeCover(tester);
      await tapIn(tester, 'brandTag', 'Take');
      await tapWrite(tester);
    }

    testWidgets('says what the server said, and offers both ways on', (
      tester,
    ) async {
      h.gateway.describeError = asleep;

      await failToWrite(tester);

      expect(
        find.text('The server is asleep. Try again in a moment.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Write it myself'), findsOneWidget);
      expect(find.byType(ListingEditorScreen), findsNothing);
      // Nothing was made of it.
      expect(h.listings.length, 0);
    });

    testWidgets('Try again sends the same photographs and makes the same '
        'listing', (tester) async {
      h.gateway.describeError = asleep;
      await failToWrite(tester);
      h.gateway.describeError = null;

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      await expectOnEditor(tester, const ListingId('listing-1'));
      expect(h.gateway.described, hasLength(2));
      expect(
        h.gateway.described.last.images.map(markOf),
        h.gateway.described.first.images.map(markOf),
      );
      // One listing, one set of files: not a second of either for the retry.
      expect(h.listings.length, 1);
      expect(h.images.length, 2);
    });

    testWidgets('Try again can fail again, and be tried again', (tester) async {
      h.gateway.describeError = asleep;
      await failToWrite(tester);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect(h.images.length, 2);

      h.gateway.describeError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      await expectOnEditor(tester, const ListingId('listing-1'));
      expect(h.images.length, 2);
    });

    testWidgets('Write it myself makes a blank draft with the photographs', (
      tester,
    ) async {
      h.gateway.describeError = asleep;
      await failToWrite(tester);

      await tester.tap(find.text('Write it myself'));
      await tester.pumpAndSettle();

      await expectOnEditor(tester, const ListingId('listing-1'));
      final listing = (await h.listings.all()).single;
      expect(listing.title, '');
      expect(listing.status, ListingStatus.draft);
      expect(listing.facts, isNull);
      expect(listing.photos.map((p) => p.shot), [
        ListingShot.cover,
        ListingShot.brandTag,
      ]);
      // The photographs that were already stored, kept: not stored again, and
      // not sent again.
      expect(h.images.length, 2);
      expect(h.gateway.described, hasLength(1));
    });

    testWidgets('Write it myself is the way on when trying again is not', (
      tester,
    ) async {
      h.gateway.describeError = const ScanFailure(
        'That photo could not be read.',
        isRetryable: false,
      );

      await failToWrite(tester);

      expect(find.text('That photo could not be read.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Write it myself'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Write it myself'));
      await tester.pumpAndSettle();
      await expectOnEditor(tester, const ListingId('listing-1'));
    });

    testWidgets('a server that answers with nonsense is the same', (
      tester,
    ) async {
      h.gateway.describeError = ScanContractError('the response had no title');

      await failToWrite(tester);

      expect(find.textContaining('cannot read'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Write it myself'), findsOneWidget);
    });

    testWidgets('backing out gives the photographs up, and leaves nothing '
        'behind', (tester) async {
      h.gateway.describeError = asleep;
      await h.open(tester);
      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();
      await takeCover(tester);
      await tapIn(tester, 'brandTag', 'Take');
      await tapWrite(tester);
      expect(h.images.length, 2);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
      expect(h.images.length, 0);
      expect(h.listings.length, 0);
    });

    testWidgets('the system Back does the same', (tester) async {
      h.gateway.describeError = asleep;
      await h.open(tester);
      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();
      await takeCover(tester);
      await tapWrite(tester);
      expect(h.images.length, 1);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
      expect(h.images.length, 0);
    });

    testWidgets('leaving while it is writing, then failing, leaves nothing '
        'behind', (tester) async {
      h.gateway.describeError = asleep;
      h.gateway.hold = Completer<void>();
      await h.open(tester);
      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();
      await takeCover(tester);
      await tester.tap(find.text('Write the listing'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(h.images.length, 1);

      // Gone to Sell before the server has answered, and then it fails.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SellScreen), findsOneWidget);
      h.gateway.hold!.complete();
      await tester.pumpAndSettle();

      expect(h.images.length, 0);
      expect(h.listings.length, 0);
    });

    testWidgets('writing it by hand keeps them, though Back is used after', (
      tester,
    ) async {
      h.gateway.describeError = asleep;
      await h.open(tester);
      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();
      await takeCover(tester);
      await tapWrite(tester);

      await tester.tap(find.text('Write it myself'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // They are the listing's now.
      expect(h.images.length, 1);
      expect(h.listings.length, 1);
    });
  });

  group('leaving before writing', () {
    testWidgets('stores nothing and sends nothing', (tester) async {
      await h.open(tester);
      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();
      await takeCover(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
      expect(h.images.length, 0);
      expect(h.listings.length, 0);
      expect(h.gateway.described, isEmpty);
    });

    testWidgets('and a fresh visit starts with nothing taken', (tester) async {
      await h.open(tester);
      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();
      await takeCover(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Photograph something to sell'));
      await tester.pumpAndSettle();

      expect(find.text('0 of 8 photos'), findsOneWidget);
      expect(write(tester).onPressed, isNull);
    });
  });

  group('on a small phone at a large text size', () {
    const phone = Size(320, 640);
    const scale = 1.6;

    /// Scrolls from top to bottom, failing on the first overflow.
    Future<void> scrollThrough(WidgetTester tester) async {
      expect(tester.takeException(), isNull);
      final list = find.byType(Scrollable).first;
      for (var step = 0; step < 16; step++) {
        await tester.drag(list, const Offset(0, -240));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after scroll $step');
      }
    }

    /// Whether every word in [finder] was kept whole.
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

    testWidgets('the checklist lays out, empty', (tester) async {
      await openChecklist(tester, size: phone, textScale: scale);

      await scrollThrough(tester);
      // The button that writes it is still on screen under the list.
      expect(find.text('Write the listing'), findsOneWidget);
    });

    testWidgets('the checklist lays out with a photograph in every place', (
      tester,
    ) async {
      await openChecklist(
        tester,
        size: const Size(320, 4000),
        textScale: scale,
      );
      for (final shot in ['cover', 'back', 'brandTag', 'sizeLabel']) {
        await tapIn(tester, shot, 'Take');
      }
      for (var i = 0; i < 4; i++) {
        await tapIn(tester, 'flaw', 'Add a flaw photo');
      }
      expect(find.text('8 of 8 photos'), findsOneWidget);

      tester.view.physicalSize = phone;
      await tester.pumpAndSettle();

      await scrollThrough(tester);
    });

    testWidgets('keeps the words of a row whole', (tester) async {
      await openChecklist(
        tester,
        size: const Size(320, 4000),
        textScale: scale,
      );

      expect(tester.takeException(), isNull);
      for (final shot in ListingShot.values.where((s) => s.isChecklist)) {
        expectWhole(tester, find.text(shot.label));
        expectWhole(tester, find.text(shot.why));
      }
      expectWhole(tester, find.text('Flaws (optional)'));
    });

    testWidgets('the button that writes it stays within the phone', (
      tester,
    ) async {
      await openChecklist(tester, size: phone, textScale: scale);

      final button = tester.getRect(
        find.widgetWithText(FilledButton, 'Write the listing'),
      );
      expect(button.left, greaterThanOrEqualTo(0));
      expect(button.right, lessThanOrEqualTo(phone.width));
      expect(button.bottom, lessThanOrEqualTo(phone.height));
    });

    testWidgets('the wait, with its sleeping-server line, lays out', (
      tester,
    ) async {
      h.gateway.hold = Completer<void>();
      await openChecklist(
        tester,
        size: const Size(320, 4000),
        textScale: scale,
      );
      await takeCover(tester);
      tester.view.physicalSize = phone;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write the listing'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(wakingAfter + const Duration(seconds: 1));

      expect(find.textContaining('The server sleeps'), findsOneWidget);
      expect(tester.takeException(), isNull);
      h.gateway.hold!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the failure, with both ways on, lays out', (tester) async {
      h.gateway.describeError = const ScanFailure(
        'Could not reach the server. SocketException: Connection refused '
        '(OS Error: Connection refused, errno = 111)',
      );
      await openChecklist(
        tester,
        size: const Size(320, 4000),
        textScale: scale,
      );
      await takeCover(tester);
      tester.view.physicalSize = phone;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write the listing'));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Write it myself'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expectWhole(tester, find.text('Try again'));
      expectWhole(tester, find.text('Write it myself'));
    });
  });
}
