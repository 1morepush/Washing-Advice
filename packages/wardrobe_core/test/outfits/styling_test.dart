/// Checking outfits a model proposed.
///
/// The judgement is deliberately delegated — pattern, texture and proportion
/// are what the rule-based builder cannot do and a model can. What is *not*
/// delegated is the facts, and every test here is about a proposal that would
/// have put something on screen the wardrobe cannot back up.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);

  WardrobeItem item(
    String id,
    ItemType type, {
    LifecycleState lifecycle = LifecycleState.active,
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
        ColorPalette([ItemColor.fromHex('#1F2A44')]),
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

  final shirt = item('shirt', ItemType.dressShirt);
  final tee = item('tee', ItemType.tShirt);
  final chinos = item('chinos', ItemType.chinos);
  final jeans = item('jeans', ItemType.jeans);
  final shoes = item('shoes', ItemType.sneakers);
  final jacket = item('jacket', ItemType.jacket);
  final dress = item('dress', ItemType.dress);
  final scarf = item('scarf', ItemType.scarf);
  final inWash = item(
    'washing',
    ItemType.dressShirt,
    lifecycle: LifecycleState.beingWashed,
  );

  final wardrobe = [
    shirt,
    tee,
    chinos,
    jeans,
    shoes,
    jacket,
    dress,
    scarf,
    inWash,
  ];

  StyledOutfits vet(List<List<String>> proposals) => const StyleVetting().vet([
        for (final ids in proposals)
          StyleProposal(
            itemIds: [for (final id in ids) ItemId(id)],
            rationale: 'because it works',
          ),
      ], wardrobe: wardrobe);

  test('a sensible outfit survives', () {
    final result = vet([
      ['shirt', 'chinos', 'shoes'],
    ]);

    expect(result.outfits, hasLength(1));
    expect(result.outfits.single.items, hasLength(3));
    expect(result.refused, isEmpty);
  });

  test('the reason is carried through in the model\'s own words', () {
    // The whole point of asking. A suggestion that hid its reasoning would be
    // asking to be obeyed rather than considered.
    final result = const StyleVetting().vet([
      const StyleProposal(
        itemIds: [ItemId('shirt'), ItemId('chinos')],
        rationale: 'The chinos soften a formal shirt into something weekday.',
      ),
    ], wardrobe: wardrobe);

    expect(
      result.outfits.single.rationale,
      'The chinos soften a formal shirt into something weekday.',
    );
  });

  test('a garment that does not exist is refused', () {
    // A model returning a plausible id it invented would otherwise put a
    // garment on the screen that cannot be opened.
    final result = vet([
      ['shirt', 'chinos', 'imaginary-belt'],
    ]);

    expect(result.outfits, isEmpty);
    expect(result.refused.single.refusal, StyleRefusal.unknownItem);
  });

  test('a garment in the machine is refused', () {
    // The one failure that makes the whole feature look broken: being told to
    // wear the shirt that is currently going round in the drum.
    final result = vet([
      ['washing', 'chinos', 'shoes'],
    ]);

    expect(result.refused.single.refusal, StyleRefusal.unavailable);
  });

  test('two tops are refused', () {
    final result = vet([
      ['shirt', 'tee', 'chinos'],
    ]);

    expect(result.refused.single.refusal, StyleRefusal.conflictingLayers);
  });

  test('two pairs of trousers are refused', () {
    final result = vet([
      ['shirt', 'chinos', 'jeans'],
    ]);

    expect(result.refused.single.refusal, StyleRefusal.conflictingLayers);
  });

  test('a dress with trousers is refused', () {
    // A full-body garment is the top and the bottom at once.
    final result = vet([
      ['dress', 'chinos'],
    ]);

    expect(result.refused.single.refusal, StyleRefusal.conflictingLayers);
  });

  test('but a dress on its own is an outfit', () {
    final result = vet([
      ['dress', 'shoes'],
    ]);

    expect(result.outfits, hasLength(1));
  });

  test('a jacket over a shirt is layering, not a conflict', () {
    // Outerwear is deliberately not exclusive: forbidding a second layer would
    // be the code overruling the judgement it asked for.
    final result = vet([
      ['shirt', 'chinos', 'jacket', 'shoes'],
    ]);

    expect(result.outfits, hasLength(1));
  });

  test('accessories alone are not an outfit', () {
    final result = vet([
      ['scarf', 'shoes'],
    ]);

    expect(result.refused.single.refusal, StyleRefusal.notAnOutfit);
  });

  test('a top with no bottom is not an outfit', () {
    final result = vet([
      ['shirt', 'shoes'],
    ]);

    expect(result.refused.single.refusal, StyleRefusal.notAnOutfit);
  });

  test('one garment is not an outfit', () {
    final result = vet([
      ['dress'],
    ]);

    expect(result.refused.single.refusal, StyleRefusal.notAnOutfit);
  });

  test('the same outfit proposed twice is shown once', () {
    // A model asked for five ideas can repeat itself, and one suggestion shown
    // five times is the failure the rule-based builder already guards against.
    final result = vet([
      ['shirt', 'chinos'],
      ['chinos', 'shirt'],
    ]);

    expect(result.outfits, hasLength(1));
  });

  test('one bad proposal does not take the good ones with it', () {
    final result = vet([
      ['shirt', 'chinos'],
      ['shirt', 'tee', 'chinos'],
      ['dress', 'shoes'],
    ]);

    expect(result.outfits, hasLength(2));
    expect(result.refused, hasLength(1));
  });

  test('nothing usable is an empty answer rather than an error', () {
    final result = vet([
      ['scarf'],
    ]);

    expect(result.isEmpty, isTrue);
    expect(result.refused, hasLength(1));
  });
}
