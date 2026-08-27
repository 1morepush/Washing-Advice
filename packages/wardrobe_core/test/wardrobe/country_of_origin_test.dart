/// Where a garment was made.
///
/// Printed on most care labels, alongside the symbols, and worth keeping for
/// the same reason the fibre content is: it is a fact about the garment that
/// nothing else can recover once the tag is cut out.
///
/// What is tested here is the awkward half — the garments whose label never
/// said. Those are the majority of any real wardrobe, and every rule below
/// exists so an absence is reported as an absence rather than quietly folded
/// in with the ones that do have an answer.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 21);

  WardrobeItem item(String id, {String? madeIn, String name = 'Tee'}) {
    final built = WardrobeItem(
      id: ItemId(id),
      name: name,
      type: Confident(
        ItemType.tShirt,
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
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
      countryOfOrigin: madeIn == null
          ? null
          : Confident(madeIn, confidence: 0.9, source: Provenance.tagScan),
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return built.copyWith(care: const CareResolver().forItem(built).profile);
  }

  group('keeping it', () {
    test('it survives a round trip through storage', () {
      final saved = item('a', madeIn: 'Portugal');

      final read = WardrobeItem.fromJson(saved.toJson());

      expect(read.countryOfOrigin?.value, 'Portugal');
      expect(read.countryOfOrigin?.source, Provenance.tagScan);
    });

    test('a garment whose label never said stays null, not empty', () {
      // An empty string would filter and tally as a real place called "".
      final read = WardrobeItem.fromJson(item('a').toJson());

      expect(read.countryOfOrigin, isNull);
    });
  });

  group('filtering', () {
    late InMemoryWardrobeRepository repository;

    setUp(() async {
      repository = InMemoryWardrobeRepository();
      await repository.saveAll([
        item('a', madeIn: 'Portugal', name: 'Linen shirt'),
        item('b', madeIn: 'portugal', name: 'Chinos'),
        item('c', madeIn: 'Vietnam', name: 'Tee'),
        item('d', name: 'Unlabelled jumper'),
      ]);
    });

    test('it matches however the label happened to be capitalised', () async {
      // Two tags for the same country, printed differently. Treating them as
      // different places would split a wardrobe by typography.
      final found = await repository.query(
        const WardrobeQuery(countries: {'Portugal'}),
      );

      expect(found.map((i) => i.id.value), unorderedEquals(['a', 'b']));
    });

    test('a garment with no country is never a match', () async {
      final found = await repository.query(
        const WardrobeQuery(countries: {'Vietnam'}),
      );

      expect(found.map((i) => i.id.value), ['c']);
    });

    test('it counts as a filter that is switched on', () async {
      // Otherwise the wardrobe screen shows an unbadged funnel while hiding
      // most of somebody's clothes.
      expect(
        const WardrobeQuery(countries: {'Portugal'}).activeFilterCount,
        1,
      );
    });

    test('the filter sheet is offered what the wardrobe actually has',
        () async {
      // Every country in the world would be a list nobody scrolls.
      expect(await repository.knownCountries(), ['Portugal', 'Vietnam']);
    });
  });

  group('sorting', () {
    test('unknown sorts last, because an absence is not a place', () async {
      final repository = InMemoryWardrobeRepository();
      await repository.saveAll([
        item('none', name: 'No label'),
        item('viet', madeIn: 'Vietnam', name: 'Tee'),
        item('port', madeIn: 'Portugal', name: 'Shirt'),
      ]);

      final sorted = await repository.query(
        const WardrobeQuery(sort: WardrobeSort.countryOfOrigin),
      );

      expect(sorted.map((i) => i.id.value), ['port', 'viet', 'none']);
    });

    test('garments from one country come out in a stable order', () async {
      // Otherwise the view reshuffles on every save, which reads as a bug.
      final repository = InMemoryWardrobeRepository();
      await repository.saveAll([
        item('z', madeIn: 'Portugal', name: 'Zip hoodie'),
        item('a', madeIn: 'Portugal', name: 'Anorak'),
      ]);

      final sorted = await repository.query(
        const WardrobeQuery(sort: WardrobeSort.countryOfOrigin),
      );

      expect(sorted.map((i) => i.id.value), ['a', 'z']);
    });
  });

  group('what the wardrobe adds up to', () {
    test('it groups on the printed words, whatever their case', () {
      final summary = WardrobeSummary([
        item('a', madeIn: 'Portugal'),
        item('b', madeIn: 'PORTUGAL'),
        item('c', madeIn: 'Vietnam'),
      ]);

      final tallies = summary.byCountryOfOrigin;

      expect(tallies.first.key, 'Portugal');
      expect(tallies.first.count, 2);
      expect(tallies.map((t) => t.key), containsAll(['Portugal', 'Vietnam']));
    });

    test('the unknowns are reported rather than folded in', () {
      // The rule that keeps this honest. A wardrobe with one read label would
      // otherwise chart as 100% from one country.
      final summary = WardrobeSummary([
        item('a', madeIn: 'Portugal'),
        item('b'),
        item('c'),
        item('d'),
      ]);

      expect(summary.withoutCountry, 3);
      expect(summary.byCountryOfOrigin.single.count, 1);
      // A quarter of the wardrobe, not all of the part that was known.
      expect(summary.byCountryOfOrigin.single.share, closeTo(0.25, 0.001));
    });

    test('a wardrobe nobody has scanned a label for charts nothing', () {
      final summary = WardrobeSummary([item('a'), item('b')]);

      expect(summary.byCountryOfOrigin, isEmpty);
      expect(summary.withoutCountry, 2);
    });
  });
}
