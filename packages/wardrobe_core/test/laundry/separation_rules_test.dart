import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  final whiteShirt = buildItem(
    id: 'white-shirt',
    type: ItemType.dressShirt,
    colors: [Colors.white],
  );
  final blackJeans = buildItem(
    id: 'black-jeans',
    type: ItemType.jeans,
    colors: [Colors.black],
    careInstructions: heavyCare,
  );
  final greyTee = buildItem(id: 'grey-tee', colors: [Colors.grey]);
  final navyTee = buildItem(id: 'navy-tee', colors: [Colors.navy]);
  final silkBlouse = buildItem(
    id: 'silk-blouse',
    type: ItemType.blouse,
    composition: {Fiber.silk: 100},
    colors: [Colors.pastelPink],
    careInstructions: delicateCare,
  );
  final towel = buildItem(
    id: 'towel',
    type: ItemType.bathTowel,
    colors: [Colors.white],
    careInstructions: heavyCare,
  );
  final blackFleece = buildItem(
    id: 'black-fleece',
    type: ItemType.hoodie,
    composition: {Fiber.polyester: 100},
    colors: [Colors.black],
  );
  final newRedTee = buildItem(
    id: 'new-red-tee',
    colors: [Colors.red],
    usage: const UsageStats(timesWashed: 0, timesWorn: 1),
  );
  final oldRedTee = buildItem(
    id: 'old-red-tee',
    colors: [Colors.red],
    usage: const UsageStats(timesWashed: 20, timesWorn: 40),
  );

  final sample = [
    whiteShirt,
    blackJeans,
    greyTee,
    navyTee,
    silkBlouse,
    towel,
    blackFleece,
    newRedTee,
    oldRedTee,
  ];

  group('colour separation', () {
    test('whites must not be washed with darks', () {
      expect(
        SeparationRules.conflictBetween(whiteShirt, navyTee),
        SeparationReason.colorTransfer,
      );
    });

    test('whites may be washed with other whites', () {
      final otherWhite = buildItem(id: 'white-2', colors: [Colors.offWhite]);
      expect(SeparationRules.conflictBetween(whiteShirt, otherWhite), isNull);
    });

    test('darks may be washed with other darks', () {
      expect(SeparationRules.conflictBetween(navyTee, blackFleece), isNull);
    });
  });

  group('dye bleed', () {
    test('a new saturated item needs its own load', () {
      expect(SeparationRules.requiresOwnLoad(newRedTee), isTrue);
      expect(
        SeparationRules.isolationReason(newRedTee),
        SeparationReason.dyeBleed,
      );
    });

    test('the same item after twenty washes does not', () {
      expect(SeparationRules.requiresOwnLoad(oldRedTee), isFalse);
    });

    test('a bleeding item conflicts with anything', () {
      expect(
        SeparationRules.conflictBetween(newRedTee, greyTee),
        SeparationReason.dyeBleed,
      );
    });
  });

  group('lint transfer', () {
    // Both dark, so a colour conflict cannot mask the lint conflict — the
    // colour check runs first and would otherwise be what the test observed.
    final darkTowel = buildItem(
      id: 'dark-towel',
      type: ItemType.bathTowel,
      colors: [Colors.charcoal],
      careInstructions: heavyCare,
    );

    test('towels must not be washed with lint-attracting fabrics', () {
      expect(
        SeparationRules.conflictBetween(darkTowel, blackFleece),
        SeparationReason.lintTransfer,
      );
    });

    test('an ordinary cotton tee is not treated as a lint hazard', () {
      // Cotton jersey sheds far too little to justify splitting a load, so
      // only construction-driven shedders (towelling, socks) count.
      expect(SeparationRules.conflictBetween(greyTee, blackFleece), isNull);
    });
  });

  group('abrasion', () {
    test('delicates must not share a drum with heavy items', () {
      expect(
        SeparationRules.conflictBetween(silkBlouse, blackJeans),
        SeparationReason.abrasion,
      );
    });
  });

  group('wash method', () {
    test('hand wash and machine wash cannot be combined', () {
      final handWashOnly = buildItem(
        id: 'hand-only',
        careInstructions: handWashCare,
      );
      expect(
        SeparationRules.conflictBetween(handWashOnly, greyTee),
        SeparationReason.washMethod,
      );
    });
  });

  group('explicit label instruction', () {
    test('wash-separately beats every other consideration', () {
      final mustBeAlone = buildItem(
        id: 'alone',
        colors: [Colors.grey],
        careInstructions: cottonCare.withWarnings([CareWarning.washSeparately]),
      );
      expect(SeparationRules.requiresOwnLoad(mustBeAlone), isTrue);
      expect(
        SeparationRules.conflictBetween(mustBeAlone, greyTee),
        SeparationReason.labelRequiresSeparate,
      );
    });
  });

  group('structural properties', () {
    test('conflict detection is symmetric across the whole sample', () {
      // Asymmetry here would mean a load's contents depended on the order items
      // came out of the camera, which would be both wrong and impossible to
      // reproduce in a bug report.
      for (final a in sample) {
        for (final b in sample) {
          expect(
            SeparationRules.conflictBetween(a, b),
            SeparationRules.conflictBetween(b, a),
            reason: '${a.id.value} vs ${b.id.value}',
          );
        }
      }
    });

    test('an item never conflicts with itself unless it needs isolation', () {
      for (final item in sample) {
        final conflict = SeparationRules.conflictBetween(item, item);
        if (SeparationRules.requiresOwnLoad(item)) {
          expect(conflict, isNotNull, reason: item.id.value);
        } else {
          expect(conflict, isNull, reason: item.id.value);
        }
      }
    });

    test('group conflict agrees with pairwise conflict', () {
      expect(
        SeparationRules.conflictWithGroup(whiteShirt, [greyTee, navyTee]),
        SeparationReason.colorTransfer,
      );
      expect(
        SeparationRules.conflictWithGroup(greyTee, [navyTee, blackFleece]),
        isNull,
      );
    });
  });

  group('temperature banding', () {
    test('groups nearby temperatures together', () {
      expect(TemperatureBand.forCelsius(20), TemperatureBand.cold);
      expect(TemperatureBand.forCelsius(30), TemperatureBand.cold);
      expect(TemperatureBand.forCelsius(40), TemperatureBand.warm);
      expect(TemperatureBand.forCelsius(60), TemperatureBand.hot);
      expect(TemperatureBand.forCelsius(90), TemperatureBand.veryHot);
    });

    test('an unstated limit is the least constrained band', () {
      expect(TemperatureBand.forCelsius(null), TemperatureBand.veryHot);
    });
  });
}
