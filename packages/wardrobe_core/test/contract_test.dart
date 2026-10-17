/// The Dart half of the cross-language contract.
///
/// The Python server validates the same fixtures in `contracts/examples/`
/// against JSON Schema. This decodes them into domain types. Between the two,
/// a field renamed on one side and not the other fails a test rather than
/// surfacing as a null on a user's phone.
///
/// These tests read from `contracts/` at the repository root, so they also fail
/// if the fixtures are moved or deleted — which is the point. A contract nobody
/// reads is not a contract.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'support/fixtures.dart';

/// Locates `contracts/` by walking up from the current directory.
///
/// Checks for the schema file rather than merely for a directory of the right
/// name — an empty `contracts/` left behind by a stray `mkdir` would otherwise
/// be found first and produce a confusing "file not found" several frames away
/// from the actual cause.
Directory findContracts() {
  const marker = 'scan_results.schema.json';
  var directory = Directory.current.absolute;

  for (var depth = 0; depth < 6; depth++) {
    final candidate = Directory('${directory.path}/contracts');
    if (File('${candidate.path}/$marker').existsSync()) return candidate;

    final parent = directory.parent;
    if (parent.path == directory.path) break; // Reached the filesystem root.
    directory = parent;
  }

  throw StateError(
    'could not find a contracts/ directory containing $marker, '
    'searching upward from ${Directory.current.absolute.path}',
  );
}

