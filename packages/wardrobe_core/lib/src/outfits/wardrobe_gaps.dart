/// Pieces the wardrobe does not have, checked before anybody is told to look
/// for one.
///
/// The stylist proposes outfits from what is owned. This is the other half of
/// the same question: a light graphic tee is asking for dark blue jeans, and if
/// there are none in the wardrobe then the most useful thing to say is so —
/// naming the gap rather than quietly proposing the fourth-best trousers.
///
/// ## Why this is not an outfit
///
/// [StyleVetting]'s first rule is that every id must exist, because an invented
/// id puts a garment on screen that cannot be opened. A suggested piece has no
/// id at all: it is a description of something that does not exist here yet. It
/// cannot be saved as an outfit, cannot be recorded as worn, and cannot be
/// tapped through to. Modelling it as a [StyledOutfit] with a hole in it would
/// break all three, so it is its own type and the screen keeps it apart.
///
/// ## What is checked
///
/// * the type must be one the wardrobe vocabulary knows — the same invention
///   guard the ids get, because "a pair of gorpcore silhouettes" is not
///   something anyone can go and look for;
/// * it must name garments it goes with, and those must exist and be wearable.
///   A piece that pairs with nothing is a shopping list, not styling advice,
///   and the whole value here is the pairing;
/// * it must not describe something already hanging up. Being told to find
///   dark blue jeans by an app that can see two pairs is the failure that makes
///   this look stupid.
///
/// ## What is deliberately not checked
///
/// Whether it is a *good* idea. That is the judgement being asked for, and this
/// file second-guessing it would defeat the point — the same line [StyleVetting]
/// draws. Nothing here costs a garment: the worst a wrong suggestion does is
/// waste a glance, which is why the checks below prefer letting a doubtful one
/// through to refusing a good one.
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

  /// How it should look, in plain words — 'dark blue', 'cream'.
  ///
  /// Free text on purpose. This is a description of something to go and find,
  /// not a colour the app is going to compute with, and 'washed indigo' is more
  /// use to somebody standing in a shop than the nearest hex code.
  final List<String> colors;

  /// The owned garments it was proposed to go with.
  final List<ItemId> pairsWithIds;

  /// Why, in the model's own words. Shown unabridged for the same reason a
  /// styled outfit's is.
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

  /// The owned garments this would go with. Never empty — a piece that pairs
  /// with nothing is refused, because the pairing is the whole point.
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
/// Small and deliberately so. This exists for one job — recognising that the
/// navy trousers already hanging up are the 'dark blue' ones being suggested —
/// and every entry earns its place by being a plain synonym rather than a
/// neighbouring shade. 'Light blue' is not folded into 'blue', because a pale
/// shirt and a mid-blue one are genuinely different things to own.
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

/// The garment types it makes sense to suggest somebody go and find.
///
/// Underwear, sleepwear, swimwear and household linen are all things people
/// own; none of them is an answer to "what would go with this shirt", and a
/// stylist that suggested pyjamas would read as broken rather than as bold.
const _notStylable = {
  ItemCategory.underwear,
  ItemCategory.sleepwear,
  ItemCategory.swimwear,
  ItemCategory.household,
};

/// The vocabulary a proposed piece may name, as plain labels.
///
/// Sent to the model with the request rather than restated on the server, so
/// the list it may choose from and the list this file resolves against are the
/// same list. A type added to [ItemType] shows up in both without anybody
/// remembering to update a copy in another language.
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
  /// Whole phrases rather than loose words, so 'light blue' and 'dark blue' stay
  /// apart — matching on the shared word 'blue' would refuse a genuinely useful
  /// suggestion because a paler version of it is hanging up.
  ///
  /// A garment whose colour was never named cannot match anything: silence is
  /// not sameness, the same rule the duplicate grouping follows. The wrong way
  /// round here is cheap — a suggestion for something already owned costs one
  /// glance to dismiss, where a refused good one is never seen at all.
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
  /// Labels first, because that is what the model was given and what it is
  /// asked to copy. Enum names are accepted too: it costs one lookup and turns
  /// a suggestion that would have been thrown away into a usable one.
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
