/// The photographs taken for a listing that has not been made yet.
///
/// Held in memory until the person says to write the listing: nothing is stored
/// or sent while they are still turning the garment over. This is the part of
/// that which is a rule rather than a screen — a checklist shot has one place and
/// retaking it replaces what is there, a flaw or any other photograph adds to
/// the pile, and the pile stops at what Depop takes — so it is a value that can
/// be tested without one.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

typedef _Taken = ({ScanImage image, ListingShot shot});

final class ListingPhotoSet {
  const ListingPhotoSet._(this._taken);

  const ListingPhotoSet.empty() : _taken = const [];

  final List<_Taken> _taken;

  /// How many photographs there are, of any kind.
  int get count => _taken.length;

  /// How many more Depop will take.
  int get room => depopPhotoLimit - count;

  /// Whether Depop will take no more.
  bool get isFull => room <= 0;

  /// Whether the cover is taken, which is all a listing needs to be written.
  bool get hasCover => imageFor(ListingShot.cover) != null;

  /// The photograph of [shot], or the first of them where it can have several.
  ScanImage? imageFor(ListingShot shot) {
    for (final taken in _taken) {
      if (taken.shot == shot) return taken.image;
    }
    return null;
  }

  /// Every photograph of [shot], in the order they were taken.
  List<ScanImage> imagesFor(ListingShot shot) => [
    for (final taken in _taken)
      if (taken.shot == shot) taken.image,
  ];

  /// With [image] as the photograph of [shot].
  ///
  /// A shot on the checklist — the cover, the back, a label — has one place, so
  /// a second photograph of it **replaces** the first, in the same position, and
  /// does not count against the limit. Any other kind adds to the pile. Null
  /// when it would be one more than Depop takes, and nothing is changed.
  ListingPhotoSet? taking(ListingShot shot, ScanImage image) {
    if (shot.isChecklist) {
      final at = _taken.indexWhere((taken) => taken.shot == shot);
      if (at >= 0) {
        return ListingPhotoSet._(
          [..._taken]..[at] = (image: image, shot: shot),
        );
      }
    }
    if (isFull) return null;
    return ListingPhotoSet._([..._taken, (image: image, shot: shot)]);
  }

  /// With as many of [images] as there is room for, as photographs of [shot].
  ///
  /// The first ones, in the order given, and [left] is how many did not fit —
  /// said to the person, so a photograph that is missing from the listing is
  /// not a mystery.
  ({ListingPhotoSet photos, int left}) takingAll(
    ListingShot shot,
    List<ScanImage> images,
  ) {
    final fit = images.take(room < 0 ? 0 : room).toList();
    return (
      photos: ListingPhotoSet._([
        ..._taken,
        for (final image in fit) (image: image, shot: shot),
      ]),
      left: images.length - fit.length,
    );
  }

  /// Without the [index]th photograph of [shot]. Unchanged where there is no
  /// such photograph.
  ListingPhotoSet without(ListingShot shot, {int index = 0}) {
    var seen = 0;
    for (final (at, taken) in _taken.indexed) {
      if (taken.shot != shot) continue;
      if (seen++ == index) return ListingPhotoSet._([..._taken]..removeAt(at));
    }
    return this;
  }

  /// The photographs as a listing keeps them: by kind in the order the core
  /// declares them — cover first, then the back, the labels, the flaws and
  /// whatever else — and in the order they were taken within a kind.
  ///
  /// The cover leading is not tidiness. A listing's first photograph is the one
  /// Depop shows in a feed, and the one the editor takes to be its cover.
  List<(ScanImage, ListingShot)> get shots => [
    for (final shot in ListingShot.values)
      for (final taken in _taken)
        if (taken.shot == shot) (taken.image, shot),
  ];
}
