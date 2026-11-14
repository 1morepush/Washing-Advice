/// Whether an older build can read what is stored, and the sentence that says
/// why not.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/data_format.dart';
import 'package:washing_advice/data/drift/database.dart';
import 'package:washing_advice/data/images/image_database.dart';

void main() {
  const old = DataFormat({'wardrobe': 4, 'images': 1});

  test('a build reads everything at or below its own layouts', () {
    expect(old.cannotRead(const DataFormat({'wardrobe': 4, 'images': 1})), []);
    expect(old.cannotRead(const DataFormat({'wardrobe': 3})), []);
  });

  test('names what it cannot read, in words a person would use', () {
    expect(old.cannotRead(const DataFormat({'wardrobe': 5})), ['wardrobe']);
    expect(old.cannotRead(const DataFormat({'wardrobe': 9, 'images': 2})), [
      'wardrobe',
      'photos',
    ]);
  });

  test('a kind of storage a build has never heard of counts as zero', () {
    expect(old.cannotRead(const DataFormat({'listings': 1})), ['listings']);
    // And a build that knows more reads stored data that never mentioned it.
    expect(
      const DataFormat({
        'wardrobe': 9,
        'images': 9,
        'listings': 1,
      }).cannotRead(old),
      [],
    );
  });

  test('what is stored only goes up', () {
    expect(
      old.mergedWith(const DataFormat({'wardrobe': 2, 'images': 3})).parts,
      {'wardrobe': 4, 'images': 3},
    );
  });

  test('reads only the shape it writes', () {
    expect(DataFormat.fromJson({'wardrobe': 5, 'images': 1})?.parts, {
      'wardrobe': 5,
      'images': 1,
    });
    for (final bad in [
      null,
      'x',
      5,
      <String, Object?>{},
      {'wardrobe': '5'},
    ]) {
      expect(DataFormat.fromJson(bad), isNull, reason: '$bad');
    }
    expect(DataFormat.fromJson({'wardrobe': -1}), isNull);
  });

  test('this build declares the layouts its databases really have', () {
    expect(currentDataFormat['wardrobe'], AppDatabase.currentSchemaVersion);
    expect(currentDataFormat['images'], ImageDatabase.currentSchemaVersion);
  });

  group('whyUnreadable', () {
    test('is silent when the stored format is not newer', () {
      expect(
        whyUnreadable(
          version: '0.34.0',
          build: currentDataFormat,
          stored: currentDataFormat,
        ),
        isNull,
      );
    });

    test('says the wardrobe is in a newer format, naming the version', () {
      final stored = DataFormat({
        'wardrobe': currentDataFormat['wardrobe'] + 1,
      });
      expect(
        whyUnreadable(
          version: '0.34.0',
          build: currentDataFormat,
          stored: stored,
        ),
        'Your wardrobe has been saved in a newer format than 0.34.0 '
        'understands.',
      );
    });

    test('says so for both when both are newer', () {
      final stored = DataFormat({
        'wardrobe': currentDataFormat['wardrobe'] + 1,
        'images': currentDataFormat['images'] + 1,
      });
      expect(
        whyUnreadable(
          version: '0.30.0',
          build: currentDataFormat,
          stored: stored,
        ),
        'Your wardrobe and photos have been saved in a newer format than '
        '0.30.0 understands.',
      );
    });

    test('with no record, this build\'s own layouts are the floor', () {
      // A browser that would not keep the record must not make a build that
      // cannot open what is *certainly* here look fine.
      const tooOld = DataFormat({'wardrobe': 1, 'images': 1});
      expect(
        whyUnreadable(version: '0.1.0', build: tooOld, stored: null),
        isNotNull,
      );
    });
  });
}
