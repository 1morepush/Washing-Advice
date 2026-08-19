/// Pieces the wardrobe does not have, checked before anybody is told to look
/// for one.
///
/// The other half of the question [StyleVetting] answers: a light graphic tee
/// is asking for dark blue jeans, and if there are none the useful answer says
/// so rather than proposing the fourth-best trousers.
///
/// Not modelled as an outfit, because a suggested piece has no id — it cannot
/// be saved, worn or tapped through to, and a [StyledOutfit] with a hole in it
/// would break all three.
///
/// Three checks: the type must be one the wardrobe vocabulary knows, it must
/// name owned garments it goes with, and it must not describe something already
/// hanging up. Whether it is a *good* idea is the judgement being asked for and
/// is deliberately not checked. Nothing here costs a garment, so the checks
/// prefer letting a doubtful suggestion through to refusing a good one.
library;

import '../shared/ids.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/wardrobe_item.dart';

/// One piece as the model proposed it, before anything has checked it.
final class PieceProposal {
  const PieceProposal({
    required this.type,
    required this.colors,
    required this.pairsWithIds,
    required this.rationale,
  });

  /// What kind of thing it is, in the model's words. Resolved against
  /// [ItemType] by the vetting rather than trusted.
  final String type;

  /// How it should look, in plain words — 'dark blue', 'cream'. Free text: it
  /// describes something to go and find rather than a colour to compute with.
  final List<String> colors;

  /// The owned garments it was proposed to go with.
  final List<ItemId> pairsWithIds;

  /// Why, in the model's own words. Shown unabridged.
  final String rationale;
}

/// Why a proposed piece was thrown away.
enum PieceRefusal {
  /// Named a kind of garment the wardrobe vocabulary does not have.
  unknownType('Described something too vague to go and look for'),

  /// Named an owned garment that does not exist.
  unknownItem('Said it went with something not in your wardrobe'),

  /// Named an owned garment that is in the wash or otherwise not wearable.
  unavailable('Said it went with something not available to wear'),

  /// Suggested a piece on its own, with nothing of yours to wear it with.
  pairsWithNothing('Suggested something on its own'),

  /// Described a garment already hanging up.
  alreadyOwned('Suggested something you already have');

  const PieceRefusal(this.reason);

  final String reason;
}

/// A proposed piece that survived checking, with its pairings resolved.
final class SuggestedPiece {
  const SuggestedPiece({
    required this.type,
    required this.colors,
    required this.pairsWith,
    required this.rationale,
  });

  final ItemType type;
  final List<String> colors;

  /// The owned garments this would go with. Never empty: the pairing is what
  /// makes it advice rather than a shopping list.
  final List<WardrobeItem> pairsWith;

  final String rationale;

  /// e.g. `Dark blue jeans`. What to go and look for, in one line.
  String get description =>
      colors.isEmpty ? type.label : '${colors.join('/')} ${type.label}';

  /// Two suggestions of the same thing are one suggestion.
  String get signature =>
      '${type.name}|${(colors.map(_fold).toList()..sort()).join(',')}';
}

/// One proposal that did not survive, kept so the screen can say so.
final class RefusedPiece {
  const RefusedPiece({required this.proposal, required this.refusal});

  final PieceProposal proposal;
  final PieceRefusal refusal;
}

/// What checking a batch of proposed pieces produced.
final class SuggestedPieces {
  const SuggestedPieces({this.pieces = const [], this.refused = const []});

  final List<SuggestedPiece> pieces;
  final List<RefusedPiece> refused;

  bool get isEmpty => pieces.isEmpty;
}

/// Colour words that name the same colour twice.
///
/// Deliberately small, and only plain synonyms rather than neighbouring
/// shades: 'light blue' is not folded into 'blue', because a pale shirt and a
/// mid-blue one are different things to own.
const _synonyms = <String, String>{
  'navy': 'dark blue',
  'indigo': 'dark blue',
  'charcoal': 'dark grey',
  'gray': 'grey',
  'burgundy': 'dark red',
  'maroon': 'dark red',
  'cream': 'off-white',
  'ivory': 'off-white',
  'tan': 'beige',
  'khaki': 'beige',
};

/// One colour phrase, reduced to a comparable form.
String _fold(String color) {
  final cleaned = color.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  return _synonyms[cleaned] ?? cleaned;
}

