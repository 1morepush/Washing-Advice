/// Where a garment was made, from the label to the screen.
///
/// The core decides what an absence means and is tested there. This is the
/// wiring either side of it: that a country printed on a tag survives the wire
/// and reaches the item, that it is stored where the wardrobe can filter and
/// sort by it, and that nothing offers a control for a fact no garment has yet.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/scan_dto.dart';
import 'package:washing_advice/data/drift/database.dart';
import 'package:washing_advice/data/drift/drift_wardrobe_repository.dart';
import 'package:drift/native.dart';

import '../support/fixtures.dart';

void main() {
  group('reading it off the wire', () {
    Map<String, Object?> reply(Object? country) => {
      'instructions': <String, Object?>{'maxTempC': 30},
      'confidence': 0.9,
      'countryOfOrigin': ?country,
    };

    test('a country the label stated arrives intact', () {
      final result = careTagResultFromJson(
        reply({'value': 'Portugal', 'confidence': 0.94, 'source': 'tagScan'}),
      );

      expect(result.countryOfOrigin?.value, 'Portugal');
      expect(result.countryOfOrigin?.source, Provenance.tagScan);
    });

    test('the printed language is not translated on the way through', () {
      final result = careTagResultFromJson(
        reply({
          'value': 'Fabriqué en Tunisie',
          'confidence': 0.9,
          'source': 'tagScan',
        }),
      );

      expect(result.countryOfOrigin?.value, 'Fabriqué en Tunisie');
    });

    test('a label that did not say arrives as nothing', () {
      expect(careTagResultFromJson(reply(null)).countryOfOrigin, isNull);
    });

    test('a blank country is dropped rather than kept', () {
      // An empty string would filter and tally as a real place with no name.
      final result = careTagResultFromJson(
        reply({'value': '   ', 'confidence': 0.9, 'source': 'tagScan'}),
      );

      expect(result.countryOfOrigin, isNull);
    });
  });

  group('in storage, where the wardrobe can use it', () {
    late AppDatabase db;
    late DriftWardrobeRepository repository;

    WardrobeItem made(String id, String? country, {String name = 'Tee'}) {
      final base = confidentItem(id: id, name: name);
      return country == null
          ? base
          : base.copyWith(
              countryOfOrigin: Confident(
                country,
                confidence: 0.9,
                source: Provenance.tagScan,
              ),
            );
    }

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repository = DriftWardrobeRepository(db);
      await repository.saveAll([
        made('a', 'Portugal', name: 'Linen shirt'),
        made('b', 'portugal', name: 'Chinos'),
        made('c', 'Vietnam', name: 'Tee'),
        made('d', null, name: 'Unlabelled jumper'),
      ]);
    });

    tearDown(() => db.close());

    test('it round-trips through the payload', () async {
      expect(
        (await repository.byId(const ItemId('a')))!.countryOfOrigin?.value,
        'Portugal',
      );
    });

    test('filtering matches however the label was capitalised', () async {
      final found = await repository.query(
        const WardrobeQuery(countries: {'Portugal'}),
      );

      expect(found.map((i) => i.id.value), unorderedEquals(['a', 'b']));
    });

    test('a garment with no country is never a match', () async {
      final found = await repository.query(
        const WardrobeQuery(countries: {'Portugal', 'Vietnam'}),
      );

      expect(found.map((i) => i.id.value), isNot(contains('d')));
    });

    test('sorting puts the ones nobody knows about last', () async {
      final sorted = await repository.query(
        const WardrobeQuery(sort: WardrobeSort.countryOfOrigin),
      );

      expect(sorted.last.id.value, 'd');
      expect(sorted.first.countryOfOrigin?.value.toLowerCase(), 'portugal');
    });

    test('the filter sheet is offered each country once', () async {
      // Two tags printing one country differently are one place. Offering
      // both would split a wardrobe by typography.
      expect(await repository.knownCountries(), ['Portugal', 'Vietnam']);
    });

    test('the same answers come from the database and from memory', () async {
      // The two repositories are meant to be interchangeable, and a filter
      // that behaved differently in a test from in the app would make every
      // widget test a lie.
      final memory = InMemoryWardrobeRepository();
      await memory.saveAll(await repository.query(const WardrobeQuery()));

      const query = WardrobeQuery(countries: {'PORTUGAL'});
      expect(
        (await memory.query(query)).map((i) => i.id.value).toSet(),
        (await repository.query(query)).map((i) => i.id.value).toSet(),
      );
    });
  });

  group('on screen', () {
    testWidgets('no filter is offered until something says where', (
      tester,
    ) async {
      // A control with no options reads as broken rather than as a question
      // nobody has answered yet.
      final repository = InMemoryWardrobeRepository();
      await repository.save(confidentItem(id: 'a', name: 'Tee'));
      final container = ProviderContainer(
        overrides: [wardrobeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      expect(await container.read(knownCountriesProvider.future), isEmpty);
    });

    testWidgets('once one does, it is offered by name', (tester) async {
      final repository = InMemoryWardrobeRepository();
      await repository.save(
        confidentItem(id: 'a', name: 'Tee').copyWith(
          countryOfOrigin: Confident(
            'Portugal',
            confidence: 0.9,
            source: Provenance.tagScan,
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [wardrobeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      expect(await container.read(knownCountriesProvider.future), ['Portugal']);
    });
  });
}
