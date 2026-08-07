import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);

  WardrobeItem item({
    required String id,
    ItemType type = ItemType.tShirt,
    Map<Fiber, int> composition = const {Fiber.cotton: 100},
    String hex = '#1A1A1E',
    UsageStats usage = const UsageStats.none(),
    PurchaseInfo? purchase,
    CareProfile? care,
  }) {
    final built = WardrobeItem(
      id: ItemId(id),
      name: id,
      type: Confident(type, confidence: 0.95, source: Provenance.aiInference),
      composition: Confident(
        FabricComposition(composition),
        confidence: 0.95,
        source: Provenance.tagScan,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex(hex)]),
        confidence: 0.95,
        source: Provenance.aiInference,
      ),
      usage: usage,
      purchase: purchase,
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return built.copyWith(
      care: care ?? const CareResolver().forItem(built).profile,
    );
  }

  group('an empty wardrobe', () {
    final summary = WardrobeSummary(const [], asOf: now);

    test('reports nothing rather than dividing by zero', () {
      expect(summary.isEmpty, isTrue);
      expect(summary.itemCount, 0);
      expect(summary.byCategory, isEmpty);
      expect(summary.byFiber, isEmpty);
      expect(summary.totalSpend, isEmpty);
    });

    test('is fully ready, because nothing is unready', () {
      // Vacuously true, and the alternative — 0% — would tell a new user their
      // empty wardrobe is in bad shape.
      expect(summary.readiness, 1);
    });
  });

  group('usage', () {
    final summary = WardrobeSummary([
      item(id: 'worn-often', usage: const UsageStats(timesWorn: 20)),
      item(id: 'worn-once', usage: const UsageStats(timesWorn: 1)),
      item(id: 'never'),
    ], asOf: now);

    test('totals every wear', () {
      expect(summary.totalWears, 21);
    });

    test('ranks by wears, most first', () {
      expect(
        [for (final r in summary.mostWorn) r.item.id.value],
        ['worn-often', 'worn-once'],
      );
    });

    test('never-worn is separate from rarely-worn', () {
      // They prompt different actions: one is a mistake, the other is a
      // garment doing its job infrequently.
      expect([for (final i in summary.neverWorn) i.id.value], ['never']);
      expect(
        [for (final r in summary.mostWorn) r.item.id.value],
        isNot(contains('never')),
      );
    });

    test('idle counts days since the last wear, not since purchase', () {
      final summary = WardrobeSummary([
        item(
          id: 'idle',
          usage: UsageStats(
            timesWorn: 3,
            lastWornAt: now.subtract(const Duration(days: 200)),
          ),
        ),
        item(
          id: 'recent',
          usage: UsageStats(
            timesWorn: 3,
            lastWornAt: now.subtract(const Duration(days: 5)),
          ),
        ),
        item(id: 'never'),
      ], asOf: now);

      final idle = summary.idleFor(90);
      expect([for (final r in idle) r.item.id.value], ['idle']);
      expect(idle.single.value, 200);
    });
  });

  group('value', () {
    final summary = WardrobeSummary([
      // 60.00 over 20 wears = 3.00
      item(
        id: 'good-value',
        usage: const UsageStats(timesWorn: 20),
        purchase: PurchaseInfo(priceMinorUnits: 6000, currencyCode: 'EUR'),
      ),
      // 90.00 over 2 wears = 45.00
      item(
        id: 'poor-value',
        usage: const UsageStats(timesWorn: 2),
        purchase: PurchaseInfo(priceMinorUnits: 9000, currencyCode: 'EUR'),
      ),
      // Priced but unworn: cost per wear is undefined, not infinite.
      item(
        id: 'unworn',
        purchase: PurchaseInfo(priceMinorUnits: 5000, currencyCode: 'EUR'),
      ),
      item(id: 'unpriced', usage: const UsageStats(timesWorn: 5)),
    ], asOf: now);

    test('ranks by cost per wear, cheapest first', () {
      expect(
        [for (final r in summary.bestValue) r.item.id.value],
        ['good-value', 'poor-value'],
      );
      expect(summary.bestValue.first.value, 3.0);
    });

    test('items without a defined cost per wear are left out', () {
      // Showing "unknown" rows in a value ranking buries the comparison it
      // exists to make.
      final ids = [for (final r in summary.bestValue) r.item.id.value];
      expect(ids, isNot(contains('unworn')));
      expect(ids, isNot(contains('unpriced')));
    });

    test('worst value is the same list reversed', () {
      expect(summary.worstValue.first.item.id.value, 'poor-value');
    });

    test('spend is kept per currency, never converted', () {
      final mixed = WardrobeSummary([
        item(
          id: 'eur',
          purchase: PurchaseInfo(priceMinorUnits: 1000, currencyCode: 'EUR'),
        ),
        item(
          id: 'usd',
          purchase: PurchaseInfo(priceMinorUnits: 2000, currencyCode: 'USD'),
        ),
      ], asOf: now);

      // Converting needs a rate the domain has no business inventing, and a
      // wrong total is worse than none because it looks like an answer.
      expect(mixed.totalSpend, {'EUR': 1000, 'USD': 2000});
    });
  });

  group('composition', () {
    test('fibres are counted per item, not per percentage point', () {
      // "How much of my wardrobe involves this fibre" — not "how many grams".
      final summary = WardrobeSummary([
        item(
            id: 'a',
            composition: const {Fiber.cotton: 80, Fiber.polyester: 20}),
        item(id: 'b', composition: const {Fiber.cotton: 100}),
      ], asOf: now);

      final byFiber = {
        for (final t in summary.byFiber) t.key: t.count,
      };
      expect(byFiber[Fiber.cotton], 2);
      expect(byFiber[Fiber.polyester], 1);
    });

    test('a trace fibre is not counted at all', () {
      // The same threshold search uses, so the breakdown and the filter cannot
      // disagree about what a garment is made of.
      final summary = WardrobeSummary([
        item(id: 'a', composition: const {Fiber.cotton: 98, Fiber.elastane: 2}),
      ], asOf: now);

      expect(
        [for (final t in summary.byFiber) t.key],
        isNot(contains(Fiber.elastane)),
      );
    });

    test('shares are of the wardrobe, not of the tally', () {
      // An item counts once per fibre it contains, so the counts can exceed
      // the item count — but a share must still mean "this fraction of my
      // clothes", or the percentages become meaningless.
      final summary = WardrobeSummary([
        item(
            id: 'a',
            composition: const {Fiber.cotton: 80, Fiber.polyester: 20}),
        item(id: 'b', composition: const {Fiber.cotton: 100}),
      ], asOf: now);

      final cotton = summary.byFiber.firstWhere((t) => t.key == Fiber.cotton);
      expect(cotton.share, 1.0);
    });

    test('groups by the laundry piles the wardrobe would sort into', () {
      final summary = WardrobeSummary([
        item(id: 'dark', hex: '#1A1A1E'),
        item(id: 'white', hex: '#F6F6F4'),
        item(id: 'white-2', hex: '#FAFAF8'),
      ], asOf: now);

      final byClass = {for (final t in summary.byColorClass) t.key: t.count};
      expect(byClass[ColorClass.whites], 2);
      expect(byClass[ColorClass.darks], 1);
    });
  });

  group('readiness', () {
    test('is the share of launderable items the app can actually sort', () {
      // The number that predicts how useful a pile scan will be, before
      // someone discovers the answer at the machine.
      final confident = item(
        id: 'known',
        care: const CareProfile(
          instructions: CareInstructions.conservative(),
          source: Provenance.tagScan,
          confidence: 0.95,
        ),
      );
      final guessing = item(id: 'guessed', care: const CareProfile.unknown());

      final summary = WardrobeSummary([confident, guessing], asOf: now);

      expect(summary.readiness, 0.5);
      expect(
        [for (final i in summary.needingCareTagScan) i.id.value],
        ['guessed'],
      );
    });
  });
}
