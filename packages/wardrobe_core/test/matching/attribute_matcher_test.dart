import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  const matcher = AttributeMatcher();
  const resolver = MatchResolver();

  final greyNikeHoodie = buildItem(
    id: 'grey-nike-hoodie',
    name: 'Grey Nike hoodie',
    type: ItemType.hoodie,
    composition: {Fiber.cotton: 80, Fiber.polyester: 20},
    colors: [Colors.grey],
    brand: 'Nike',
    sizeLabel: 'M',
  );
  final navyAdidasHoodie = buildItem(
    id: 'navy-adidas-hoodie',
    name: 'Navy Adidas hoodie',
    type: ItemType.hoodie,
    composition: {Fiber.polyester: 100},
    colors: [Colors.navy],
    brand: 'Adidas',
    sizeLabel: 'L',
  );
  final whiteTee = buildItem(
    id: 'white-tee',
    type: ItemType.tShirt,
    colors: [Colors.white],
  );

  final wardrobe = [greyNikeHoodie, navyAdidasHoodie, whiteTee];

  group('ranking', () {
    test('recognises the item it was built from', () {
      final probe = GarmentFingerprint.of(greyNikeHoodie);
      final ranked = matcher.rank(probe, wardrobe);
      expect(ranked.first.itemId, greyNikeHoodie.id);
      expect(ranked.first.score, greaterThan(0.95));
    });

    test('never matches across garment types', () {
      // A hoodie is never a mis-scan of a t-shirt, however similar the colour.
      final probe = GarmentFingerprint.of(whiteTee);
      final ranked = matcher.rank(probe, wardrobe);
      expect(ranked.map((c) => c.itemId), [whiteTee.id]);
    });

    test('ranks the right hoodie above the wrong one', () {
      final probe = GarmentFingerprint.of(greyNikeHoodie);
      final ranked = matcher.rank(probe, wardrobe);
      expect(ranked.first.itemId, greyNikeHoodie.id);
      expect(ranked[1].itemId, navyAdidasHoodie.id);
      expect(ranked.first.score - ranked[1].score, greaterThan(0.2));
    });

    test('reports how each signal contributed', () {
      final ranked = matcher.rank(
        GarmentFingerprint.of(greyNikeHoodie),
        wardrobe,
      );
      expect(
        ranked.first.contributions.keys,
        containsAll(['type', 'color', 'brand', 'composition', 'size']),
      );
    });

    test('an unknown brand neither helps nor punishes', () {
      final noBrand = GarmentFingerprint(
        type: ItemType.hoodie,
        colors: ColorPalette([Colors.grey]),
        composition: FabricComposition({Fiber.cotton: 80, Fiber.polyester: 20}),
        sizeLabel: 'M',
      );
      final ranked = matcher.rank(noBrand, wardrobe);
      expect(ranked.first.itemId, greyNikeHoodie.id);
      expect(ranked.first.contributions['brand'], 0.5);
    });

    test('visible text separates otherwise identical garments', () {
      // Two black cotton tees are indistinguishable on attributes alone. A
      // printed slogan is what breaks the tie.
      final plainBlackTee =
          buildItem(id: 'plain-black', colors: [Colors.black]);
      final bandBlackTee = buildItem(
        id: 'band-black',
        colors: [Colors.black],
        distinguishingText: 'Nirvana',
      );

      final probe = GarmentFingerprint(
        type: ItemType.tShirt,
        colors: ColorPalette([Colors.black]),
        composition: FabricComposition({Fiber.cotton: 100}),
        distinguishingText: 'Nirvana',
      );

      final ranked = matcher.rank(probe, [plainBlackTee, bandBlackTee]);
      expect(ranked.first.itemId.value, 'band-black');
      expect(ranked.first.contributions['text'], 1.0);
      // The plain tee has no text at all, so the signal simply does not apply.
      expect(ranked[1].contributions.containsKey('text'), isFalse);
      expect(ranked.first.score, greaterThan(ranked[1].score));
    });

    test('a different slogan pushes a garment down the ranking', () {
      final nirvanaTee = buildItem(
        id: 'nirvana',
        colors: [Colors.black],
        distinguishingText: 'Nirvana',
      );
      final metallicaTee = buildItem(
        id: 'metallica',
        colors: [Colors.black],
        distinguishingText: 'Metallica',
      );

      final probe = GarmentFingerprint.of(nirvanaTee);
      final ranked = matcher.rank(probe, [metallicaTee, nirvanaTee]);
      expect(ranked.first.itemId.value, 'nirvana');
      expect(ranked[1].contributions['text'], 0.0);
    });
  });

  group('decisions', () {
    test('an exact match is recognised without asking', () {
      final ranked = matcher.rank(
        GarmentFingerprint.of(greyNikeHoodie),
        wardrobe,
      );
      final decision = resolver.resolve(ranked);
      expect(decision, isA<RecognisedItem>());
      expect((decision as RecognisedItem).itemId, greyNikeHoodie.id);
    });

    test('nothing similar is treated as a new item', () {
      final probe = GarmentFingerprint(
        type: ItemType.jeans,
        colors: ColorPalette([Colors.navy]),
        composition: FabricComposition({Fiber.cotton: 100}),
      );
      final decision = resolver.resolve(matcher.rank(probe, wardrobe));
      expect(decision, isA<UnrecognisedItem>());
    });

    test('two near-identical garments force a confirmation', () {
      // The honest limit of attribute matching: three identical black tees
      // cannot be told apart, so the app must ask rather than guess.
      final identical = [
        buildItem(id: 'tee-1', colors: [Colors.black], brand: 'Uniqlo'),
        buildItem(id: 'tee-2', colors: [Colors.black], brand: 'Uniqlo'),
        buildItem(id: 'tee-3', colors: [Colors.black], brand: 'Uniqlo'),
      ];
      final probe = GarmentFingerprint.of(identical.first);
      final decision = resolver.resolve(matcher.rank(probe, identical));

      expect(decision, isA<NeedsConfirmation>());
      expect(
        (decision as NeedsConfirmation).reason,
        contains('almost identical'),
      );
      expect(decision.candidates, hasLength(3));
    });

    test('an empty wardrobe yields an unrecognised item', () {
      expect(resolver.resolve(const []), isA<UnrecognisedItem>());
    });
  });

  group('MatcherChain', () {
    test('a single matcher passes straight through', () {
      const chain = MatcherChain([AttributeMatcher()]);
      final probe = GarmentFingerprint.of(greyNikeHoodie);
      expect(
        chain.rank(probe, wardrobe).map((c) => c.itemId),
        matcher.rank(probe, wardrobe).map((c) => c.itemId),
      );
    });

    test('an empty chain ranks nothing', () {
      const chain = MatcherChain([]);
      expect(chain.rank(GarmentFingerprint.of(whiteTee), wardrobe), isEmpty);
    });

    test('combines two matchers by weight', () {
      // Stands in for the future embedding matcher: a second opinion that
      // disagrees should move the combined score without any caller changing.
      final chain = MatcherChain([
        const AttributeMatcher(weight: 1.0),
        _ConstantMatcher(score: 0.0, weight: 1.0),
      ]);
      final probe = GarmentFingerprint.of(greyNikeHoodie);

      final alone = matcher.rank(probe, wardrobe).first.score;
      final combined = chain.rank(probe, wardrobe).first.score;

      expect(combined, closeTo(alone / 2, 1e-9));
      expect(
        chain.rank(probe, wardrobe).first.contributions.keys,
        containsAll(['attributes', 'constant']),
      );
    });
  });

  group('Embedding', () {
    test('an identical vector has cosine similarity 1', () {
      const a = Embedding([1, 2, 3], model: 'test');
      expect(Embedding.cosineSimilarity(a, a), closeTo(1.0, 1e-6));
    });

    test('orthogonal vectors have similarity 0', () {
      const a = Embedding([1, 0], model: 'test');
      const b = Embedding([0, 1], model: 'test');
      expect(Embedding.cosineSimilarity(a, b), closeTo(0.0, 1e-9));
    });

    test('vectors from different models are not comparable', () {
      // Comparing across models silently produces meaningless numbers, so the
      // API refuses rather than returning a plausible-looking score.
      const a = Embedding([1, 0], model: 'clip');
      const b = Embedding([1, 0], model: 'siglip');
      expect(Embedding.cosineSimilarity(a, b), isNull);
    });

    test('mismatched dimensions are not comparable', () {
      const a = Embedding([1, 0], model: 'test');
      const b = Embedding([1, 0, 0], model: 'test');
      expect(Embedding.cosineSimilarity(a, b), isNull);
    });

    test('survives a JSON round trip', () {
      const a = Embedding([0.5, -0.25], model: 'test');
      final restored = Embedding.fromJson(a.toJson());
      expect(restored.values, a.values);
      expect(restored.model, a.model);
    });
  });
}

/// A stand-in second matcher, used to verify chain weighting.
final class _ConstantMatcher implements ItemMatcher {
  const _ConstantMatcher({required this.score, required this.weight});

  final double score;

  @override
  final double weight;

  @override
  String get name => 'constant';

  @override
  List<MatchCandidate> rank(
    GarmentFingerprint probe,
    Iterable<WardrobeItem> candidates,
  ) =>
      [
        for (final item in candidates)
          MatchCandidate(itemId: item.id, score: score),
      ];
}
