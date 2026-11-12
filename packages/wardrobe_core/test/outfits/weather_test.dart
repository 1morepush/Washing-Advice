import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

Weather day(
  double low,
  double high, {
  double? rain,
  double? mm,
  double? wind,
  WeatherCondition condition = WeatherCondition.cloudy,
}) =>
    Weather(
      feelsLikeLowC: low,
      feelsLikeHighC: high,
      rainChancePercent: rain,
      rainMm: mm,
      windKph: wind,
      condition: condition,
    );

WardrobeItem item(
  String id,
  ItemType type, {
  Set<String> tags = const {},
  Fiber fiber = Fiber.cotton,
  SleeveLength? sleeve,
  LifecycleState lifecycle = LifecycleState.active,
}) =>
    WardrobeItem(
      id: ItemId(id),
      name: id,
      type: Confident(type, confidence: 0.9, source: Provenance.aiInference),
      composition: Confident(
        FabricComposition({fiber: 100}),
        confidence: 0.9,
        source: Provenance.tagScan,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex('#3C3F44')]),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      care: const CareProfile.unknown(),
      usage: const UsageStats(timesWorn: 5),
      tags: tags,
      sleeveLength: sleeve,
      lifecycle: lifecycle,
      addedAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('warmth bands', () {
    test('edges belong to the warmer band', () {
      expect(WarmthBand.ofFeelsLike(-0.1), WarmthBand.freezing);
      expect(WarmthBand.ofFeelsLike(0), WarmthBand.cold);
      expect(WarmthBand.ofFeelsLike(7.9), WarmthBand.cold);
      expect(WarmthBand.ofFeelsLike(8), WarmthBand.cool);
      expect(WarmthBand.ofFeelsLike(14.9), WarmthBand.cool);
      expect(WarmthBand.ofFeelsLike(15), WarmthBand.mild);
      expect(WarmthBand.ofFeelsLike(20.9), WarmthBand.mild);
      expect(WarmthBand.ofFeelsLike(21), WarmthBand.warm);
      expect(WarmthBand.ofFeelsLike(26.9), WarmthBand.warm);
      expect(WarmthBand.ofFeelsLike(27), WarmthBand.hot);
    });

    test('the day is weighted towards its warm half', () {
      // 0.4 * 4 + 0.6 * 18 = 12.4 -> cool, not the mean of 11 (also cool) —
      // pick numbers where the weighting matters: 2..20 -> 13.2 cool; the
      // plain mean 11 would be too.  Use 6..20: 0.4*6+0.6*20 = 14.4 cool,
      // mean 13.  And 8..20: 15.2 mild, mean 14 cool.
      expect(DressingNeeds.of(day(8, 20)).band, WarmthBand.mild);
    });
  });

  group('needs from the weather', () {
    test('rain is likely by chance, by amount, or by a wet sky with no chance',
        () {
      expect(DressingNeeds.of(day(12, 16, rain: 50)).rainLikely, isTrue);
      expect(DressingNeeds.of(day(12, 16, rain: 49)).rainLikely, isFalse);
      expect(DressingNeeds.of(day(12, 16, rain: 10, mm: 1)).rainLikely, isTrue);
      expect(
        DressingNeeds.of(day(12, 16, condition: WeatherCondition.rain))
            .rainLikely,
        isTrue,
      );
      // A chance was reported and is low: trust it over the sky.
      expect(
        DressingNeeds.of(
          day(12, 16, rain: 10, condition: WeatherCondition.rain),
        ).rainLikely,
        isFalse,
      );
    });

    test('rain is possible between 30 and 49', () {
      expect(DressingNeeds.of(day(12, 16, rain: 30)).rainPossible, isTrue);
      expect(DressingNeeds.of(day(12, 16, rain: 29)).rainPossible, isFalse);
      expect(DressingNeeds.of(day(12, 16, rain: 60)).rainPossible, isFalse);
    });

    test('wind is noticeable from 30 km/h', () {
      expect(DressingNeeds.of(day(15, 20, wind: 29.9)).windy, isFalse);
      expect(DressingNeeds.of(day(15, 20, wind: 30)).windy, isTrue);
    });

    test('a layer: cold, rain, snow, wind when not warm, cold mornings', () {
      expect(DressingNeeds.of(day(2, 6)).outerLayer, isTrue);
      expect(DressingNeeds.of(day(9, 13)).outerLayer, isTrue); // cool
      expect(DressingNeeds.of(day(16, 20)).outerLayer, isFalse); // mild
      expect(DressingNeeds.of(day(16, 20, rain: 80)).outerLayer, isTrue);
      expect(
        DressingNeeds.of(day(16, 20, condition: WeatherCondition.snow))
            .outerLayer,
        isTrue,
      );
      expect(DressingNeeds.of(day(16, 20, wind: 40)).outerLayer, isTrue);
      expect(DressingNeeds.of(day(22, 28, wind: 40)).outerLayer, isFalse);
      // Warm afternoon, cold start.
      final morning = DressingNeeds.of(day(5, 24));
      expect(morning.band, WarmthBand.mild);
      expect(morning.coldMorning, isTrue);
      expect(morning.outerLayer, isTrue);
      expect(DressingNeeds.of(day(22, 30)).outerLayer, isFalse);
    });

    test('wet means likely rain or snow, not merely possible', () {
      expect(DressingNeeds.of(day(12, 16, rain: 40)).wet, isFalse);
      expect(DressingNeeds.of(day(12, 16, rain: 70)).wet, isTrue);
      expect(
        DressingNeeds.of(day(-3, 0, condition: WeatherCondition.snow)).wet,
        isTrue,
      );
    });

    test('headline names the day', () {
      expect(DressingNeeds.of(day(30, 34)).headline, 'Hot');
      expect(DressingNeeds.of(day(5, 8, rain: 80)).headline, 'Cold and rainy');
      expect(
        DressingNeeds.of(day(12, 14, rain: 80, wind: 40)).headline,
        'Cool, rainy and windy',
      );
      expect(
        DressingNeeds.of(day(16, 20, rain: 35)).headline,
        'Mild and a chance of rain',
      );
    });

    test('WMO codes map to conditions, unknown codes are tolerated', () {
      expect(WeatherCondition.fromWmoCode(0), WeatherCondition.clear);
      expect(WeatherCondition.fromWmoCode(3), WeatherCondition.cloudy);
      expect(WeatherCondition.fromWmoCode(63), WeatherCondition.rain);
      expect(WeatherCondition.fromWmoCode(81), WeatherCondition.rain);
      expect(WeatherCondition.fromWmoCode(73), WeatherCondition.snow);
      expect(WeatherCondition.fromWmoCode(95), WeatherCondition.thunderstorm);
      expect(WeatherCondition.fromWmoCode(53), WeatherCondition.drizzle);
      expect(WeatherCondition.fromWmoCode(45), WeatherCondition.fog);
      expect(WeatherCondition.fromWmoCode(1234), WeatherCondition.unknown);
      expect(WeatherCondition.fromWmoCode(null), WeatherCondition.unknown);
    });
  });

  group('the builder with weather', () {
    final clock = FixedClock(DateTime.utc(2026, 8, 5));
    final builder = OutfitBuilder(clock: clock);

    final wardrobe = [
      item('tee', ItemType.tShirt),
      item('long', ItemType.longSleeveShirt),
      item('knit', ItemType.sweater, fiber: Fiber.wool),
      item('jeans', ItemType.jeans),
      item('shorts', ItemType.shorts),
      item('coat', ItemType.coat, fiber: Fiber.wool),
      item('mac', ItemType.jacket, tags: {'waterproof'}),
      item('jacket', ItemType.jacket),
      item('boots', ItemType.boots),
      item('sneakers', ItemType.sneakers),
      item('sandals', ItemType.sandals),
      item('suedes', ItemType.sneakers, tags: {'suede'}),
    ];

    List<Set<String>> ids(List<OutfitSuggestion> s) => [
          for (final o in s) {for (final i in o.items) i.id.value}
        ];

    OutfitRequest req(Weather w) =>
        OutfitRequest(count: 8, needs: DressingNeeds.of(w));

    test('hot: short sleeves and shorts, no coat, no knit, sandals over boots',
        () {
      final out = builder.suggest(wardrobe, req(day(28, 34)));
      final best = out.first.items.map((i) => i.id.value).toSet();
      expect(best, containsAll(['tee', 'shorts']));
      expect(best, isNot(contains('knit')));
      expect(best, isNot(contains('coat')));
      expect(best, isNot(contains('boots')));
      expect(out.first.weatherReasons.first, contains('Hot'));
    });

    test('cold: a layer is included, long sleeves, boots, no shorts', () {
      final out = builder.suggest(wardrobe, req(day(-2, 4)));
      for (final o in out.take(3)) {
        final slots = o.items.map((i) => OutfitSlot.ofType(i.type.value));
        expect(slots, contains(OutfitSlot.outerwear));
        expect(o.items.map((i) => i.id.value), isNot(contains('shorts')));
        expect(o.items.map((i) => i.id.value), isNot(contains('sandals')));
      }
      final best = out.first.items.map((i) => i.id.value).toSet();
      expect(best, contains('coat'));
      expect(best, contains('boots'));
      expect(out.first.weatherReasons.first, startsWith('Cold'));
    });

    test('rain: the waterproof layer, closed non-suede shoes', () {
      final out = builder.suggest(wardrobe, req(day(14, 17, rain: 90)));
      final best = out.first.items.map((i) => i.id.value).toSet();
      expect(best, contains('mac'));
      expect(best, isNot(contains('sandals')));
      expect(best, isNot(contains('suedes')));
      expect(out.first.weatherReasons.first, contains('a waterproof jacket'));
      expect(out.first.weatherReasons.first, contains('closed shoes'));
    });

    test('a coat is allowed for everyday when the weather asks for a layer',
        () {
      final only = [
        item('tee', ItemType.tShirt),
        item('jeans', ItemType.jeans),
        item('coat', ItemType.coat),
      ];
      final without =
          builder.suggest(only, const OutfitRequest(includeFootwear: false));
      expect(ids(without).any((s) => s.contains('coat')), isFalse);
      final cold = builder.suggest(
        only,
        OutfitRequest(
          includeFootwear: false,
          needs: DressingNeeds.of(day(-2, 3)),
        ),
      );
      expect(ids(cold).single, contains('coat'));
    });

    test('a small wardrobe still gets a suggestion, and says what is missing',
        () {
      final small = [
        item('tee', ItemType.tShirt),
        item('jeans', ItemType.jeans),
        item('sandals', ItemType.sandals),
      ];
      final request = req(day(9, 12, rain: 90));
      final out = builder.suggest(small, request);
      expect(out, isNotEmpty);
      final gaps = builder.weatherGapsFor(small, request);
      expect(gaps, contains('No waterproof layer in your wardrobe'));
      expect(gaps, contains('No closed shoes in your wardrobe for the rain'));
    });

    test('gap messages', () {
      final needs = DressingNeeds.of(day(-4, 1));
      final g = weatherGaps([item('tee', ItemType.tShirt)], needs);
      expect(
          g, contains('No jacket or coat in your wardrobe for a freezing day'));
      expect(
        g,
        contains('Nothing warm to wear on top: no sweater or long sleeves'),
      );
      expect(
        g,
        contains('No boots or closed shoes in your wardrobe for the cold'),
      );

      // Jacket exists but is not tagged: say how to fix it.
      final wet = weatherGaps(
        [item('j', ItemType.jacket), item('b', ItemType.boots)],
        DressingNeeds.of(day(12, 15, rain: 90)),
      );
      expect(wet.single, startsWith('No waterproof layer in your wardrobe'));
      expect(wet.single, contains('tag'));

      expect(
        weatherGaps(
          [item('c', ItemType.coat)],
          DressingNeeds.of(day(30, 34)),
        ),
        contains(
            'Nothing light for the heat: no short sleeves, shorts or dress'),
      );

      // Nothing missing: no gaps. Items in the wash do not count.
      expect(
        weatherGaps([
          item('m', ItemType.jacket, tags: {'waterproof'}),
          item('b', ItemType.boots),
        ], DressingNeeds.of(day(12, 15, rain: 90))),
        isEmpty,
      );
      expect(
        weatherGaps([
          item('m', ItemType.jacket,
              tags: {'waterproof'}, lifecycle: LifecycleState.sold),
          item('b', ItemType.boots),
        ], DressingNeeds.of(day(12, 15, rain: 90))),
        isNotEmpty,
      );
    });

    test('a layer that is not waterproof earns an umbrella caveat', () {
      final out = builder.suggest([
        item('tee', ItemType.tShirt),
        item('jeans', ItemType.jeans),
        item('jacket', ItemType.jacket),
        item('boots', ItemType.boots),
      ], req(day(12, 15, rain: 90)));
      expect(out.first.weatherReasons.last, contains('umbrella'));
    });

    test('no weather: results are identical to a request without needs', () {
      final plain = builder.suggest(wardrobe, const OutfitRequest(count: 8));
      final explicit = builder.suggest(
        wardrobe,
        const OutfitRequest(count: 8, needs: null),
      );
      expect(explicit.map((s) => s.signature), plain.map((s) => s.signature));
      expect(plain.every((s) => s.weatherReasons.isEmpty), isTrue);
      expect(builder.weatherGapsFor(wardrobe, const OutfitRequest()), isEmpty);
    });

    test('attributes the model cannot tell give no opinion', () {
      // A blouse has no implied sleeve length; it is neither rewarded nor
      // penalised in the cold.
      final blouse = item('blouse', ItemType.blouse);
      expect(
        weatherAdjustment(blouse, DressingNeeds.of(day(-5, 0))),
        0,
      );
      // A recorded sleeve length is believed.
      final longBlouse =
          item('b2', ItemType.blouse, sleeve: SleeveLength.longSleeve);
      expect(
        weatherAdjustment(longBlouse, DressingNeeds.of(day(-5, 0))),
        greaterThan(0),
      );
    });
  });
}
