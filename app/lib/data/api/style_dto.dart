/// Asking for outfit ideas, on the wire.
///
/// Text rather than photographs, and that is a decision rather than a
/// shortcut. The wardrobe already holds what a stylist needs as structured
/// facts — type, colour, pattern, fit, fabric — read once when each garment was
/// scanned. Re-uploading forty photographs to derive them again would cost a
/// multiple of the time and money for facts the app is already surer about than
/// a fresh glance would be.
///
/// What comes back is a [StyleProposal]: item ids and a reason, neither of them
/// trusted. `StyleVetting` in the core resolves the ids against the real
/// wardrobe and throws away anything that does not add up. Keeping the wire
/// type separate from `StyledOutfit` is what makes skipping that step a compile
/// error rather than an oversight — the same reason `StainAdvice` is not a
/// `TreatmentPlan`.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

import 'scan_dto.dart';

/// One garment, as the stylist is told about it.
///
/// Deliberately not the whole item. A stylist needs what a garment looks like
/// and roughly how formal it is; it has no use for wash temperatures, purchase
/// prices or wear counts, and every field sent is tokens spent and one more
/// thing to keep in step across two languages.
Map<String, Object?> styleCandidateJson(WardrobeItem item) => {
  'id': item.id.value,
  'name': item.displayName,
  'type': item.type.value.label,
  'category': item.category.label,
  // Named colours where the scan produced a name, hex otherwise — the same
  // fallback the item screen shows, so the model is told what the user was
  // told. A model reads '#1F2A44' perfectly well; it just reasons better about
  // 'navy'.
  'colors': [for (final c in item.colors.value.colors) c.name ?? c.hex],
  'fabric': ?_nonEmpty(item.composition.value.label),
  'pattern': ?item.pattern?.value.label,
  'fit': ?item.fit?.label,
  'brand': ?_nonEmpty(item.brand?.value),
};

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();

/// Reads the proposals out of a `result` array.
///
/// A proposal with no ids or no reason is dropped rather than thrown on: one
/// malformed entry in a batch of five is not a reason to show nothing, and the
/// vetting downstream would refuse it anyway. A `result` that is not a list at
/// all *is* thrown on, because that is a contract this version cannot read.
List<StyleProposal> styleProposalsFromJson(List<Object?> json) {
  final proposals = <StyleProposal>[];

  for (final entry in json) {
    if (entry is! Map<String, Object?>) continue;

    final ids = entry['itemIds'];
    final rationale = entry['rationale'];
    if (ids is! List || rationale is! String || rationale.trim().isEmpty) {
      continue;
    }

    final itemIds = [
      for (final id in ids)
        if (id is String && id.isNotEmpty) ItemId(id),
    ];
    if (itemIds.isEmpty) continue;

    proposals.add(StyleProposal(itemIds: itemIds, rationale: rationale.trim()));
  }

  return proposals;
}

/// Guards the one shape [styleProposalsFromJson] cannot recover from.
List<Object?> styleResultList(Object? result) {
  if (result is! List) {
    throw ScanContractError('the response had no list of outfits');
  }
  return result;
}

/// Both halves of what the stylist answered. Separate lists because a piece
/// has no id — nothing to open, nothing to save.
typedef StyleAnswer = ({
  List<StyleProposal> outfits,
  List<PieceProposal> pieces,
});

/// Reads the suggested pieces out of a `pieces` array.
///
/// Absent on a server built before they existed, which is the shape this has
/// to survive most. Anything that is not a list reads as no pieces rather than
/// failing a response whose outfits are perfectly good.
List<PieceProposal> pieceProposalsFromJson(Object? json) {
  if (json is! List) return const [];

  final proposals = <PieceProposal>[];
  for (final entry in json) {
    if (entry is! Map<String, Object?>) continue;

    final type = entry['type'];
    final rationale = entry['rationale'];
    if (type is! String || type.trim().isEmpty) continue;
    if (rationale is! String || rationale.trim().isEmpty) continue;

    proposals.add(
      PieceProposal(
        type: type.trim(),
        colors: [
          for (final color in _list(entry['colors']))
            if (color is String && color.trim().isNotEmpty) color.trim(),
        ],
        // Left empty rather than dropped: the vetting refuses a piece that
        // pairs with nothing and says why.
        pairsWithIds: [
          for (final id in _list(entry['pairsWith']))
            if (id is String && id.isNotEmpty) ItemId(id),
        ],
        rationale: rationale.trim(),
      ),
    );
  }

  return proposals;
}

List<Object?> _list(Object? value) => value is List ? value : const [];
