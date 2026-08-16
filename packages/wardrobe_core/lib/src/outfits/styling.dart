/// Outfits a model proposed, checked before anybody is told to wear one.
///
/// [OutfitBuilder] scores colour, usage and what has been worn together. It has
/// no opinion on pattern, texture, proportion or formality, which is a real
/// limit: it will happily pair a pinstripe with a check because both are navy.
/// Those are exactly the judgements a model trained on how clothes actually
/// look is good at, and they carry no safety cost — a bad outfit is a bad day,
/// not a ruined jumper.
///
/// So this is the one place in the app where a model's *opinion* is welcome.
/// What it is still not allowed to do is invent facts, and that is what this
/// file is for.
///
/// ## What is checked
///
/// A proposal names item ids and gives a reason. Before it becomes a
/// suggestion:
///
/// * every id must exist in the wardrobe — a model that returns a plausible id
///   it made up would otherwise put a garment on the screen that cannot be
///   opened;
/// * every item must be available to wear, because suggesting the shirt that is
///   currently in the washing machine is the one failure that makes the whole
///   feature look broken;
/// * it must not stack two garments that occupy the same place on the body,
///   which is the commonest structural nonsense and the easiest to catch;
/// * it must be a wearable outfit at all rather than a pile of accessories.
///
/// Nothing here judges whether the outfit is *good*. That is the part being
/// delegated, and second-guessing it in code would defeat the point of asking.
library;

import '../shared/ids.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/wardrobe_item.dart';

/// One outfit as the model proposed it, before anything has checked it.
final class StyleProposal {
  const StyleProposal({required this.itemIds, required this.rationale});

  final List<ItemId> itemIds;

  /// Why the model put these together, in its own words.
  ///
  /// Shown rather than summarised. The whole reason for asking a model is the
  /// judgement the rule-based builder cannot make, and a suggestion that hid
  /// its reasoning would be asking to be obeyed rather than considered — which
  /// is the opposite of what every other explanation in this app does.
  final String rationale;
}

/// Why a proposal was thrown away.
enum StyleRefusal {
  /// Named a garment that is not in the wardrobe.
  unknownItem('Suggested something that is not in your wardrobe'),

  /// Named a garment that is in the wash, stored, or otherwise not wearable.
  unavailable('Suggested something that is not available to wear'),

  /// Two tops, two pairs of trousers — garments competing for one place.
  conflictingLayers('Suggested two garments for the same place'),

  /// Accessories and nothing to wear them with.
  notAnOutfit('Did not add up to something wearable');

  const StyleRefusal(this.reason);

  final String reason;
}

/// A proposal that survived checking, with the items resolved.
final class StyledOutfit {
  const StyledOutfit({required this.items, required this.rationale});

  final List<WardrobeItem> items;
  final String rationale;

  Iterable<ItemId> get itemIds => items.map((item) => item.id);

  /// The same key [OutfitSuggestion] uses, so a styled outfit and a built one
  /// can be compared for sameness without either knowing about the other.
  String get signature =>
      (itemIds.map((id) => id.value).toList()..sort()).join('|');
}

/// One proposal that did not survive, kept so the screen can say so.
final class RefusedOutfit {
  const RefusedOutfit({required this.proposal, required this.refusal});

  final StyleProposal proposal;
  final StyleRefusal refusal;
}

/// What checking a batch of proposals produced.
final class StyledOutfits {
  const StyledOutfits({this.outfits = const [], this.refused = const []});

  final List<StyledOutfit> outfits;
  final List<RefusedOutfit> refused;

  bool get isEmpty => outfits.isEmpty;
}

/// Checks proposed outfits against the wardrobe they were proposed from.
final class StyleVetting {
  const StyleVetting();

  /// Categories that occupy the same place on the body, so two of any one of
  /// them is a mistake rather than layering.
  ///
  /// Outerwear is deliberately absent: a gilet over a jacket is a real outfit,
  /// and a rule that forbade it would be the code overruling the judgement it
  /// asked for. Accessories likewise — two of them is a belt and a scarf.
  static const _exclusive = {
    ItemCategory.top,
    ItemCategory.bottom,
    ItemCategory.fullBody,
    ItemCategory.footwear,
  };

  StyledOutfits vet(
    List<StyleProposal> proposals, {
    required List<WardrobeItem> wardrobe,
  }) {
    final byId = {for (final item in wardrobe) item.id: item};
    final kept = <StyledOutfit>[];
    final refused = <RefusedOutfit>[];
    final seen = <String>{};

    for (final proposal in proposals) {
      final (:items, :refusal) = _check(proposal, byId);
      if (refusal != null || items == null) {
        refused.add(
          RefusedOutfit(
            proposal: proposal,
            refusal: refusal ?? StyleRefusal.notAnOutfit,
          ),
        );
        continue;
      }

      final outfit = StyledOutfit(items: items, rationale: proposal.rationale);
      // The same outfit proposed twice is one suggestion shown twice, which is
      // the failure the rule-based builder already guards against by
      // diversifying. A model asked for five ideas can repeat itself.
      if (seen.add(outfit.signature)) kept.add(outfit);
    }

    return StyledOutfits(outfits: kept, refused: refused);
  }

  /// The resolved items, or why this proposal cannot be shown.
  ({List<WardrobeItem>? items, StyleRefusal? refusal}) _check(
    StyleProposal proposal,
    Map<ItemId, WardrobeItem> byId,
  ) {
    ({List<WardrobeItem>? items, StyleRefusal? refusal}) no(
      StyleRefusal refusal,
    ) =>
        (items: null, refusal: refusal);

    final items = <WardrobeItem>[];

    for (final id in proposal.itemIds) {
      final item = byId[id];
      if (item == null) return no(StyleRefusal.unknownItem);
      if (!item.lifecycle.isWearable) return no(StyleRefusal.unavailable);
      items.add(item);
    }

    if (items.length < 2) return no(StyleRefusal.notAnOutfit);

    final counts = <ItemCategory, int>{};
    for (final item in items) {
      counts.update(item.category, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final category in _exclusive) {
      if ((counts[category] ?? 0) > 1) {
        return no(StyleRefusal.conflictingLayers);
      }
    }

    // A full-body garment is the top and the bottom, so pairing one with either
    // is the same mistake as two tops.
    if ((counts[ItemCategory.fullBody] ?? 0) > 0 &&
        ((counts[ItemCategory.top] ?? 0) > 0 ||
            (counts[ItemCategory.bottom] ?? 0) > 0)) {
      return no(StyleRefusal.conflictingLayers);
    }

    final covered = counts[ItemCategory.fullBody] != null ||
        (counts[ItemCategory.top] != null &&
            counts[ItemCategory.bottom] != null);
    if (!covered) return no(StyleRefusal.notAnOutfit);

    return (items: items, refusal: null);
  }
}
