/// Folding a re-scan into an item that already exists.
///
/// The whole risk in this feature is silent loss. A retake that quietly
/// reverted a hand correction, or dropped a field the old scan had filled in,
/// would be worse than no retake at all — the user would have no way to know it
/// had happened. So most of what is asserted here is what *survives*.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

final _later = testNow.add(const Duration(days: 7));

GarmentScanResult _scan({
  ItemType type = ItemType.tShirt,
  double typeConfidence = 0.9,
  Confident<FabricComposition>? composition,
  Confident<String>? brand,
  Confident<SleeveLength>? sleeveLength,
  Confident<Fit>? fit,
  Confident<StyleCut>? styleCut,
  Set<Season> seasons = const {},
  String? distinguishingText,
  List<ItemColor>? colors,
}) =>
    GarmentScanResult(
      type: Confident(
        type,
        confidence: typeConfidence,
        source: Provenance.aiInference,
      ),
      colors: Confident(
        ColorPalette(colors ?? [Colors.navy]),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      composition: composition,
      brand: brand,
      sleeveLength: sleeveLength,
      fit: fit,
      styleCut: styleCut,
      seasons: seasons,
      distinguishingText: distinguishingText,
    );

void main() {
  group('what a re-scan may change', () {
    test('a better look at the same garment replaces a weaker guess', () {
      // Both beliefs came from a photograph, so the more confident one wins —
      // which is the entire point of retaking a badly lit shot.
      final item = buildItem(type: ItemType.tShirt);
      expect(item.type.confidence, 0.95);

      final merged = item.mergeScan(
        _scan(type: ItemType.poloShirt, typeConfidence: 0.99),
        at: _later,
      );

      expect(merged.type.value, ItemType.poloShirt);
    });

    test('a hesitant new guess does not displace a confident old one', () {
      final item = buildItem(type: ItemType.tShirt);

      final merged = item.mergeScan(
        _scan(type: ItemType.poloShirt, typeConfidence: 0.4),
        at: _later,
      );

      expect(merged.type.value, ItemType.tShirt);
    });

    test('the timestamp moves, so sync sees the change', () {
      final merged = buildItem().mergeScan(_scan(), at: _later);

      expect(merged.updatedAt, _later);
    });
  });

  group('what a re-scan may not change', () {
    test('a correction the user made by hand survives', () {
      // The failure this prevents: someone fixes the brand, retakes the
      // photograph a week later for a better cutout, and finds their
      // correction reverted with no indication it ever happened.
      final item = buildItem(brand: 'Uniqlo');
      expect(item.brand!.source, Provenance.userEdited);

      final merged = item.mergeScan(
        _scan(
          brand: Confident(
            'Muji',
            confidence: 0.99,
            source: Provenance.aiInference,
          ),
        ),
        at: _later,
      );

      expect(merged.brand!.value, 'Uniqlo');
    });

    test('a fibre composition read off the label beats one guessed by eye', () {
      // A camera cannot see fibre content. The label can, and did.
      final item = buildItem(composition: {Fiber.wool: 100});

      final merged = item.mergeScan(
        _scan(
          composition: Confident(
            FabricComposition(const {Fiber.acrylic: 100}),
            confidence: 0.99,
            source: Provenance.aiInference,
          ),
        ),
        at: _later,
      );

      expect(merged.composition.value.percentages, {Fiber.wool: 100});
    });

    test('the name the user gave it', () {
      final item = buildItem(name: "Dad's old cricket jumper");

      final merged = item.mergeScan(_scan(), at: _later);

      expect(merged.name, "Dad's old cricket jumper");
    });

    test('anything the scan says nothing about', () {
      // A scan with no brand must not erase the brand already recorded. This
      // is the difference between "not stated" and "stated as nothing", and
      // getting it wrong here would quietly empty half the item.
      final item = buildItem(
        brand: 'Uniqlo',
        pattern: Pattern.striped,
        distinguishingText: 'NIRVANA',
        seasons: {Season.winter},
      );

      final merged = item.mergeScan(_scan(), at: _later);

      expect(merged.brand!.value, 'Uniqlo');
      expect(merged.pattern!.value, Pattern.striped);
      expect(merged.distinguishingText, 'NIRVANA');
      expect(merged.seasons, {Season.winter});
    });

    test('the photographs, which the caller attaches itself', () {
      final photo = ItemPhoto(
        uri: 'file:///front.jpg',
        role: PhotoRole.front,
        capturedAt: testNow,
      );
      final item = buildItem().copyWith(photos: PhotoSet([photo]));

      final merged = item.mergeScan(_scan(), at: _later);

      expect(merged.photos.photos, [photo]);
    });
  });

  group('filling in what was missing', () {
    test('a field the first scan never produced is taken from this one', () {
      final item = buildItem();
      expect(item.brand, isNull);
      expect(item.sleeveLength, isNull);

      final merged = item.mergeScan(
        _scan(
          brand: Confident(
            'Muji',
            confidence: 0.8,
            source: Provenance.aiInference,
          ),
          sleeveLength: Confident(
            SleeveLength.longSleeve,
            confidence: 0.8,
            source: Provenance.aiInference,
          ),
          seasons: {Season.autumn},
          distinguishingText: 'NIRVANA',
        ),
        at: _later,
      );

      expect(merged.brand!.value, 'Muji');
      expect(merged.sleeveLength, SleeveLength.longSleeve);
      expect(merged.seasons, {Season.autumn});
      expect(merged.distinguishingText, 'NIRVANA');
    });

    test('a plain field already set is left alone', () {
      // Sleeve length carries no confidence on the item, so there is nothing
      // to arbitrate with — and overwriting on a coin toss loses information
      // that may have come from a person.
      final item = buildItem().copyWith(sleeveLength: SleeveLength.shortSleeve);

      final merged = item.mergeScan(
        _scan(
          sleeveLength: Confident(
            SleeveLength.longSleeve,
            confidence: 0.99,
            source: Provenance.aiInference,
          ),
        ),
        at: _later,
      );

      expect(merged.sleeveLength, SleeveLength.shortSleeve);
    });
  });

  test('care is left for the caller to re-derive', () {
    // Re-deriving here would mean doing it without the scanned care label,
    // which downgrades a manufacturer's instruction to a generic rule. The
    // caller goes through `CareResolver.forItem`, which carries the label.
    final item = buildItem(careInstructions: handWashCare);

    final merged = item.mergeScan(
      _scan(
        composition: Confident(
          FabricComposition(const {Fiber.polyester: 100}),
          confidence: 0.99,
          source: Provenance.aiInference,
        ),
      ),
      at: _later,
    );

    expect(merged.care.instructions, handWashCare);
  });
}
