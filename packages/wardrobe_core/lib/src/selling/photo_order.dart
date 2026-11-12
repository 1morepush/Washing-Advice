/// The order of a listing's photographs, and who the cover is.
///
/// A Depop listing's first photograph is the one a buyer sees in search, so
/// "the cover" is a place in the list before it is a kind of shot, and the
/// listing keeps the two in step: **the first photograph is always the cover,
/// and the cover is always first.** These are the rules for changing that, in
/// one place and without a screen, so the strip, the full-screen viewer and
/// the tests all mean the same thing by "make this the cover".
///
/// Every function takes the list and returns a new one; the argument is never
/// changed. A request that would change nothing — an index out of range, a
/// move to where the photograph already is — returns a list equal to the one
/// given, so a caller comparing before and after can tell nothing happened.
library;

import 'listing.dart';

/// [photos] with [index] made the cover.
///
/// The chosen photograph goes first and its shot becomes [ListingShot.cover].
/// The one that was the cover steps down:
///
/// * a cover becomes [ListingShot.other], since "cover" is no longer what it
///   is and nothing better is known about it;
/// * a first photograph that was never marked as a cover but had a role — a
///   back, a brand tag — keeps that role, because the photograph has not
///   stopped being of the back of the garment.
///
/// Any other photograph marked as a cover is demoted the same way, so there
/// is exactly one. The rest keep their order.
List<ListingPhoto> makePhotoCover(List<ListingPhoto> photos, int index) {
  if (!_inRange(photos, index)) return photos;
  if (index == 0) return _crowned(photos);

  return _crowned(
      [photos[index], ...photos.take(index), ...photos.skip(index + 1)]);
}

/// [photos] with the one at [from] moved to [to], the others closing up.
///
/// [to] is clamped to the list. Moving something to the front makes it the
/// cover, and moving the cover back makes the photograph that takes its place
/// the cover, by the rules in [makePhotoCover]: the first photograph is always
/// the cover.
List<ListingPhoto> movePhoto(List<ListingPhoto> photos, int from, int to) {
  if (!_inRange(photos, from)) return photos;
  final target = to.clamp(0, photos.length - 1);
  if (target == from) return photos;

  final moved = [...photos];
  moved.insert(target, moved.removeAt(from));

  // Only the front is special. A move among the others changes no cover.
  return from == 0 || target == 0 ? _crowned(moved) : moved;
}

/// [photos] without the one at [index].
///
/// Removing the cover makes the next photograph the cover, with its shot
/// changed to match (see [makePhotoCover]). That photograph stops counting as
/// whatever it was — if it was the brand tag, the listing is missing a brand
/// tag again, and says so.
List<ListingPhoto> removePhotoAt(List<ListingPhoto> photos, int index) {
  if (!_inRange(photos, index)) return photos;

  final left = [...photos]..removeAt(index);
  return index == 0 && left.isNotEmpty ? _crowned(left) : left;
}

bool _inRange(List<ListingPhoto> photos, int index) =>
    index >= 0 && index < photos.length;

/// [photos] with the first as the one and only cover.
List<ListingPhoto> _crowned(List<ListingPhoto> photos) => [
      for (final (i, photo) in photos.indexed)
        if (i == 0)
          photo.copyWith(shot: ListingShot.cover)
        else if (photo.shot == ListingShot.cover)
          photo.copyWith(shot: ListingShot.other)
        else
          photo,
    ];
