import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';
import '../support/selling_fixtures.dart';

final now = DateTime.utc(2026, 10, 17, 14);

ItemPhoto itemPhoto(
  String uri,
  PhotoRole role, {
  String? cutout,
  bool primary = false,
}) =>
    ItemPhoto(
      uri: uri,
      role: role,
      capturedAt: DateTime.utc(2026, 1, 1),
      cutoutUri: cutout,
      isPrimary: primary,
    );

ListingFacts facts({
  String title = 'Nike vintage crewneck sweatshirt grey',
  ItemType itemType = ItemType.sweatshirt,
  Confident<String>? brand,
  List<String> colors = const ['Grey'],
  String? material,
  Confident<String>? sizeOnTag,
  List<String> styleWords = const ['vintage', 'crewneck'],
  String? era = '90s',
  List<String> visibleFlaws = const [],
}) =>
    ListingFacts(
      title: title,
      itemType: itemType,
      brand: brand,
      colors: colors,
      material: material,
      sizeOnTag: sizeOnTag,
      styleWords: styleWords,
      era: era,
      visibleFlaws: visibleFlaws,
      searchQueries: const SearchQueries(
        depop: 'Nike vintage crewneck sweatshirt grey',
        retail: 'Nike Club Fleece crew sweatshirt grey',
      ),
    );

Confident<String> read(String value, [double confidence = 0.9]) =>
    Confident(value, confidence: confidence, source: Provenance.aiInference);

