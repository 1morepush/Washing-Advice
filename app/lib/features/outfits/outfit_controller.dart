/// Saving, wearing and deleting outfits.
///
/// A thin layer over the repository, but not a pointless one: it is where the
/// clock, the id generator and the wear recorder are brought together, so a
/// widget never has to know that saving an outfit means minting an id and
/// stamping two timestamps.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../history/wear_recorder.dart';

class OutfitController {
  const OutfitController(this._ref);

  final Ref _ref;

  /// Saves a suggestion under a name, returning the stored outfit.
  Future<Outfit> saveSuggestion(
    OutfitSuggestion suggestion, {
    required String name,
    required Occasion occasion,
  }) async {
    final now = DateTime.now();
    final outfit = Outfit(
      id: OutfitId(_ref.read(idGeneratorProvider).next()),
      name: name.trim().isEmpty ? _nameFor(suggestion) : name.trim(),
      itemIds: suggestion.itemIds,
      occasion: occasion,
      // Seasons are deliberately left unstated rather than guessed from the
      // garments. Empty means "any" throughout the domain, and inferring
      // "winter" from a jumper would quietly hide the outfit for nine months
      // on evidence the user never gave.
      createdAt: now,
      updatedAt: now,
    );

    await _ref.read(outfitRepositoryProvider).save(outfit);
    _ref.invalidate(savedOutfitsProvider);
    return outfit;
  }

  /// Records the outfit as worn: every item at the same instant, and the
  /// outfit's own counters kept in step.
  ///
  /// The item events are the log; the outfit's [UsageStats] is a cache of how
  /// often this particular combination was chosen, which no per-item event can
  /// answer — the log knows the tee and the jeans were worn together, not that
  /// they were worn together *as this saved outfit*.
  Future<void> wear(Outfit outfit) async {
    final now = DateTime.now();
    await _ref
        .read(wearRecorderProvider)
        .recordOutfit(outfit.itemIds, occasion: outfit.occasion.name, at: now);

    await _ref
        .read(outfitRepositoryProvider)
        .save(
          outfit.copyWith(
            usage: outfit.usage.copyWith(
              timesWorn: outfit.usage.timesWorn + 1,
              lastWornAt: now,
              firstWornAt: outfit.usage.firstWornAt ?? now,
            ),
            updatedAt: now,
          ),
        );
    _ref.invalidate(savedOutfitsProvider);
  }

  Future<void> delete(OutfitId id) async {
    await _ref.read(outfitRepositoryProvider).delete(id);
    _ref.invalidate(savedOutfitsProvider);
  }

  Future<void> rename(Outfit outfit, String name) async {
    if (name.trim().isEmpty) return;
    await _ref
        .read(outfitRepositoryProvider)
        .save(outfit.copyWith(name: name.trim(), updatedAt: DateTime.now()));
    _ref.invalidate(savedOutfitsProvider);
  }

  /// A default name, so saving never demands typing.
  ///
  /// The two most identifying garments, which is what someone would say out
  /// loud — "the cream blouse and the jeans" — rather than a serial number.
  String _nameFor(OutfitSuggestion suggestion) =>
      suggestion.items.take(2).map((i) => i.displayName).join(' + ');
}

final outfitControllerProvider = Provider<OutfitController>(
  OutfitController.new,
);
