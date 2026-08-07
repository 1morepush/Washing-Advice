/// Storage for saved outfits.
///
/// Kept separate from [WardrobeRepository] rather than added to it. An outfit
/// references items but does not contain them, the two have different
/// lifetimes, and a wardrobe is perfectly usable with no outfits saved at all
/// — merging the two interfaces would force every implementation of one to
/// answer for the other.
///
/// The in-memory implementation below is not only a test double: it is what
/// the operations are *defined* to mean, and the shared contract suite in
/// `test/outfits/outfit_repository_test.dart` runs the same tests against it
/// and against the app's Drift implementation, so a divergence is a bug in the
/// SQL rather than an open question.
library;

import 'dart:async';

import '../shared/ids.dart';
import 'model/occasion.dart';
import 'model/outfit.dart';

/// Reads and writes saved outfits.
abstract interface class OutfitRepository {
  /// One outfit, or null when nothing has that id.
  Future<Outfit?> byId(OutfitId id);

  /// Every saved outfit, most recently updated first.
  ///
  /// A wardrobe holds hundreds of items and someone might save a dozen
  /// outfits, so there is no query language here and no paging. If that
  /// assumption ever breaks, this is the one method that changes.
  Future<List<Outfit>> all({Occasion? occasion});

  /// Outfits containing [id] — what a garment is part of.
  ///
  /// Needed by the item detail screen, and by deletion: removing a garment
  /// must not leave outfits pointing at something that no longer exists.
  Future<List<Outfit>> containing(ItemId id);

  /// Inserts or replaces.
  Future<void> save(Outfit outfit);

  /// Removes an outfit.
  Future<void> delete(OutfitId id);

  /// Drops [id] from every outfit that contains it, deleting any outfit left
  /// with fewer than two items.
  ///
  /// Called when a garment leaves the wardrobe. An "outfit" of one item is not
  /// an outfit, and silently keeping one would put a broken entry in a list
  /// the user has to maintain by hand.
  Future<void> removeItem(ItemId id);

  /// Saved outfits, re-emitted whenever they change.
  Stream<List<Outfit>> watch({Occasion? occasion});
}

/// Holds saved outfits in a map.
final class InMemoryOutfitRepository implements OutfitRepository {
  InMemoryOutfitRepository([Iterable<Outfit> initial = const []]) {
    for (final outfit in initial) {
      _outfits[outfit.id] = outfit;
    }
  }

  final Map<OutfitId, Outfit> _outfits = {};
  final List<StreamController<List<Outfit>>> _watchers = [];
  final Map<StreamController<List<Outfit>>, Occasion?> _filters = {};

  int get length => _outfits.length;

  @override
  Future<Outfit?> byId(OutfitId id) async => _outfits[id];

  @override
  Future<List<Outfit>> all({Occasion? occasion}) async => _apply(occasion);

  @override
  Future<List<Outfit>> containing(ItemId id) async => [
        for (final outfit in _apply(null))
          if (outfit.contains(id)) outfit,
      ];

  @override
  Future<void> save(Outfit outfit) async {
    _outfits[outfit.id] = outfit;
    _notify();
  }

  @override
  Future<void> delete(OutfitId id) async {
    _outfits.remove(id);
    _notify();
  }

  @override
  Future<void> removeItem(ItemId id) async {
    for (final outfit in [..._outfits.values]) {
      if (!outfit.contains(id)) continue;

      final reduced = outfit.without(id);
      if (reduced.size < 2) {
        _outfits.remove(outfit.id);
      } else {
        _outfits[outfit.id] = reduced;
      }
    }
    _notify();
  }

  @override
  Stream<List<Outfit>> watch({Occasion? occasion}) {
    // Single-subscription rather than broadcast, for the reason spelled out on
    // `InMemoryWardrobeRepository.watch`: a broadcast controller drops the
    // snapshot pushed from `onListen`, which left a screen spinning forever.
    late final StreamController<List<Outfit>> controller;
    controller = StreamController<List<Outfit>>(
      onListen: () => controller.add(_apply(occasion)),
      onCancel: () {
        _watchers.remove(controller);
        _filters.remove(controller);
      },
    );
    _watchers.add(controller);
    _filters[controller] = occasion;
    return controller.stream;
  }

  List<Outfit> _apply(Occasion? occasion) {
    final matching = [
      for (final outfit in _outfits.values)
        if (occasion == null || outfit.occasion == occasion) outfit,
    ];

    // Most recently updated first, with the id as a tie-break so two outfits
    // saved in the same millisecond still come back in a stable order.
    matching.sort((a, b) {
      final byDate = b.updatedAt.compareTo(a.updatedAt);
      return byDate != 0 ? byDate : a.id.value.compareTo(b.id.value);
    });
    return matching;
  }

  void _notify() {
    for (final controller in _watchers) {
      if (!controller.isClosed) controller.add(_apply(_filters[controller]));
    }
  }
}
