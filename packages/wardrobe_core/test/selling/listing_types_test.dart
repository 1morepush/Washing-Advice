import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/selling_fixtures.dart';

void main() {
  group('ListingId', () {
    test('is equal to another with the same value', () {
      expect(const ListingId('a'), const ListingId('a'));
      expect(const ListingId('a').hashCode, const ListingId('a').hashCode);
      expect(const ListingId('a'), isNot(const ListingId('b')));
    });

    test('is not an ItemId, even holding the same text', () {
      // The point of a typed id: swapping one for the other fails.
      expect(const ListingId('a') == const ItemId('a'), isFalse);
    });

    test('prints as its type and value', () {
      expect(const ListingId('abc').toString(), 'ListingId(abc)');
    });
  });

  group('ListingShot', () {
    test('has a label and a reason a buyer would care about', () {
      expect({
        for (final s in ListingShot.values) s.name: s.label
      }, {
        'cover': 'Cover',
        'back': 'Back',
        'brandTag': 'Brand tag',
        'sizeLabel': 'Size label',
        'careLabel': 'Care label',
        'flaw': 'Flaw',
        'other': 'Other',
      });
      for (final shot in ListingShot.values) {
        expect(shot.why, isNotEmpty, reason: shot.name);
      }
    });

    test('gives the briefing\'s reason for each of the asked-for shots', () {
      expect(ListingShot.cover.why, contains('first thing a buyer sees'));
      expect(ListingShot.back.why, contains('back for marks'));
      expect(ListingShot.brandTag.why, contains('brand'));
      expect(ListingShot.sizeLabel.why, contains('most common message'));
      expect(ListingShot.flaw.why, contains('disclosed flaw, not a return'));
    });

    test('asks for cover, back, brand tag and size label on every listing', () {
      expect({
        for (final s in ListingShot.values)
          if (s.isChecklist) s,
      }, {
        ListingShot.cover,
        ListingShot.back,
        ListingShot.brandTag,
        ListingShot.sizeLabel,
      });
    });

    test(
        'a flaw is not a checklist item, since it is asked for only when '
        'flaws are listed', () {
      expect(ListingShot.flaw.isChecklist, isFalse);
    });

    test('is made from a wardrobe photo role without asking again', () {
      expect({
        for (final r in PhotoRole.values) r: ListingShot.fromPhotoRole(r),
      }, {
        PhotoRole.front: ListingShot.cover,
        PhotoRole.back: ListingShot.back,
        PhotoRole.brandTag: ListingShot.brandTag,
        PhotoRole.careTag: ListingShot.careLabel,
        PhotoRole.condition: ListingShot.flaw,
        PhotoRole.logo: ListingShot.other,
        PhotoRole.detail: ListingShot.other,
        PhotoRole.worn: ListingShot.other,
      });
    });
  });

  group('ListingPhoto', () {
    test('holds the image-store uri and what the photograph is of', () {
      const photo = ListingPhoto(uri: 'store://a.jpg', shot: ListingShot.back);

      expect(photo.uri, 'store://a.jpg');
      expect(photo.shot, ListingShot.back);
    });

    test('copies with a different shot', () {
      const photo = ListingPhoto(uri: 'store://a.jpg', shot: ListingShot.other);

      expect(photo.copyWith(shot: ListingShot.flaw).shot, ListingShot.flaw);
      expect(photo.copyWith(shot: ListingShot.flaw).uri, 'store://a.jpg');
    });

    test('is equal by value', () {
      const a = ListingPhoto(uri: 'u', shot: ListingShot.cover);
      const b = ListingPhoto(uri: 'u', shot: ListingShot.cover);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(shot: ListingShot.back)));
    });

    test('survives a round trip', () {
      const photo = ListingPhoto(uri: 'store://a.jpg', shot: ListingShot.flaw);

      expect(ListingPhoto.tryFromJson(photo.toJson()), photo);
    });

    test('reads an unknown shot as Other, and no uri as nothing', () {
      expect(
        ListingPhoto.tryFromJson({'uri': 'u', 'shot': 'sideways'})?.shot,
        ListingShot.other,
      );
      expect(ListingPhoto.tryFromJson({'shot': 'cover'}), isNull);
      expect(ListingPhoto.tryFromJson({'uri': '', 'shot': 'cover'}), isNull);
    });
  });

  group('Measurements', () {
    test('is empty until something is measured', () {
      expect(Measurements.none.isEmpty, isTrue);
      expect(const Measurements().isEmpty, isTrue);
      expect(const Measurements(lengthIn: 27).isEmpty, isFalse);
    });

    test('lists what was given in the order a buyer reads it', () {
      const m = Measurements(
        inseamIn: 32,
        pitToPitIn: 21,
        waistIn: 30,
        lengthIn: 27.5,
        sleeveIn: 24,
      );

      expect([
        for (final e in m.given) (e.label, e.inches),
      ], [
        ('pit to pit', 21.0),
        ('length', 27.5),
        ('sleeve', 24.0),
        ('waist', 30.0),
        ('inseam', 32.0),
      ]);
    });

    test('leaves out what was not measured', () {
      const m = Measurements(pitToPitIn: 21, inseamIn: 32);

      expect([for (final e in m.given) e.label], ['pit to pit', 'inseam']);
    });

    test('treats zero, a negative and not-a-number as not measured', () {
      final m = Measurements(
        pitToPitIn: 0,
        lengthIn: -3,
        sleeveIn: double.nan,
        waistIn: double.infinity,
        inseamIn: 32,
      );

      expect([for (final e in m.given) e.label], ['inseam']);
      expect(const Measurements(pitToPitIn: 0).isEmpty, isTrue);
    });

    test('copyWith changes one and keeps the rest', () {
      const m = Measurements(pitToPitIn: 21, lengthIn: 27);
      final changed = m.copyWith(lengthIn: 28);

      expect(changed.pitToPitIn, 21);
      expect(changed.lengthIn, 28);
    });

    test('copyWith can take a measurement back', () {
      const m = Measurements(
        pitToPitIn: 21,
        lengthIn: 27,
        sleeveIn: 24,
        waistIn: 30,
        inseamIn: 32,
      );

      expect(m.copyWith(clearPitToPit: true).pitToPitIn, isNull);
      expect(m.copyWith(clearLength: true).lengthIn, isNull);
      expect(m.copyWith(clearSleeve: true).sleeveIn, isNull);
      expect(m.copyWith(clearWaist: true).waistIn, isNull);
      expect(m.copyWith(clearInseam: true).inseamIn, isNull);
      // And only the one asked for.
      expect(m.copyWith(clearLength: true).pitToPitIn, 21);
    });

    test('is equal by value', () {
      expect(
        const Measurements(pitToPitIn: 21),
        const Measurements(pitToPitIn: 21),
      );
      expect(
        const Measurements(pitToPitIn: 21).hashCode,
        const Measurements(pitToPitIn: 21).hashCode,
      );
      expect(
        const Measurements(pitToPitIn: 21),
        isNot(const Measurements(pitToPitIn: 22)),
      );
    });

    test('survives a round trip, writing only what was measured', () {
      const m = Measurements(pitToPitIn: 21.5, inseamIn: 32);

      expect(m.toJson(), {'pitToPitIn': 21.5, 'inseamIn': 32.0});
      expect(Measurements.fromJson(viaText(m.toJson())), m);
    });

    test('reads whole numbers as inches too', () {
      expect(Measurements.fromJson({'lengthIn': 27}).lengthIn, 27.0);
    });
  });

  group('SearchQueries', () {
    test('is searchable when both phrases are long enough', () {
      expect(
        const SearchQueries(depop: 'nike hoodie', retail: 'nike hoodie')
            .isSearchable,
        isTrue,
      );
    });

    test('is not searchable when either phrase is too short for the server',
        () {
      expect(
        const SearchQueries(depop: 'ab', retail: 'nike hoodie').isSearchable,
        isFalse,
      );
      expect(
        const SearchQueries(depop: 'nike hoodie', retail: ' a ').isSearchable,
        isFalse,
      );
      expect(
        const SearchQueries(depop: '', retail: '').isSearchable,
        isFalse,
      );
    });

    test('knows the limits the contract sets', () {
      expect(SearchQueries.minLength, 3);
      expect(SearchQueries.maxLength, 120);
    });

    test('copies with one phrase changed', () {
      const q = SearchQueries(depop: 'a b c', retail: 'd e f');

      expect(q.copyWith(depop: 'x y z').depop, 'x y z');
      expect(q.copyWith(depop: 'x y z').retail, 'd e f');
    });

    test('is equal by value and survives a round trip', () {
      const q = SearchQueries(depop: 'a b c', retail: 'd e f');

      expect(q, const SearchQueries(depop: 'a b c', retail: 'd e f'));
      expect(q.hashCode,
          const SearchQueries(depop: 'a b c', retail: 'd e f').hashCode);
      expect(SearchQueries.fromJson(q.toJson()), q);
    });

    test('reads missing phrases as empty rather than failing', () {
      final q = SearchQueries.fromJson({'depop': 'nike hoodie'});

      expect(q.retail, '');
      expect(q.isSearchable, isFalse);
    });
  });

  group('ExcludedCounts', () {
    test('adds up what was dropped', () {
      const excluded = ExcludedCounts(
        notUsd: 2,
        unverifiedPrice: 1,
        notComparable: 4,
      );

      expect(excluded.total, 7);
      expect(ExcludedCounts.none.total, 0);
    });

    test('is equal by value and survives a round trip', () {
      const excluded = ExcludedCounts(notUsd: 2, notComparable: 4);

      expect(excluded, const ExcludedCounts(notUsd: 2, notComparable: 4));
      expect(ExcludedCounts.fromJson(excluded.toJson()), excluded);
    });

    test('reads missing counts as zero', () {
      expect(ExcludedCounts.fromJson(const {}).total, 0);
    });
  });

  group('SaleComparable and RetailReference', () {
    test('a comparable survives a round trip through JSON text', () {
      final original = comparable();

      expect(
        SaleComparable.tryFromJson(viaText(original.toJson())),
        original,
      );
    });

    test('keeps an unknown sold state unknown', () {
      final unknown = comparable(sold: null, condition: null, why: null);
      final back = SaleComparable.tryFromJson(viaText(unknown.toJson()))!;

      expect(back.sold, isNull);
      expect(back.condition, isNull);
      expect(back.why, isNull);
    });

    test('a comparable without a usable link or price is not readable', () {
      final json = comparable().toJson();

      expect(SaleComparable.tryFromJson({...json}..remove('url')), isNull);
      expect(SaleComparable.tryFromJson({...json, 'url': 'nonsense'}), isNull);
      expect(
          SaleComparable.tryFromJson({...json}..remove('priceCents')), isNull);
      expect(SaleComparable.tryFromJson({...json}..remove('title')), isNull);
    });

    test('an unknown match reads as similar, the cautious one', () {
      final json = {...comparable().toJson(), 'match': 'exact'};

      expect(SaleComparable.tryFromJson(json)!.match, ComparableMatch.similar);
    });

    test('a reference survives a round trip through JSON text', () {
      final original = reference();

      expect(
        RetailReference.tryFromJson(viaText(original.toJson())),
        original,
      );
    });

    test('a reference without a usable link or price is not readable', () {
      final json = reference().toJson();

      expect(RetailReference.tryFromJson({...json}..remove('url')), isNull);
      expect(
          RetailReference.tryFromJson({...json}..remove('priceCents')), isNull);
    });

    test('are equal by value', () {
      expect(comparable(), comparable());
      expect(comparable().hashCode, comparable().hashCode);
      expect(comparable(), isNot(comparable(priceCents: 100)));
      expect(reference(), reference());
      expect(reference(), isNot(reference(priceCents: 100)));
    });
  });

  group('PriceSearch', () {
    test('survives a round trip through JSON text, every field', () {
      final original = fullSearch();
      final back = PriceSearch.fromJson(viaText(original.toJson()));

      expect(back, original);
      expect(back.status, PriceSearchStatus.ok);
      expect(back.searchedAt, DateTime.utc(2026, 10, 17, 14, 5));
      expect(back.provider, 'tavily');
      expect(back.comparables, hasLength(2));
      expect(back.retail, hasLength(1));
      expect(back.excluded.total, 7);
    });

    test('stores prices in cents, not dollars', () {
      final json = fullSearch().toJson();
      final first = (json['comparables']! as List<Object?>).first!
          as Map<String, Object?>;

      expect(first['priceCents'], 3200);
      expect(first.containsKey('price'), isFalse);
    });

    test('skips an entry it cannot read and keeps the rest', () {
      final json = fullSearch().toJson();
      (json['comparables']! as List<Object?>).insert(0, {'title': 'no link'});

      final back = PriceSearch.fromJson(json);

      expect(back.comparables, hasLength(2));
    });

    test('reads an unknown status as unavailable', () {
      final json = {...fullSearch().toJson(), 'status': 'rateLimited'};

      expect(PriceSearch.fromJson(json).status, PriceSearchStatus.unavailable);
    });

    test('a failed search keeps the phrases that were searched', () {
      final failed = PriceSearch(
        status: PriceSearchStatus.notConfigured,
        queries:
            const SearchQueries(depop: 'nike hoodie', retail: 'nike hoodie'),
      );
      final back = PriceSearch.fromJson(viaText(failed.toJson()));

      expect(back.status, PriceSearchStatus.notConfigured);
      expect(back.queries.depop, 'nike hoodie');
      expect(back.comparables, isEmpty);
      expect(back.searchedAt, isNull);
    });

    test('its lists cannot be changed afterwards', () {
      final search = fullSearch();

      expect(
          () => search.comparables.add(comparable()), throwsUnsupportedError);
      expect(() => search.retail.add(reference()), throwsUnsupportedError);
    });

    test('is equal by value', () {
      expect(fullSearch(), fullSearch());
      expect(fullSearch().hashCode, fullSearch().hashCode);
      expect(
        fullSearch(),
        isNot(
          PriceSearch(
            status: PriceSearchStatus.ok,
            queries: fullSearch().queries,
          ),
        ),
      );
    });
  });

  group('ListingFacts', () {
    test('survives a round trip through JSON text, every field', () {
      final original = fullFacts();
      final back = ListingFacts.fromJson(viaText(original.toJson()));

      expect(back, original);
      expect(back.brand!.value, 'Nike');
      expect(back.brand!.confidence, closeTo(0.93, 1e-9));
      expect(back.brand!.source, Provenance.aiInference);
      expect(back.sizeOnTag!.value, 'M');
      expect(back.era, '90s');
    });

    test('writes the contract\'s own shape', () {
      final json = fullFacts().toJson();

      expect(json.keys.toSet(), {
        'title',
        'itemType',
        'brand',
        'colors',
        'material',
        'sizeOnTag',
        'styleWords',
        'era',
        'visibleFlaws',
        'searchQueries',
      });
      expect(json['itemType'], 'sweatshirt');
      expect(json['brand'], {
        'value': 'Nike',
        'confidence': 0.93,
        'source': 'aiInference',
      });
    });

    test('leaves out what the photographs did not show', () {
      final minimal = ListingFacts(
        title: 'Grey crewneck sweatshirt',
        itemType: ItemType.sweatshirt,
        searchQueries: const SearchQueries(
          depop: 'grey crewneck sweatshirt',
          retail: 'grey crewneck sweatshirt',
        ),
      );
      final json = minimal.toJson();

      expect(json.containsKey('brand'), isFalse);
      expect(json.containsKey('material'), isFalse);
      expect(json.containsKey('sizeOnTag'), isFalse);
      expect(json.containsKey('era'), isFalse);
      expect(ListingFacts.fromJson(json), minimal);
    });

    test('an unknown item type is Other', () {
      final json = {...fullFacts().toJson(), 'itemType': 'poncho'};

      expect(ListingFacts.fromJson(json).itemType, ItemType.other);
    });

    test('without search phrases, the title stands in for both', () {
      final json = fullFacts().toJson()..remove('searchQueries');
      final facts = ListingFacts.fromJson(json);

      expect(facts.searchQueries.depop, facts.title);
      expect(facts.searchQueries.retail, facts.title);
    });

    test('trims what it reads and drops empty entries', () {
      final facts = ListingFacts.fromJson({
        ...fullFacts().toJson(),
        'title': '  Nike hoodie  ',
        'colors': [' Grey ', '', '  '],
        'visibleFlaws': ['  small mark  ', ''],
      });

      expect(facts.title, 'Nike hoodie');
      expect(facts.colors, ['Grey']);
      expect(facts.visibleFlaws, ['small mark']);
    });

    test('a brand with no confidence is not trusted', () {
      final facts = ListingFacts.fromJson({
        ...fullFacts().toJson(),
        'brand': {'value': 'Nike'},
      });

      expect(facts.brand!.value, 'Nike');
      expect(facts.brand!.confidence, 0.0);
    });

    test('a brand that is not an object is ignored', () {
      final facts = ListingFacts.fromJson({
        ...fullFacts().toJson(),
        'brand': 'Nike',
      });

      expect(facts.brand, isNull);
    });

    test('an out-of-range confidence is held to the range', () {
      final facts = ListingFacts.fromJson({
        ...fullFacts().toJson(),
        'brand': {'value': 'Nike', 'confidence': 4.2, 'source': 'aiInference'},
      });

      expect(facts.brand!.confidence, 1.0);
    });

    test('its lists cannot be changed afterwards', () {
      expect(() => fullFacts().colors.add('Red'), throwsUnsupportedError);
      expect(() => fullFacts().styleWords.add('x'), throwsUnsupportedError);
      expect(() => fullFacts().visibleFlaws.add('x'), throwsUnsupportedError);
    });

    test('is equal by value', () {
      expect(fullFacts(), fullFacts());
      expect(fullFacts().hashCode, fullFacts().hashCode);
    });
  });
}