/// Excluded because none of them answers "what would go with this shirt". A
/// stylist that suggested pyjamas would read as broken rather than bold.
const _notStylable = {
  ItemCategory.underwear,
  ItemCategory.sleepwear,
  ItemCategory.swimwear,
  ItemCategory.household,
};

/// The vocabulary a proposed piece may name, as plain labels.
///
/// Sent with the request rather than restated on the server, so what the model
/// may choose from and what this file resolves against cannot drift apart.
List<String> get stylableTypeLabels => [
      for (final type in ItemType.values)
        if (!_notStylable.contains(type.category)) type.label,
    ];

/// Checks proposed pieces against the wardrobe they were proposed for.
final class GapVetting {
  const GapVetting();

  SuggestedPieces vet(
    List<PieceProposal> proposals, {
    required List<WardrobeItem> wardrobe,
  }) {
    final byId = {for (final item in wardrobe) item.id: item};
    final kept = <SuggestedPiece>[];
    final refused = <RefusedPiece>[];
    final seen = <String>{};

    for (final proposal in proposals) {
      final (:piece, :refusal) = _check(proposal, byId, wardrobe);
      if (refusal != null || piece == null) {
        refused.add(
          RefusedPiece(
            proposal: proposal,
            refusal: refusal ?? PieceRefusal.unknownType,
          ),
        );
        continue;
      }

      if (seen.add(piece.signature)) kept.add(piece);
    }

    return SuggestedPieces(pieces: kept, refused: refused);
  }

  ({SuggestedPiece? piece, PieceRefusal? refusal}) _check(
    PieceProposal proposal,
    Map<ItemId, WardrobeItem> byId,
    List<WardrobeItem> wardrobe,
  ) {
    ({SuggestedPiece? piece, PieceRefusal? refusal}) no(PieceRefusal refusal) =>
        (piece: null, refusal: refusal);

    final type = _resolveType(proposal.type);
    if (type == null) return no(PieceRefusal.unknownType);

    if (proposal.pairsWithIds.isEmpty) {
      return no(PieceRefusal.pairsWithNothing);
    }

    final pairsWith = <WardrobeItem>[];
    for (final id in proposal.pairsWithIds) {
      final item = byId[id];
      if (item == null) return no(PieceRefusal.unknownItem);
      if (!item.lifecycle.isWearable) return no(PieceRefusal.unavailable);
      pairsWith.add(item);
    }

    final colors = [
      for (final color in proposal.colors)
        if (color.trim().isNotEmpty) color.trim(),
    ];

    if (_alreadyOwns(wardrobe, type: type, colors: colors)) {
      return no(PieceRefusal.alreadyOwned);
    }

    return (
      piece: SuggestedPiece(
        type: type,
        colors: colors,
        pairsWith: pairsWith,
        rationale: proposal.rationale,
      ),
      refusal: null,
    );
  }

  /// Whether the wardrobe already holds this thing in this colour.
  ///
  /// Whole phrases rather than loose words, so 'light blue' and 'dark blue'
  /// stay apart. A garment whose colour was never named matches nothing —
  /// silence is not sameness, as in the duplicate grouping — which errs
  /// towards showing a suggestion, the cheaper mistake of the two.
  bool _alreadyOwns(
    List<WardrobeItem> wardrobe, {
    required ItemType type,
    required List<String> colors,
  }) {
    if (colors.isEmpty) return false;
    final wanted = colors.map(_fold).toSet();

    return wardrobe.any((item) {
      if (item.type.value != type) return false;
      final owned = {
        for (final color in item.colors.value.colors)
          if (color.name case final String name) _fold(name),
      };
      return owned.intersection(wanted).isNotEmpty;
    });
  }

  /// The type this names, or null if it names nothing the wardrobe knows.
  ///
  /// Labels are what the model was given; enum names are accepted too, since
  /// it costs one lookup and salvages a suggestion that would be thrown away.
  ItemType? _resolveType(String raw) {
    final wanted = raw.toLowerCase().trim();
    if (wanted.isEmpty) return null;

    for (final type in ItemType.values) {
      if (_notStylable.contains(type.category)) continue;
      if (type.label.toLowerCase() == wanted ||
          type.name.toLowerCase() == wanted) {
        return type;
      }
    }
    return null;
  }
}