Map<String, Object?> loadFixture(String name) {
  final file = File('${findContracts().path}/examples/$name');
  if (!file.existsSync()) {
    throw StateError('missing contract fixture: ${file.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

void main() {
  group('garment scan fixture', () {
    late Map<String, Object?> result;

    setUpAll(() {
      result =
          loadFixture('garment_scan.json')['result']! as Map<String, Object?>;
    });

    test('decodes the item type with its confidence and provenance', () {
      final type = Confident.fromJson(
        result['type']! as Map<String, Object?>,
        (raw) => ItemType.values.byName(raw! as String),
      );

      expect(type.value, ItemType.hoodie);
      expect(type.confidence, closeTo(0.94, 1e-9));
      expect(type.source, Provenance.aiInference);
    });

    test('decodes the colour palette, ordered by coverage', () {
      final colors = Confident.fromJson(
        result['colors']! as Map<String, Object?>,
        (raw) => ColorPalette.fromJson(raw! as List<Object?>),
      );

      expect(colors.value.colors, hasLength(2));
      expect(colors.value.dominant?.name, 'Grey');
      // The server sends CIELAB, and the core must read it as such rather than
      // re-deriving it from a hex string it was never sent.
      expect(colors.value.dominant!.lightness, closeTo(63.7, 1e-9));
    });

    test('decodes the fibre composition from a bare map', () {
      final composition = Confident.fromJson(
        result['composition']! as Map<String, Object?>,
        (raw) => FabricComposition.fromJson(raw! as Map<String, Object?>),
      );

      expect(composition.value.percentOf(Fiber.cotton), 80);
      expect(composition.value.percentOf(Fiber.polyester), 20);
      expect(composition.value.isPlausible, isTrue);
    });

    test('decodes every optional attribute the server may send', () {
      expect(
        Pattern.values.byName(
          (result['pattern']! as Map<String, Object?>)['value']! as String,
        ),
        Pattern.graphic,
      );
      expect(
        SleeveLength.values.byName(
          (result['sleeveLength']! as Map<String, Object?>)['value']! as String,
        ),
        SleeveLength.longSleeve,
      );
      expect(
        [
          for (final raw in result['seasons']! as List<Object?>)
            Season.values.byName(raw! as String),
        ],
        [Season.autumn, Season.winter],
      );
      expect(result['distinguishingText'], 'Just Do It');
    });
  });

  group('care tag fixture', () {
    late Map<String, Object?> result;
    late Map<String, Object?> instructions;

    setUpAll(() {
      result =
          loadFixture('care_tag_scan.json')['result']! as Map<String, Object?>;
      instructions = result['instructions']! as Map<String, Object?>;
    });

    test('every key the server sends maps to a known care value', () {
      expect(WashMethod.values.byName(instructions['method']! as String),
          WashMethod.machine);
      expect(instructions['maxTempC'], 30);
      expect(Agitation.values.byName(instructions['agitation']! as String),
          Agitation.normal);
      expect(BleachAllowance.values.byName(instructions['bleach']! as String),
          BleachAllowance.none);
      expect(instructions['tumbleDryAllowed'], isTrue);
      expect(
          TumbleDryHeat.values.byName(instructions['tumbleDryHeat']! as String),
          TumbleDryHeat.low);
      expect(
        [
          for (final raw in instructions['warnings']! as List<Object?>)
            CareWarning.values.byName(raw! as String),
        ],
        containsAll([CareWarning.washInsideOut, CareWarning.doNotUseSoftener]),
      );
    });

    test('an unstated field is absent, not null', () {
      // The semantic the whole care model rests on. This fixture represents a
      // label whose iron symbol was smudged: the key must simply not be there,
      // because the core reads absence as "fill this from the rule table" and
      // would read an explicit null as a stated value.
      expect(instructions.containsKey('ironTemperature'), isFalse);
      expect(result['unreadableSymbolCount'], 1);
    });

    test('the parser carries absence through to statedFields', () {
      // The assertion above checks the server's bytes; this one checks that the
      // core actually reads them that way. Between them, a regression on either
      // side of the wire fails a test.
      final constraint = CareConstraint.fromJson(instructions);

      expect(constraint.ironTemperature, isNull);
      expect(constraint.statedFields, isNot(contains('iron.temperature')));
      expect(constraint.statedFields, contains('wash.maxTempC'));
      expect(constraint.method, WashMethod.machine);
      expect(constraint.warnings, contains(CareWarning.washInsideOut));
    });

    test('a null on the wire is read as unstated, not as a stated value', () {
      // A server that forgot `exclude_none` would send `"maxTempC": null`.
      // Reading that as a stated limit would be inventing an instruction the
      // label never gave, so it must be indistinguishable from absence.
      final fromNull = CareConstraint.fromJson({'maxTempC': null});
      expect(fromNull.maxTempC, isNull);
      expect(fromNull.statesNothing, isTrue);
    });

    test('a constraint survives a round trip through JSON', () {
      final original = CareConstraint.fromJson(instructions);
      final round = CareConstraint.fromJson(original.toJson());

      expect(round.statedFields, original.statedFields);
      expect(round.warnings, original.warnings);
      expect(round.maxTempC, original.maxTempC);
      expect(round.agitation, original.agitation);
    });

    test('a bar-less tub arrives as normal agitation', () {
      // If the server omitted this, every ordinary garment would inherit the
      // conservative default and be recommended a gentle cycle it does not need.
      expect(instructions['agitation'], 'normal');
    });

    test('the composition is marked as read from a tag, not guessed', () {
      final composition = Confident.fromJson(
        result['composition']! as Map<String, Object?>,
        (raw) => FabricComposition.fromJson(raw! as Map<String, Object?>),
      );

      expect(composition.source, Provenance.tagScan);
      // Provenance is what lets a label outrank a photograph when they disagree.
      expect(
        composition.source.resolutionRank,
        greaterThan(Provenance.aiInference.resolutionRank),
      );
    });
  });

  group('pile scan fixture', () {
    late Map<String, Object?> result;

    setUpAll(() {
      result = loadFixture('pile_scan.json')['result']! as Map<String, Object?>;
    });

    test('decodes every detected item', () {
      final items = result['items']! as List<Object?>;
      expect(items, hasLength(3));

      final types = [
        for (final raw in items)
          ItemType.values.byName(
            (((raw! as Map<String, Object?>)['scan']!
                    as Map<String, Object?>)['type']!
                as Map<String, Object?>)['value']! as String,
          ),
      ];
      expect(types, [ItemType.tShirt, ItemType.jeans, ItemType.socks]);
    });

    test('bounding boxes are normalised and within the frame', () {
      for (final raw in result['items']! as List<Object?>) {
        final box = (raw! as Map<String, Object?>)['boundingBox']!
            as Map<String, Object?>;
        final left = (box['left']! as num).toDouble();
        final top = (box['top']! as num).toDouble();
        final width = (box['width']! as num).toDouble();
        final height = (box['height']! as num).toDouble();

        expect(left, inInclusiveRange(0.0, 1.0));
        expect(top, inInclusiveRange(0.0, 1.0));
        expect(left + width, lessThanOrEqualTo(1.0));
        expect(top + height, lessThanOrEqualTo(1.0));
      }
    });

    test('reports garments it could not identify', () {
      // Admitting two items are buried is more useful than guessing at shapes.
      expect(result['partiallyObscuredCount'], 2);
    });
  });

  group('vocabulary agreement', () {
    test('every enum value the schema lists exists in Dart', () {
      // Catches the schema gaining a value the core cannot decode, which would
      // otherwise fail only when a model happened to return that value.
      final schema = jsonDecode(
        File('${findContracts().path}/scan_results.schema.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final defs = schema[r'$defs']! as Map<String, Object?>;

      void checkEnum(String defName, Set<String> dartNames) {
        final values =
            (defs[defName]! as Map<String, Object?>)['enum']! as List<Object?>;
        for (final value in values) {
          expect(
            dartNames,
            contains(value! as String),
            reason: '$defName value "$value" has no Dart counterpart',
          );
        }
      }

      checkEnum('itemType', {for (final v in ItemType.values) v.name});
      checkEnum('fiber', {for (final v in Fiber.values) v.name});
      checkEnum('provenance', {for (final v in Provenance.values) v.name});
    });

    test('every care enum in the schema exists in Dart', () {
      final schema = jsonDecode(
        File('${findContracts().path}/care_constraint.schema.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final properties = schema['properties']! as Map<String, Object?>;

      void checkProperty(String property, Set<String> dartNames) {
        final definition = properties[property]! as Map<String, Object?>;
        // Scalar properties carry `enum` directly; array properties such as
        // `warnings` carry it on their `items`.
        final holder = definition.containsKey('enum')
            ? definition
            : definition['items']! as Map<String, Object?>;
        final values = holder['enum']! as List<Object?>;

        for (final value in values) {
          expect(
            dartNames,
            contains(value! as String),
            reason: '$property value "$value" has no Dart counterpart',
          );
        }
      }

      checkProperty('method', {for (final v in WashMethod.values) v.name});
      checkProperty('agitation', {for (final v in Agitation.values) v.name});
      checkProperty('bleach', {for (final v in BleachAllowance.values) v.name});
      checkProperty(
          'tumbleDryHeat', {for (final v in TumbleDryHeat.values) v.name});
      checkProperty(
          'naturalDry', {for (final v in NaturalDryMethod.values) v.name});
      checkProperty(
        'ironTemperature',
        {for (final v in IronTemperature.values) v.name},
      );
      checkProperty(
          'solvent', {for (final v in CleaningSolvent.values) v.name});
      checkProperty('warnings', {for (final v in CareWarning.values) v.name});
    });

    test('and the schema knows every care warning Dart has', () {
      // The check above only walks the schema, so a member added to Dart and
      // forgotten in the contract passes it. That is the likelier direction:
      // the enum is where a new warning gets written first, and a warning the
      // contract has never heard of is one the server can never send.
      final schema = jsonDecode(
        File('${findContracts().path}/care_constraint.schema.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final properties = schema['properties']! as Map<String, Object?>;
      final items = (properties['warnings']! as Map<String, Object?>)['items']!
          as Map<String, Object?>;
      final listed = {
        for (final value in items['enum']! as List<Object?>) value! as String,
      };

      expect(listed, {for (final v in CareWarning.values) v.name});
    });
  });

  group('listing fixtures', () {
    Map<String, Object?> resultOf(String name) =>
        loadFixture('listing/$name')['result']! as Map<String, Object?>;

    test('every file decodes, a description told from prices by its shape', () {
      final directory = Directory('${findContracts().path}/examples/listing');
      final files = [
        for (final entity in directory.listSync())
          if (entity is File && entity.path.endsWith('.json')) entity,
      ];

      // Guards the loop below from passing because it found nothing to read.
      expect(
        [for (final file in files) file.uri.pathSegments.last],
        containsAll([
          'describe.json',
          'describe_minimal.json',
          'prices_not_configured.json',
          'prices_ok.json',
        ]),
      );

      for (final file in files) {
        final body =
            jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        final result = body['result']! as Map<String, Object?>;

        // A prices response has a status and a description has a title.
        if (result.containsKey('status')) {
          expect(
            priceSearchFromJson(result).queries.isSearchable,
            isTrue,
            reason: file.path,
          );
        } else {
          expect(
            listingFactsFromJson(result).searchQueries.isSearchable,
            isTrue,
            reason: file.path,
          );
        }
        expect(body['diagnostics'], isA<Map<String, Object?>>(),
            reason: file.path);
      }
    });

    test('a full description decodes to the values the fixture holds', () {
      final facts = listingFactsFromJson(resultOf('describe.json'));

      expect(facts.title, 'Nike vintage crewneck sweatshirt grey');
      expect(facts.itemType, ItemType.sweatshirt);
      expect(facts.brand!.value, 'Nike');
      expect(facts.brand!.confidence, closeTo(0.93, 1e-9));
      expect(facts.brand!.source, Provenance.aiInference);
      expect(facts.colors, ['Grey']);
      expect(facts.material, '80% cotton, 20% polyester');
      expect(facts.sizeOnTag!.value, 'M');
      expect(facts.sizeOnTag!.confidence, closeTo(0.9, 1e-9));
      expect(facts.styleWords, [
        'vintage',
        'crewneck',
        'embroidered logo',
        '90s',
      ]);
      expect(facts.era, '90s');
      expect(facts.visibleFlaws, ['small mark on the left cuff']);
      expect(
        facts.searchQueries,
        const SearchQueries(
          depop: 'Nike vintage crewneck sweatshirt grey',
          retail: 'Nike Club Fleece crew sweatshirt grey',
        ),
      );
    });

    test('a minimal description decodes with everything optional absent', () {
      final facts = listingFactsFromJson(resultOf('describe_minimal.json'));

      expect(facts.title, 'Grey crewneck sweatshirt');
      expect(facts.itemType, ItemType.sweatshirt);
      expect(facts.brand, isNull);
      expect(facts.material, isNull);
      expect(facts.sizeOnTag, isNull);
      expect(facts.era, isNull);
      expect(facts.colors, isEmpty);
      expect(facts.styleWords, isEmpty);
      expect(facts.visibleFlaws, isEmpty);
      expect(facts.searchQueries.depop, 'grey crewneck sweatshirt');
    });

    test('a description starts a listing that has all it was told', () {
      final facts = listingFactsFromJson(resultOf('describe.json'));
      final listing = Listing.fromFacts(
        id: const ListingId('from-fixture'),
        now: DateTime.utc(2026, 10, 17),
        facts: facts,
      );

      expect(listing.brand, 'Nike');
      expect(listing.sizeLabel, 'M');
      expect(listing.colours, [DepopColour.grey]);
      expect(listing.flaws, ['small mark on the left cuff']);
      expect(listing.canLookUpPrices, isTrue);
    });

    test('a search decodes to the values the fixture holds, in cents', () {
      final search = priceSearchFromJson(resultOf('prices_ok.json'));

      expect(search.status, PriceSearchStatus.ok);
      expect(search.searchedAt, DateTime.utc(2026, 10, 17, 14, 5));
      expect(search.provider, 'tavily');
      expect(search.excluded.notUsd, 2);
      expect(search.excluded.unverifiedPrice, 1);
      expect(search.excluded.notComparable, 4);

      expect([
        for (final c in search.comparables) c.priceCents
      ], [
        3200,
        2800,
        3500,
      ]);
      expect([for (final c in search.comparables) c.sold], [true, false, null]);
      expect([
        for (final c in search.comparables) c.condition
      ], [
        'Used - Excellent',
        null,
        null,
      ]);
      expect([
        for (final c in search.comparables) c.match
      ], [
        ComparableMatch.same,
        ComparableMatch.same,
        ComparableMatch.similar,
      ]);
      expect(
        search.comparables.first.url,
        Uri.parse(
          'https://www.depop.com/products/example-vintage-nike-grey-crewneck/',
        ),
      );
      expect(search.comparables.first.why, 'Same 90s Nike crewneck, also grey');

      expect(search.retail.single.priceCents, 6000);
      expect(search.retail.single.seller, 'nike.com');
      expect(search.retail.single.match, ComparableMatch.similar);
    });

    test('a search that was not configured decodes with nothing in it', () {
      final search =
          priceSearchFromJson(resultOf('prices_not_configured.json'));

      expect(search.status, PriceSearchStatus.notConfigured);
      expect(search.comparables, isEmpty);
      expect(search.retail, isEmpty);
      expect(search.searchedAt, isNull);
      expect(search.provider, isNull);
      expect(search.excluded.total, 0);
      // The phrases come back so the app can offer the same searches as links.
      expect(search.queries.isSearchable, isTrue);
    });

    test('a search in the fixture prices at \$30, leaving \$28.56', () {
      // The contract's own example, run through the pricing rule: two of the
      // same product (a sale at \$32 and an asking price of \$28), the similar
      // \$35 listing kept out, and a similar shop item that does not cap.
      final search = priceSearchFromJson(resultOf('prices_ok.json'));
      final suggestion = suggestPrice(
        comparables: search.comparables,
        retail: search.retail,
        condition: DepopCondition.usedExcellent,
      );

      expect(suggestion.listPriceCents, 3000);
      expect(suggestion.netCents, 2856);
    });

    test('a search stored on the phone reads back as it was received', () {
      final search = priceSearchFromJson(resultOf('prices_ok.json'));
      final stored = PriceSearch.fromJson(
        jsonDecode(jsonEncode(search.toJson())) as Map<String, Object?>,
      );

      expect(stored, search);
    });
  });

  group('listing request fixtures', () {
    test('there is a test for every request fixture', () {
      final directory = Directory(
        '${findContracts().path}/examples/listing/requests',
      );
      final names = {
        for (final entity in directory.listSync())
          if (entity is File && entity.path.endsWith('.json'))
            entity.uri.pathSegments.last,
      };

      // A new request fixture without a builder test below would otherwise be
      // a contract nobody checks.
      expect(names, {'describe_context.json', 'price_search.json'});
    });

    test('the price search builder writes exactly the fixture', () {
      final fixture = loadFixture('listing/requests/price_search.json');

      final built = priceSearchRequestJson(
        queries: const SearchQueries(
          depop: 'Nike vintage crewneck sweatshirt grey',
          retail: 'Nike Club Fleece crew sweatshirt grey',
        ),
        itemType: ItemType.sweatshirt,
        title: 'Nike vintage crewneck sweatshirt grey',
        brand: 'Nike',
        colors: const ['Grey'],
      );

      expect(built.keys.toSet(), fixture.keys.toSet());
      expect(
        (built['queries']! as Map<String, Object?>).keys.toSet(),
        (fixture['queries']! as Map<String, Object?>).keys.toSet(),
      );
      expect(built, fixture);
    });

    test('the describe context builder writes exactly the fixture', () {
      final fixture = loadFixture('listing/requests/describe_context.json');

      final built = describeContextJson(
        itemType: ItemType.sweatshirt,
        brand: 'Nike',
        colors: const ['Grey'],
        material: '80% cotton, 20% polyester',
        sizeLabel: 'M',
        notes: 'Bought in 2019, worn a handful of times',
      );

      expect(built.keys.toSet(), fixture.keys.toSet());
      expect(
        (built['known']! as Map<String, Object?>).keys.toSet(),
        (fixture['known']! as Map<String, Object?>).keys.toSet(),
      );
      expect(built, fixture);
    });

    test('the context for a garment has the same keys as the fixture', () {
      final fixture = loadFixture('listing/requests/describe_context.json');
      final item = buildItem(
        type: ItemType.sweatshirt,
        brand: 'Nike',
        sizeLabel: 'M',
        colors: [Colors.grey],
        composition: const {Fiber.cotton: 80, Fiber.polyester: 20},
        usage: const UsageStats.none(),
      ).copyWith(notes: 'Bought in 2019, worn a handful of times');

      final built = describeContextForItem(item);

      expect(built.keys.toSet(), fixture.keys.toSet());
      expect(
        (built['known']! as Map<String, Object?>).keys.toSet(),
        (fixture['known']! as Map<String, Object?>).keys.toSet(),
      );
      // The garment's notes are sent as the person typed them.
      expect(built['notes'], fixture['notes']);
      expect(
        (built['known']! as Map<String, Object?>)['itemType'],
        (fixture['known']! as Map<String, Object?>)['itemType'],
      );
    });
  });

  group('listing schema agreement', () {
    late Map<String, Object?> defs;

    Map<String, Object?> child(Map<String, Object?> parent, String key) =>
        parent[key]! as Map<String, Object?>;

    Map<String, Object?> properties(String definition) =>
        child(child(defs, definition), 'properties');

    setUpAll(() {
      final schema = jsonDecode(
        File('${findContracts().path}/listing.schema.json').readAsStringSync(),
      ) as Map<String, Object?>;
      defs = child(schema, r'$defs');
    });

    Set<String> enumValues(Map<String, Object?> definition) => {
          for (final value in definition['enum']! as List<Object?>)
            value! as String,
        };

    test('the search statuses are the ones Dart has, both ways', () {
      expect(
        enumValues(child(properties('priceSearch'), 'status')),
        {for (final v in PriceSearchStatus.values) v.name},
      );
    });

    test('the match levels are the ones Dart has, both ways', () {
      final dart = {for (final v in ComparableMatch.values) v.name};

      expect(enumValues(child(properties('comparable'), 'match')), dart);
      expect(enumValues(child(properties('retailReference'), 'match')), dart);
    });

    test('the only currency is US dollars', () {
      expect(child(defs, 'currency')['const'], 'USD');
    });

    test('search phrases are the lengths the core says they are', () {
      final depop = child(properties('searchQueries'), 'depop');
      final retail = child(properties('searchQueries'), 'retail');

      for (final phrase in [depop, retail]) {
        expect(phrase['minLength'], SearchQueries.minLength);
        expect(phrase['maxLength'], SearchQueries.maxLength);
      }
    });

    test('the price search request is cut to the schema\'s lengths', () {
      final request = properties('priceSearchRequest');
      final built = priceSearchRequestJson(
        queries: SearchQueries(depop: 'd' * 999, retail: 'r' * 999),
        itemType: ItemType.hoodie,
        title: 't' * 999,
        brand: 'b' * 999,
        colors: ['c' * 999, 'c' * 999, 'c' * 999, 'c' * 999],
      );
      final colours = built['colors']! as List<Object?>;

      expect(
        (built['title']! as String).length,
        child(request, 'title')['maxLength'],
      );
      expect(
        (built['brand']! as String).length,
        child(request, 'brand')['maxLength'],
      );
      expect(colours, hasLength(child(request, 'colors')['maxItems']! as int));
      expect(
        (colours.first! as String).length,
        child(child(request, 'colors'), 'items')['maxLength'],
      );
    });

    test('the describe context is cut to the schema\'s lengths', () {
      final context = child(defs, 'describeContext');
      final known = child(child(context, 'properties'), 'known');
      final knownProperties = child(known, 'properties');
      final built = describeContextJson(
        itemType: ItemType.hoodie,
        brand: 'b' * 999,
        colors: ['c' * 999, 'c' * 999, 'c' * 999, 'c' * 999],
        material: 'm' * 999,
        sizeLabel: 's' * 999,
        notes: 'n' * 999,
      );
      final builtKnown = built['known']! as Map<String, Object?>;
      final colours = builtKnown['colors']! as List<Object?>;

      expect(
        (builtKnown['brand']! as String).length,
        child(knownProperties, 'brand')['maxLength'],
      );
      expect(
        (builtKnown['material']! as String).length,
        child(knownProperties, 'material')['maxLength'],
      );
      expect(
        (builtKnown['sizeLabel']! as String).length,
        child(knownProperties, 'sizeLabel')['maxLength'],
      );
      expect(
        colours,
        hasLength(child(knownProperties, 'colors')['maxItems']! as int),
      );
      expect(
        (colours.first! as String).length,
        child(child(knownProperties, 'colors'), 'items')['maxLength'],
      );
      expect(
        (built['notes']! as String).length,
        child(child(context, 'properties'), 'notes')['maxLength'],
      );
    });

    test('a listing\'s facts are written in the schema\'s shape', () {
      // The keys of ListingFacts.toJson are the listingFacts properties, so
      // what is stored on the phone is what the server sends.
      final stored = ListingFacts(
        title: 'Nike vintage crewneck sweatshirt grey',
        itemType: ItemType.sweatshirt,
        searchQueries: const SearchQueries(depop: 'a b c', retail: 'd e f'),
        brand: Confident(
          'Nike',
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        material: 'cotton',
        sizeOnTag: Confident(
          'M',
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        era: '90s',
      ).toJson();

      expect(stored.keys.toSet(), properties('listingFacts').keys.toSet());
    });
  });
}
