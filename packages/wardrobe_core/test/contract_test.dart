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
  });
}
