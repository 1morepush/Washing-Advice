/// Checking pieces a model suggested the wardrobe does not have.
///
/// The judgement is the thing being asked for and nothing here second-guesses
/// it. What is checked is that the suggestion is something a person could act
/// on: a garment type that exists, anchored to clothes they own, and not
/// already hanging up.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16);

  WardrobeItem item(
    String id,
    ItemType type, {
    LifecycleState lifecycle = LifecycleState.active,
    List<ItemColor> colors = const [],
  }) {
    final built = WardrobeItem(
      id: ItemId(id),
      name: id,
      type: Confident(type, confidence: 0.95, source: Provenance.aiInference),
      composition: Confident(
        FabricComposition(const {Fiber.cotton: 100}),
        confidence: 0.9,
        source: Provenance.tagScan,
      ),
      colors: Confident(
        ColorPalette(
          colors.isEmpty ? [ItemColor.fromHex('#1F2A44')] : colors,
        ),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      lifecycle: lifecycle,
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return built.copyWith(care: const CareResolver().forItem(built).profile);
  }

  final tee = item('tee', ItemType.tShirt);
  final shirt = item('shirt', ItemType.dressShirt);
  final inWash = item(
    'washing',
    ItemType.tShirt,
    lifecycle: LifecycleState.beingWashed,
  );

  final wardrobe = [tee, shirt, inWash];

  PieceProposal proposal({
    String type = 'Jeans',
    List<String> colors = const ['dark blue'],
    List<String> pairsWith = const ['tee'],
    String rationale = 'The tee is asking for something with weight under it.',
  }) =>
      PieceProposal(
        type: type,
        colors: colors,
        pairsWithIds: [for (final id in pairsWith) ItemId(id)],
        rationale: rationale,
      );

  SuggestedPieces vet(
    List<PieceProposal> proposals, {
    List<WardrobeItem>? from,
  }) =>
      const GapVetting().vet(proposals, wardrobe: from ?? wardrobe);

  group('a suggestion has to be something you can act on', () {
    test('a piece that pairs with an owned garment survives', () {
      final result = vet([proposal()]);

      expect(result.pieces, hasLength(1));
      expect(result.pieces.single.type, ItemType.jeans);
      expect(result.pieces.single.description, 'dark blue Jeans');
      expect(result.pieces.single.pairsWith.single.id, tee.id);
    });

    test('the reason survives whole, in the model words', () {
      // Summarising it would throw away the only thing this feature has that
      // arithmetic does not.
      const said =
          'A mid-wash denim keeps the graphic reading as casual rather than '
          'fighting it, and the weight balances a thin jersey.';

      final result = vet([proposal(rationale: said)]);

      expect(result.pieces.single.rationale, said);
    });

    test('a kind of garment the wardrobe has no word for is refused', () {
      // The same invention guard the ids get. "A gorpcore silhouette" is not
      // something anyone can go and look for.
      final result = vet([proposal(type: 'gorpcore silhouette')]);

      expect(result.pieces, isEmpty);
      expect(result.refused.single.refusal, PieceRefusal.unknownType);
    });

    test('the enum name is accepted as well as the label', () {
      // Costs one lookup and turns a suggestion that would have been thrown
      // away into a usable one.
      final result = vet([proposal(type: 'longSleeveShirt')]);

      expect(result.pieces.single.type, ItemType.longSleeveShirt);
    });

    test('a piece suggested on its own is refused', () {
      // "Goes with the tee you own" is advice; "buy jeans" is not.
      final result = vet([proposal(pairsWith: const [])]);

      expect(result.refused.single.refusal, PieceRefusal.pairsWithNothing);
    });

    test('pairing with a garment that does not exist is refused', () {
      final result = vet([
        proposal(pairsWith: const ['invented'])
      ]);

      expect(result.refused.single.refusal, PieceRefusal.unknownItem);
    });

    test('pairing with something in the wash is refused', () {
      // Being told what goes with a shirt that is in the machine is the
      // failure that makes the whole feature look broken.
      final result = vet([
        proposal(pairsWith: const ['washing'])
      ]);

      expect(result.refused.single.refusal, PieceRefusal.unavailable);
    });
  });

  group('it must not suggest what is already hanging up', () {
    test('the same type in the same colour is refused', () {
      final owned = [
        tee,
        item(
          'blues',
          ItemType.jeans,
          colors: [ItemColor.fromHex('#24406E', name: 'dark blue')],
        ),
      ];

      final result = vet([proposal()], from: owned);

      expect(result.pieces, isEmpty);
      expect(result.refused.single.refusal, PieceRefusal.alreadyOwned);
    });

    test('navy on the rail is the dark blue being suggested', () {
      // Nobody writes "dark blue" on a pair of navy chinos.
      final owned = [
        tee,
        item(
          'navys',
          ItemType.jeans,
          colors: [ItemColor.fromHex('#1F2A44', name: 'Navy')],
        ),
      ];

      final result = vet([proposal()], from: owned);

      expect(result.refused.single.refusal, PieceRefusal.alreadyOwned);
    });

    test('a paler version of the same thing is not the same thing', () {
      // Matching on 'blue' alone would refuse a useful suggestion because a
      // light pair is hanging up.
      final owned = [
        tee,
        item(
          'pale',
          ItemType.jeans,
          colors: [ItemColor.fromHex('#9BB7D4', name: 'light blue')],
        ),
      ];

      final result = vet([proposal()], from: owned);

      expect(result.pieces, hasLength(1));
    });

    test('the same colour in a different garment is not the same thing', () {
      final owned = [
        tee,
        item(
          'trousers',
          ItemType.trousers,
          colors: [ItemColor.fromHex('#24406E', name: 'dark blue')],
        ),
      ];

      final result = vet([proposal()], from: owned);

      expect(result.pieces, hasLength(1));
    });

    test('a garment whose colour was never named blocks nothing', () {
      // Silence is not sameness: treating an unnamed colour as a match would
      // hide suggestions on the strength of missing data.
      final owned = [
        tee,
        item('unnamed', ItemType.jeans, colors: [ItemColor.fromHex('#24406E')]),
      ];

      final result = vet([proposal()], from: owned);

      expect(result.pieces, hasLength(1));
    });

    test('a suggestion with no colour at all is not refused as owned', () {
      // Nothing to check it against, and refusing on suspicion loses a fair
      // suggestion.
      final result = vet([proposal(type: 'Jacket', colors: const [])]);

      expect(result.pieces.single.description, 'Jacket');
    });
  });

  group('the batch as a whole', () {
    test('the same suggestion twice is shown once', () {
      final result = vet([proposal(), proposal()]);

      expect(result.pieces, hasLength(1));
    });

    test('two names for one colour count as the same suggestion', () {
      final result = vet([
        proposal(colors: const ['navy']),
        proposal(colors: const ['dark blue']),
      ]);

      expect(result.pieces, hasLength(1));
    });

    test('a refused piece does not take the good ones with it', () {
      final result = vet([
        proposal(type: 'nonsense'),
        proposal(),
        proposal(type: 'Sneakers', colors: const ['white']),
      ]);

      expect(result.pieces, hasLength(2));
      expect(result.refused, hasLength(1));
    });

    test('nothing proposed is empty rather than an error', () {
      expect(vet([]).isEmpty, isTrue);
    });
  });

  group('the vocabulary offered to the model', () {
    test('covers the clothes somebody would go and look for', () {
      expect(stylableTypeLabels, contains('Jeans'));
      expect(stylableTypeLabels, contains('Sneakers'));
      expect(stylableTypeLabels, contains('Blazer'));
    });

    test('leaves out what no stylist should be proposing', () {
      // A duvet cover is not an answer to "what goes with this shirt".
      expect(stylableTypeLabels, isNot(contains('Underwear')));
      expect(stylableTypeLabels, isNot(contains('Pajamas')));
      expect(stylableTypeLabels, isNot(contains('Swimwear')));
    });

    test('a type outside the vocabulary is refused even when it is real', () {
      // Underwear is a real ItemType, so the parser must not let it back in.
      final result = vet([proposal(type: 'Underwear')]);

      expect(result.refused.single.refusal, PieceRefusal.unknownType);
    });
  });
}
