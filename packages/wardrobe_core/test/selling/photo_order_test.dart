import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

ListingPhoto p(String name, ListingShot shot) =>
    ListingPhoto(uri: 'store://$name.jpg', shot: shot);

/// A cover, a back, a brand tag and a flaw, in that order.
List<ListingPhoto> four() => [
      p('cover', ListingShot.cover),
      p('back', ListingShot.back),
      p('tag', ListingShot.brandTag),
      p('flaw', ListingShot.flaw),
    ];

List<String> names(List<ListingPhoto> photos) =>
    [for (final photo in photos) photo.uri.split('/').last.split('.').first];

List<ListingShot> shots(List<ListingPhoto> photos) =>
    [for (final photo in photos) photo.shot];

void main() {
  group('making a photograph the cover', () {
    test('puts it first and gives it the cover shot', () {
      final result = makePhotoCover(four(), 2);

      expect(names(result), ['tag', 'cover', 'back', 'flaw']);
      expect(result.first.shot, ListingShot.cover);
    });

    test('demotes the old cover to other', () {
      final result = makePhotoCover(four(), 2);

      expect(
        shots(result),
        [
          ListingShot.cover,
          ListingShot.other,
          ListingShot.back,
          ListingShot.flaw,
        ],
      );
    });

    test('lets a first photograph that was never a cover keep its role', () {
      // A listing made from a garment can open on a photograph that is the
      // back: it has not stopped being the back because another is chosen.
      final photos = [
        p('back', ListingShot.back),
        p('front', ListingShot.other),
        p('tag', ListingShot.brandTag),
      ];

      final result = makePhotoCover(photos, 1);

      expect(names(result), ['front', 'back', 'tag']);
      expect(
        shots(result),
        [ListingShot.cover, ListingShot.back, ListingShot.brandTag],
      );
    });

    test('leaves exactly one cover when there were two', () {
      final photos = [
        p('a', ListingShot.cover),
        p('b', ListingShot.back),
        p('c', ListingShot.cover),
      ];

      final result = makePhotoCover(photos, 1);

      expect(names(result), ['b', 'a', 'c']);
      expect(
        shots(result),
        [ListingShot.cover, ListingShot.other, ListingShot.other],
      );
    });

    test('keeps the others in the order they were in', () {
      final result = makePhotoCover(four(), 3);

      expect(names(result), ['flaw', 'cover', 'back', 'tag']);
    });

    test('does nothing to a photograph that is already the cover', () {
      final photos = four();

      expect(makePhotoCover(photos, 0), photos);
    });

    test('makes the first photograph a cover when it was not marked as one',
        () {
      final photos = [
        p('front', ListingShot.other),
        p('back', ListingShot.back),
      ];

      final result = makePhotoCover(photos, 0);

      expect(names(result), ['front', 'back']);
      expect(shots(result), [ListingShot.cover, ListingShot.back]);
    });

    test('ignores an index that is not there', () {
      final photos = four();

      expect(makePhotoCover(photos, -1), photos);
      expect(makePhotoCover(photos, 4), photos);
      expect(makePhotoCover(const [], 0), isEmpty);
    });

    test('does not change the list it was given', () {
      final photos = four();
      final before = [...photos];

      makePhotoCover(photos, 2);

      expect(photos, before);
    });
  });

  group('moving a photograph', () {
    test('later swaps it with the next', () {
      final result = movePhoto(four(), 1, 2);

      expect(names(result), ['cover', 'tag', 'back', 'flaw']);
      // Nothing about the cover changed, so no shot did.
      expect(
        shots(result),
        [
          ListingShot.cover,
          ListingShot.brandTag,
          ListingShot.back,
          ListingShot.flaw,
        ],
      );
    });

    test('earlier swaps it with the one before', () {
      final result = movePhoto(four(), 3, 2);

      expect(names(result), ['cover', 'back', 'flaw', 'tag']);
    });

    test('to the front makes it the cover', () {
      final result = movePhoto(four(), 1, 0);

      expect(names(result), ['back', 'cover', 'tag', 'flaw']);
      expect(
        shots(result),
        [
          ListingShot.cover,
          ListingShot.other,
          ListingShot.brandTag,
          ListingShot.flaw,
        ],
      );
    });

    test('the cover later makes the next photograph the cover', () {
      final result = movePhoto(four(), 0, 1);

      expect(names(result), ['back', 'cover', 'tag', 'flaw']);
      expect(result.first.shot, ListingShot.cover);
      expect(result[1].shot, ListingShot.other);
    });

    test('clamps to the ends', () {
      expect(names(movePhoto(four(), 1, 99)), ['cover', 'tag', 'flaw', 'back']);
      expect(names(movePhoto(four(), 2, -5)), ['tag', 'cover', 'back', 'flaw']);
    });

    test('to where it already is changes nothing', () {
      final photos = four();

      expect(movePhoto(photos, 2, 2), photos);
      expect(movePhoto(photos, 3, 99), photos);
      expect(movePhoto(photos, 0, -1), photos);
    });

    test('ignores a photograph that is not there', () {
      final photos = four();

      expect(movePhoto(photos, 4, 0), photos);
      expect(movePhoto(photos, -1, 0), photos);
    });

    test('keeps every photograph', () {
      final result = movePhoto(four(), 3, 0);

      expect(names(result)..sort(), ['back', 'cover', 'flaw', 'tag']);
    });
  });

  group('removing a photograph', () {
    test('closes the gap and leaves the others as they are', () {
      final result = removePhotoAt(four(), 2);

      expect(names(result), ['cover', 'back', 'flaw']);
      expect(
        shots(result),
        [ListingShot.cover, ListingShot.back, ListingShot.flaw],
      );
    });

    test('the cover makes the next photograph the cover', () {
      final result = removePhotoAt(four(), 0);

      expect(names(result), ['back', 'tag', 'flaw']);
      expect(
        shots(result),
        [ListingShot.cover, ListingShot.brandTag, ListingShot.flaw],
      );
    });

    test('the last photograph leaves none', () {
      expect(removePhotoAt([p('cover', ListingShot.cover)], 0), isEmpty);
    });

    test('the last one, when it is not the cover, leaves the cover alone', () {
      final result = removePhotoAt(four(), 3);

      expect(names(result), ['cover', 'back', 'tag']);
      expect(result.first.shot, ListingShot.cover);
    });

    test('ignores an index that is not there', () {
      final photos = four();

      expect(removePhotoAt(photos, 4), photos);
      expect(removePhotoAt(photos, -1), photos);
    });

    test('does not change the list it was given', () {
      final photos = four();
      final before = [...photos];

      removePhotoAt(photos, 0);

      expect(photos, before);
    });
  });
}
