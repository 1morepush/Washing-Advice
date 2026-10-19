/// The photographs taken for a listing, and the rules about them.
///
/// The screen tests drive these through buttons; this is the same rules without
/// the buttons, so that an edge — the ninth photograph, the retake at the limit,
/// a pick that only half fits — is pinned where it can be read in a line.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/features/sell/start/photo_set.dart';

import 'sell_list_harness.dart' show markOf, photoOf;

void main() {
  const empty = ListingPhotoSet.empty();

  ListingPhotoSet of(List<(ListingShot, String)> taken) {
    var photos = empty;
    for (final (shot, mark) in taken) {
      photos = photos.taking(shot, photoOf(mark))!;
    }
    return photos;
  }

  List<String> marks(ListingPhotoSet photos) => [
    for (final (image, _) in photos.shots) markOf(image),
  ];

  /// Eight photographs: the four asked for and four flaws.
  ListingPhotoSet full() => of([
    (ListingShot.cover, 'c'),
    (ListingShot.back, 'b'),
    (ListingShot.brandTag, 't'),
    (ListingShot.sizeLabel, 's'),
    for (var i = 0; i < 4; i++) (ListingShot.flaw, 'f$i'),
  ]);

  group('with nothing taken', () {
    test('has room for everything Depop takes', () {
      expect(empty.count, 0);
      expect(empty.room, depopPhotoLimit);
      expect(empty.isFull, isFalse);
      expect(empty.shots, isEmpty);
    });

    test('has no cover, which is what a listing needs to be written', () {
      expect(empty.hasCover, isFalse);
      expect(empty.imageFor(ListingShot.cover), isNull);
    });
  });

  group('a shot on the checklist', () {
    test('has one place', () {
      final photos = of([(ListingShot.cover, 'first')]);

      expect(photos.hasCover, isTrue);
      expect(markOf(photos.imageFor(ListingShot.cover)!), 'first');
    });

    test('is replaced by a retake, in the same position and uncounted', () {
      final photos = of([
        (ListingShot.cover, 'old'),
        (ListingShot.back, 'back'),
      ]);

      final retaken = photos.taking(ListingShot.cover, photoOf('new'))!;

      expect(retaken.count, 2);
      expect(marks(retaken), ['new', 'back']);
    });

    test('can still be retaken at the limit', () {
      final retaken = full().taking(ListingShot.cover, photoOf('new'));

      expect(retaken, isNotNull);
      expect(retaken!.count, depopPhotoLimit);
      expect(markOf(retaken.imageFor(ListingShot.cover)!), 'new');
    });

    test('is not a flaw or a pile: only those take several', () {
      for (final shot in ListingShot.values) {
        final twice = of([(shot, 'a'), (shot, 'b')]);
        expect(twice.count, shot.isChecklist ? 1 : 2, reason: shot.name);
      }
    });
  });

  group('a flaw, or any other photograph', () {
    test('adds to the pile, in the order taken', () {
      final photos = of([(ListingShot.flaw, 'one'), (ListingShot.flaw, 'two')]);

      expect(photos.count, 2);
      expect(photos.imagesFor(ListingShot.flaw).map(markOf), ['one', 'two']);
    });

    test('is refused at the limit, and nothing is changed', () {
      final photos = full();

      expect(photos.taking(ListingShot.flaw, photoOf('nine')), isNull);
      expect(photos.taking(ListingShot.other, photoOf('nine')), isNull);
      expect(photos.count, depopPhotoLimit);
    });
  });

  group('the limit', () {
    test('is what the core says Depop takes', () {
      expect(depopPhotoLimit, 8);
      expect(full().isFull, isTrue);
      expect(full().room, 0);
    });

    test('is reached only by the eighth', () {
      final seven = of([
        (ListingShot.cover, 'c'),
        for (var i = 0; i < 6; i++) (ListingShot.other, 'o$i'),
      ]);

      expect(seven.count, 7);
      expect(seven.isFull, isFalse);
      expect(seven.room, 1);
    });
  });

  group('taking several at once', () {
    test('takes them as photographs of the kind given', () {
      final added = empty.takingAll(ListingShot.other, [
        photoOf('a'),
        photoOf('b'),
      ]);

      expect(added.left, 0);
      expect(added.photos.imagesFor(ListingShot.other).map(markOf), ['a', 'b']);
    });

    test('takes the first that fit and counts the rest', () {
      final seven = of([
        (ListingShot.cover, 'c'),
        for (var i = 0; i < 6; i++) (ListingShot.flaw, 'f$i'),
      ]);

      final added = seven.takingAll(ListingShot.other, [
        photoOf('first'),
        photoOf('second'),
        photoOf('third'),
      ]);

      expect(added.photos.count, depopPhotoLimit);
      expect(added.photos.imagesFor(ListingShot.other).map(markOf), ['first']);
      expect(added.left, 2);
    });

    test('takes none when it is full', () {
      final added = full().takingAll(ListingShot.other, [photoOf('a')]);

      expect(added.photos.count, depopPhotoLimit);
      expect(added.left, 1);
    });

    test('takes none of none', () {
      final added = empty.takingAll(ListingShot.other, const []);

      expect(added.photos.count, 0);
      expect(added.left, 0);
    });
  });

  group('taking one back', () {
    test('removes that photograph and leaves the rest', () {
      final photos = of([
        (ListingShot.cover, 'c'),
        (ListingShot.flaw, 'f0'),
        (ListingShot.flaw, 'f1'),
        (ListingShot.flaw, 'f2'),
      ]);

      final fewer = photos.without(ListingShot.flaw, index: 1);

      expect(fewer.imagesFor(ListingShot.flaw).map(markOf), ['f0', 'f2']);
      expect(fewer.hasCover, isTrue);
    });

    test('takes the cover back, and so the way to write the listing', () {
      final photos = of([(ListingShot.cover, 'c')]);

      expect(photos.without(ListingShot.cover).hasCover, isFalse);
    });

    test('is nothing for a photograph that is not there', () {
      final photos = of([(ListingShot.cover, 'c')]);

      expect(photos.without(ListingShot.back).count, 1);
      expect(photos.without(ListingShot.cover, index: 3).count, 1);
    });

    test('makes room again', () {
      final photos = full().without(ListingShot.flaw);

      expect(photos.isFull, isFalse);
      expect(photos.taking(ListingShot.flaw, photoOf('again')), isNotNull);
    });
  });

  group('the order a listing keeps them in', () {
    test('is cover first, then by kind as the core declares them', () {
      final photos = of([
        (ListingShot.other, 'o'),
        (ListingShot.flaw, 'f'),
        (ListingShot.sizeLabel, 's'),
        (ListingShot.back, 'b'),
        (ListingShot.cover, 'c'),
        (ListingShot.brandTag, 't'),
      ]);

      expect(photos.shots.map((s) => s.$2), [
        ListingShot.cover,
        ListingShot.back,
        ListingShot.brandTag,
        ListingShot.sizeLabel,
        ListingShot.flaw,
        ListingShot.other,
      ]);
      expect(marks(photos), ['c', 'b', 't', 's', 'f', 'o']);
    });

    test('keeps the order within a kind', () {
      final photos = of([
        (ListingShot.flaw, 'second thing'),
        (ListingShot.cover, 'c'),
        (ListingShot.flaw, 'third thing'),
      ]);

      expect(marks(photos), ['c', 'second thing', 'third thing']);
    });

    test('never has more than Depop takes', () {
      expect(full().shots, hasLength(depopPhotoLimit));
    });
  });
}