void main() {
  group('Listing.fromFacts', () {
    test('takes what the photographs showed', () {
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: facts(
          brand: read('Nike'),
          material: '80% cotton, 20% polyester',
          sizeOnTag: read('M'),
          visibleFlaws: const ['small mark on the left cuff'],
        ),
      );

      expect(listing.id, const ListingId('l-1'));
      expect(listing.title, 'Nike vintage crewneck sweatshirt grey');
      expect(listing.itemType, ItemType.sweatshirt);
      expect(listing.brand, 'Nike');
      expect(listing.sizeLabel, 'M');
      expect(listing.colours, [DepopColour.grey]);
      expect(listing.material, '80% cotton, 20% polyester');
      expect(listing.flaws, ['small mark on the left cuff']);
      expect(listing.styleWords, ['vintage', 'crewneck']);
      expect(listing.era, '90s');
    });

    test('is a draft made now, belonging to no garment', () {
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: facts(),
      );

      expect(listing.status, ListingStatus.draft);
      expect(listing.createdAt, now);
      expect(listing.updatedAt, now);
      expect(listing.itemId, isNull);
    });

    test('grades nothing and prices nothing', () {
      // A photograph cannot say how worn something is, and the price comes
      // from evidence the person looks at.
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: facts(brand: read('Nike')),
      );

      expect(listing.condition, isNull);
      expect(listing.priceCents, isNull);
      expect(listing.department, isNull);
      expect(listing.priceSearch, isNull);
      expect(listing.notes, isNull);
    });

    test('keeps the facts, so the editor can show how sure the reading was',
        () {
      final read = facts(
          brand: Confident(
        'Nike',
        confidence: 0.4,
        source: Provenance.aiInference,
      ));
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: read,
      );

      expect(listing.facts, read);
      expect(listing.facts!.brand!.confidence, 0.4);
      expect(listing.facts!.brand!.needsConfirmation, isFalse);
    });

    test('leaves out a brand, size or material the photographs did not show',
        () {
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: facts(),
      );

      expect(listing.brand, isNull);
      expect(listing.sizeLabel, isNull);
      expect(listing.material, isNull);
    });

    test('turns colour names into Depop\'s colours', () {
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: facts(colors: const ['Charcoal', 'Cream']),
      );

      expect(listing.colours, [DepopColour.grey, DepopColour.cream]);
    });

    test('three colours is Multi', () {
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: facts(colors: const ['Red', 'White', 'Blue']),
      );

      expect(listing.colours, [DepopColour.multi]);
    });

    test('takes the photographs it was given, cover first, up to the limit',
        () {
      final photos = [
        for (var i = 0; i < 10; i++)
          ListingPhoto(uri: 'store://$i.jpg', shot: ListingShot.other),
      ];
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: facts(),
        photos: photos,
      );

      expect(listing.photos, hasLength(depopPhotoLimit));
      expect(listing.photos.first.uri, 'store://0.jpg');
      expect(listing.photos.last.uri, 'store://${depopPhotoLimit - 1}.jpg');
    });

    test('a draft from facts can be searched for prices straight away', () {
      final listing = Listing.fromFacts(
        id: const ListingId('l-1'),
        now: now,
        facts: facts(),
      );

      expect(listing.canLookUpPrices, isTrue);
      expect(
        listing.searchQueries!.retail,
        'Nike Club Fleece crew sweatshirt grey',
      );
    });
  });

  group('Listing.empty', () {
    test('is blank: no title, no type, nothing filled in', () {
      final listing = Listing.empty(id: const ListingId('l-2'), now: now);

      expect(listing.id, const ListingId('l-2'));
      expect(listing.status, ListingStatus.draft);
      expect(listing.title, '');
      expect(listing.itemType, ItemType.other);
      expect(listing.brand, isNull);
      expect(listing.sizeLabel, isNull);
      expect(listing.condition, isNull);
      expect(listing.department, isNull);
      expect(listing.colours, isEmpty);
      expect(listing.material, isNull);
      expect(listing.measurements.isEmpty, isTrue);
      expect(listing.flaws, isEmpty);
      expect(listing.styleWords, isEmpty);
      expect(listing.era, isNull);
      expect(listing.priceCents, isNull);
      expect(listing.facts, isNull);
      expect(listing.itemId, isNull);
      expect(listing.createdAt, now);
      expect(listing.updatedAt, now);
    });

    test('is a valid draft that can be saved and read back', () {
      final listing = Listing.empty(id: const ListingId('l-2'), now: now);

      expect(Listing.fromJson(viaText(listing.toJson())), listing);
    });

    test('keeps the photographs it was given, up to the limit', () {
      final photos = [
        for (var i = 0; i < 9; i++)
          ListingPhoto(uri: 'store://$i.jpg', shot: ListingShot.cover),
      ];
      final listing = Listing.empty(
        id: const ListingId('l-2'),
        now: now,
        photos: photos,
      );

      expect(listing.photos, hasLength(depopPhotoLimit));
    });

    test('cannot be searched until it has a title', () {
      final blank = Listing.empty(id: const ListingId('l-2'), now: now);

      expect(blank.canLookUpPrices, isFalse);
      expect(
          blank.copyWith(title: 'Levi\'s 501 jeans').canLookUpPrices, isTrue);
    });

    test('asks for every photograph on the checklist', () {
      final blank = Listing.empty(id: const ListingId('l-2'), now: now);

      expect(blank.missingShots, hasLength(4));
    });
  });

  group('Listing.fromGarment', () {
    WardrobeItem hoodie({
      String? brand = 'Nike',
      String? sizeLabel = 'L',
      List<ItemColor>? colors,
      ItemType type = ItemType.hoodie,
      int timesWorn = 10,
      ConditionAssessment? condition,
    }) =>
        buildItem(
          id: 'hoodie-1',
          type: type,
          brand: brand,
          sizeLabel: sizeLabel,
          colors: colors ?? [Colors.charcoal],
          composition: const {Fiber.cotton: 80, Fiber.polyester: 20},
          usage: UsageStats(timesWorn: timesWorn),
          condition: condition,
        );

    Listing fromGarment(WardrobeItem item, {ListingFacts? facts}) =>
        Listing.fromGarment(
          id: const ListingId('l-3'),
          now: now,
          item: item,
          facts: facts,
        );

    test('remembers which garment it came from', () {
      expect(fromGarment(hoodie()).itemId, const ItemId('hoodie-1'));
    });

    test('is a draft made now', () {
      final listing = fromGarment(hoodie());

      expect(listing.id, const ListingId('l-3'));
      expect(listing.status, ListingStatus.draft);
      expect(listing.createdAt, now);
      expect(listing.updatedAt, now);
    });

    test('takes the type, brand, size, colours and fabric from the wardrobe',
        () {
      final listing = fromGarment(hoodie());

      expect(listing.itemType, ItemType.hoodie);
      expect(listing.brand, 'Nike');
      expect(listing.sizeLabel, 'L');
      expect(listing.colours, [DepopColour.grey]);
      expect(listing.material, '80% Cotton, 20% Polyester');
    });

    group('what the wardrobe knows wins', () {
      final disagreeing = facts(
        title: 'Adidas crewneck sweatshirt',
        itemType: ItemType.sweatshirt,
        brand: read('Adidas'),
        sizeOnTag: read('S'),
        colors: const ['Red'],
        material: '100% polyester',
      );

      test('over the type the photographs suggested', () {
        expect(
          fromGarment(hoodie(), facts: disagreeing).itemType,
          ItemType.hoodie,
        );
      });

      test('over the brand the photographs suggested', () {
        expect(fromGarment(hoodie(), facts: disagreeing).brand, 'Nike');
      });

      test('over the size the photographs showed', () {
        expect(fromGarment(hoodie(), facts: disagreeing).sizeLabel, 'L');
      });

      test('over the colours the photographs suggested', () {
        expect(
          fromGarment(hoodie(), facts: disagreeing).colours,
          [DepopColour.grey],
        );
      });

      test('over the material the photographs showed', () {
        expect(
          fromGarment(hoodie(), facts: disagreeing).material,
          '80% Cotton, 20% Polyester',
        );
      });
    });

    group('the facts fill what the wardrobe lacks', () {
      test('the brand', () {
        final listing = fromGarment(
          hoodie(brand: null),
          facts: facts(brand: read('Champion')),
        );

        expect(listing.brand, 'Champion');
      });

      test('the size', () {
        final listing = fromGarment(
          hoodie(sizeLabel: null),
          facts: facts(sizeOnTag: read('XL')),
        );

        expect(listing.sizeLabel, 'XL');
      });

      test('the colours, when the garment has no colour names', () {
        final listing = fromGarment(
          hoodie(colors: [ItemColor.fromHex('#1F2A44')]),
          facts: facts(colors: const ['Navy']),
        );

        expect(listing.colours, [DepopColour.navy]);
      });

      test('a brand or size that is blank counts as lacking', () {
        final listing = fromGarment(
          hoodie(brand: '   ', sizeLabel: ' '),
          facts: facts(brand: read('Champion'), sizeOnTag: read('XL')),
        );

        expect(listing.brand, 'Champion');
        expect(listing.sizeLabel, 'XL');
      });

      test('the title, style words and era, which a wardrobe never has', () {
        final listing = fromGarment(hoodie(), facts: facts());

        expect(listing.title, 'Nike vintage crewneck sweatshirt grey');
        expect(listing.styleWords, ['vintage', 'crewneck']);
        expect(listing.era, '90s');
      });

      test('nothing, when the wardrobe has no brand and the facts none either',
          () {
        final listing = fromGarment(hoodie(brand: null), facts: facts());

        expect(listing.brand, isNull);
      });
    });

    group('the fabric', () {
      WardrobeItem withComposition(Provenance source, {bool empty = false}) =>
          hoodie().copyWith(
            composition: Confident(
              empty
                  ? FabricComposition.unknown()
                  : FabricComposition(const {Fiber.cotton: 100}),
              confidence: 0.9,
              source: source,
            ),
          );

      test('read off a care label is stated', () {
        expect(
          fromGarment(withComposition(Provenance.tagScan)).material,
          '100% Cotton',
        );
      });

      test('typed in by the person is stated', () {
        expect(
          fromGarment(withComposition(Provenance.userEdited)).material,
          '100% Cotton',
        );
      });

      test('guessed from a photograph is not something to sell on', () {
        expect(fromGarment(withComposition(Provenance.aiInference)).material,
            isNull);
        expect(
            fromGarment(withComposition(Provenance.fallbackDefault)).material,
            isNull);
      });

      test('a guess is replaced by what a photographed label showed', () {
        final listing = fromGarment(
          withComposition(Provenance.aiInference),
          facts: facts(material: '100% organic cotton'),
        );

        expect(listing.material, '100% organic cotton');
      });

      test('an unknown composition is nothing, not "Unknown composition"', () {
        final listing = fromGarment(
          withComposition(Provenance.tagScan, empty: true),
        );

        expect(listing.material, isNull);
      });
    });

    group('the title', () {
      test('is the one the photographs produced', () {
        expect(
          fromGarment(hoodie(), facts: facts(title: 'Nike Club hoodie navy'))
              .title,
          'Nike Club hoodie navy',
        );
      });

      test(
          'is built from the wardrobe when the facts came back with a blank one',
          () {
        expect(
          fromGarment(hoodie(), facts: facts(title: '  ')).title,
          'Nike hoodie charcoal',
        );
      });

      test('is built from brand, type and colour when there are no facts', () {
        expect(fromGarment(hoodie()).title, 'Nike hoodie charcoal');
      });

      test('has no brand in it when there is none', () {
        expect(fromGarment(hoodie(brand: null)).title, 'hoodie charcoal');
      });

      test('has no type in it when the type is just Other', () {
        expect(
          fromGarment(hoodie(type: ItemType.other)).title,
          'Nike charcoal',
        );
      });

      test('has no colour in it when the colour has no name', () {
        final listing = fromGarment(
          hoodie(colors: [ItemColor.fromHex('#1F2A44')]),
        );

        expect(listing.title, 'Nike hoodie');
      });

      test('is not a hex code when the colour was named after itself', () {
        final listing = fromGarment(
          hoodie(colors: [ItemColor.fromHex('#1F2A44', name: '#1F2A44')]),
        );

        expect(listing.title, 'Nike hoodie');
        expect(listing.colours, isEmpty);
      });

      test('is empty when there is nothing to build it from', () {
        final listing = fromGarment(
          hoodie(
            brand: null,
            type: ItemType.other,
            colors: [ItemColor.fromHex('#1F2A44')],
          ),
        );

        expect(listing.title, '');
      });
    });

    group('the condition and the flaws', () {
      test('are suggested from the wear history', () {
        final listing = fromGarment(
          hoodie(
            condition: ConditionAssessment([
              WearObservation(
                type: WearType.pilling,
                severity: WearSeverity.moderate,
                observedAt: DateTime.utc(2026, 5, 1),
              ),
            ]),
          ),
        );

        expect(listing.condition, DepopCondition.usedGood);
        expect(listing.flaws, ['moderate pilling']);
      });

      test('are Used - Excellent and none when worn often with no wear', () {
        final listing = fromGarment(hoodie(timesWorn: 10));

        expect(listing.condition, DepopCondition.usedExcellent);
        expect(listing.flaws, isEmpty);
      });

      test('are Like new for something never worn', () {
        expect(
          fromGarment(hoodie(timesWorn: 0)).condition,
          DepopCondition.likeNew,
        );
      });

      test('add the flaws the photographs showed', () {
        final listing = fromGarment(
          hoodie(),
          facts: facts(visibleFlaws: const ['small mark on the left cuff']),
        );

        expect(listing.flaws, ['small mark on the left cuff']);
      });

      test('list a flaw once when the wardrobe and the photographs agree', () {
        final listing = fromGarment(
          hoodie(
            condition: ConditionAssessment([
              WearObservation(
                type: WearType.pilling,
                severity: WearSeverity.slight,
                observedAt: DateTime.utc(2026, 5, 1),
              ),
            ]),
          ),
          facts: facts(
            visibleFlaws: const [
              'Slight Pilling',
              'small mark on the left cuff',
              '  small mark on the left cuff ',
            ],
          ),
        );

        expect(listing.flaws, [
          'slight pilling',
          'small mark on the left cuff',
        ]);
      });

      test('put the wardrobe\'s flaws before the photographs\'', () {
        final listing = fromGarment(
          hoodie(
            condition: ConditionAssessment([
              WearObservation(
                type: WearType.fading,
                severity: WearSeverity.moderate,
                observedAt: DateTime.utc(2026, 5, 1),
              ),
            ]),
          ),
          facts: facts(visibleFlaws: const ['loose thread at the hem']),
        );

        expect(listing.flaws, ['moderate fading', 'loose thread at the hem']);
      });
    });

    group('the department', () {
      test('is Men for a men\'s cut', () {
        expect(
          fromGarment(hoodie().copyWith(styleCut: StyleCut.mens)).department,
          DepopDepartment.men,
        );
      });

      test('is Women for a women\'s cut', () {
        expect(
          fromGarment(hoodie().copyWith(styleCut: StyleCut.womens)).department,
          DepopDepartment.women,
        );
      });

      test('is left for the person when the cut does not say', () {
        for (final cut in [StyleCut.unisex, StyleCut.kids]) {
          expect(
            fromGarment(hoodie().copyWith(styleCut: cut)).department,
            isNull,
            reason: cut.name,
          );
        }
        expect(fromGarment(hoodie()).department, isNull);
      });
    });

    group('the photographs', () {
      test('are the garment\'s own, mapped to the shots they already are', () {
        final item = hoodie().copyWith(
          photos: PhotoSet([
            itemPhoto('front', PhotoRole.front, primary: true),
            itemPhoto('back', PhotoRole.back),
            itemPhoto('tag', PhotoRole.brandTag),
            itemPhoto('care', PhotoRole.careTag),
            itemPhoto('hole', PhotoRole.condition),
            itemPhoto('logo', PhotoRole.logo),
            itemPhoto('detail', PhotoRole.detail),
            itemPhoto('worn', PhotoRole.worn),
          ]),
        );

        expect(
          [for (final p in fromGarment(item).photos) (p.uri, p.shot)],
          [
            ('front', ListingShot.cover),
            ('back', ListingShot.back),
            ('tag', ListingShot.brandTag),
            ('care', ListingShot.careLabel),
            ('hole', ListingShot.flaw),
            ('logo', ListingShot.other),
            ('detail', ListingShot.other),
            ('worn', ListingShot.other),
          ],
        );
      });

      test('start with the photograph the wardrobe shows for it', () {
        final item = hoodie().copyWith(
          photos: PhotoSet([
            itemPhoto('back', PhotoRole.back),
            itemPhoto('front', PhotoRole.front, cutout: 'front-cutout'),
            itemPhoto('tag', PhotoRole.brandTag),
          ]),
        );

        expect(
          [for (final p in fromGarment(item).photos) p.uri],
          ['front', 'back', 'tag'],
        );
      });

      test('put a photograph the person marked as primary first', () {
        final item = hoodie().copyWith(
          photos: PhotoSet([
            itemPhoto('front', PhotoRole.front),
            itemPhoto('worn', PhotoRole.worn, primary: true),
          ]),
        );
        final photos = fromGarment(item).photos;

        expect(photos.first.uri, 'worn');
        expect(photos.first.shot, ListingShot.other);
        expect(photos.last.uri, 'front');
      });

      test('are the originals, never the cutouts', () {
        // A buyer should see the garment, not a silhouette on transparency.
        final item = hoodie().copyWith(
          photos: PhotoSet([
            itemPhoto('front', PhotoRole.front, cutout: 'front-cutout'),
          ]),
        );
        final uris = [for (final p in fromGarment(item).photos) p.uri];

        expect(uris, ['front']);
        expect(uris, isNot(contains('front-cutout')));
      });

      test('list a photograph once even though it is first and in the set', () {
        final item = hoodie().copyWith(
          photos: PhotoSet([
            itemPhoto('front', PhotoRole.front, primary: true),
          ]),
        );

        expect(fromGarment(item).photos, hasLength(1));
      });

      test('stop at the most Depop takes', () {
        final item = hoodie().copyWith(
          photos: PhotoSet([
            for (var i = 0; i < 12; i++) itemPhoto('p$i', PhotoRole.detail),
          ]),
        );
        final photos = fromGarment(item).photos;

        expect(photos, hasLength(depopPhotoLimit));
        expect(photos.first.uri, 'p0');
      });

      test('are none when the garment has none', () {
        expect(fromGarment(hoodie()).photos, isEmpty);
      });

      test('mean the checklist only asks for what is still missing', () {
        final item = hoodie().copyWith(
          photos: PhotoSet([
            itemPhoto('front', PhotoRole.front),
            itemPhoto('back', PhotoRole.back),
          ]),
        );

        expect(
          fromGarment(item).missingShots,
          {ListingShot.brandTag, ListingShot.sizeLabel},
        );
      });
    });

    group('when the description could not be fetched', () {
      test('still makes a usable draft from the wardrobe alone', () {
        final listing = fromGarment(hoodie());

        expect(listing.facts, isNull);
        expect(listing.title, isNotEmpty);
        expect(listing.styleWords, isEmpty);
        expect(listing.era, isNull);
        expect(listing.canLookUpPrices, isTrue);
      });

      test('can still search for prices from the words it built', () {
        final listing = fromGarment(hoodie());

        expect(listing.searchQueries!.depop, 'Nike hoodie charcoal');
        expect(listing.searchQueries!.retail, 'Nike hoodie grey');
      });
    });

    test('does not copy the person\'s private notes about the garment', () {
      // "Bought in 2019, worn a handful of times" is for them, not a buyer.
      final item = hoodie().copyWith(notes: 'Bought in 2019, my favourite');

      expect(fromGarment(item).notes, isNull);
    });

    test('is a draft with no price and no department guessed', () {
      final listing = fromGarment(hoodie());

      expect(listing.priceCents, isNull);
      expect(listing.priceSearch, isNull);
      expect(listing.measurements.isEmpty, isTrue);
    });

    test('survives being saved and read back', () {
      final item = hoodie().copyWith(
        styleCut: StyleCut.mens,
        photos: PhotoSet([itemPhoto('front', PhotoRole.front)]),
      );
      final listing = fromGarment(
        item,
        facts: facts(visibleFlaws: const ['small mark']),
      );

      expect(Listing.fromJson(viaText(listing.toJson())), listing);
    });
  });
}
