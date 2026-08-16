/// Deciding which observed wear is worth asking about.
///
/// The two failures worth pinning are opposite. A review that passed
/// everything would cry pilling at shadows, and a feature people learn to
/// ignore is worse than no feature — they miss the real one. A review that
/// passed nothing new would confirm facts the user typed in themselves,
/// wasting the one moment of attention this gets.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16);
  final lastWeek = DateTime.utc(2026, 8, 9);

  WardrobeItem itemWith(List<WearObservation> observations) {
    final built = WardrobeItem(
      id: const ItemId('jumper'),
      name: 'Wool jumper',
      type: Confident(
        ItemType.sweater,
        confidence: 0.95,
        source: Provenance.aiInference,
      ),
      composition: Confident(
        FabricComposition(const {Fiber.wool: 100}),
        confidence: 0.95,
        source: Provenance.tagScan,
      ),
      colors: Confident(
        ColorPalette([ItemColor.fromHex('#1F2A44')]),
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      condition: ConditionAssessment(observations),
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return built.copyWith(care: const CareResolver().forItem(built).profile);
  }

  final pristine = itemWith(const []);

  WearObservation recorded(WearType type, WearSeverity severity) =>
      WearObservation(type: type, severity: severity, observedAt: lastWeek);

  ObservedWear seen(
    WearType type,
    WearSeverity severity, {
    double confidence = 0.9,
    String? note,
  }) =>
      ObservedWear(
        type: type,
        severity: severity,
        confidence: confidence,
        note: note,
      );

  ConditionReport read(List<ObservedWear> observed, {WardrobeItem? item}) =>
      const ConditionReview()
          .read(observed, item: item ?? pristine, at: now);

  test('wear on a garment nothing is known about is worth asking about', () {
    final report = read([seen(WearType.pilling, WearSeverity.moderate)]);

    expect(report.noticed, hasLength(1));
    expect(report.noticed.single.type, WearType.pilling);
    expect(report.dismissed, isEmpty);
  });

  test('the model is not sure enough to be worth interrupting for', () {
    // A feature that cries pilling at shadows is one people learn to ignore,
    // and then they miss the real one.
    final report = read([
      seen(WearType.hole, WearSeverity.severe, confidence: 0.4),
    ]);

    expect(report.noticed, isEmpty);
    expect(report.dismissed.single.why, WearDismissal.unsure);
  });

  test('where to look is carried through in the model\'s own words', () {
    // What lets somebody check the claim against the garment in two seconds.
    // A report of pilling with nowhere to look is one nobody can confirm.
    final report = read([
      seen(
        WearType.pilling,
        WearSeverity.moderate,
        note: 'along the inner sleeve',
      ),
    ]);

    expect(report.noticed.single.observed.note, 'along the inner sleeve');
  });

  group('what is already known', () {
    test('the same problem at the same severity is not news', () {
      final report = read(
        [seen(WearType.pilling, WearSeverity.moderate)],
        item: itemWith([recorded(WearType.pilling, WearSeverity.moderate)]),
      );

      expect(report.noticed, isEmpty);
      expect(report.dismissed.single.why, WearDismissal.alreadyKnown);
    });

    test('but getting worse is the whole point', () {
      final report = read(
        [seen(WearType.pilling, WearSeverity.severe)],
        item: itemWith([recorded(WearType.pilling, WearSeverity.slight)]),
      );

      expect(report.noticed.single.severity, WearSeverity.severe);
    });

    test('a hole does not close up on its own', () {
      // A photograph reporting less than the record is a worse look at the
      // same garment, not a garment recovering. Letting it through would let a
      // hurried glance overwrite a careful one.
      final report = read(
        [seen(WearType.hole, WearSeverity.slight)],
        item: itemWith([recorded(WearType.hole, WearSeverity.severe)]),
      );

      expect(report.noticed, isEmpty);
      expect(report.dismissed.single.why, WearDismissal.lessThanKnown);
    });

    test('a stain, however, comes out', () {
      // The distinction that makes the rule above honest rather than blunt.
      final report = read(
        [seen(WearType.stain, WearSeverity.slight)],
        item: itemWith([recorded(WearType.stain, WearSeverity.severe)]),
      );

      expect(report.noticed.single.type, WearType.stain);
    });

    test('and a different problem on a worn garment is still news', () {
      final report = read(
        [seen(WearType.hole, WearSeverity.moderate)],
        item: itemWith([recorded(WearType.pilling, WearSeverity.moderate)]),
      );

      expect(report.noticed.single.type, WearType.hole);
    });
  });

  group('saying what it decides', () {
    test('wear that changes the wash says so', () {
      // The reason to interrupt anybody at all. "Your jumper is pilling" is a
      // remark; "and it will be washed more gently from now on" is a
      // consequence, and a screen that hid the second would be asking for a
      // decision without saying what it decides.
      final report = read([seen(WearType.pilling, WearSeverity.moderate)]);

      expect(report.noticed.single.changesCare, isTrue);
      expect(report.changesCare, isTrue);
    });

    test('wear that changes nothing does not claim to', () {
      final report = read([seen(WearType.shrunk, WearSeverity.moderate)]);

      expect(report.noticed.single.changesCare, isFalse);
      expect(report.changesCare, isFalse);
    });

    test('and neither does wear on a garment already handled gently', () {
      // Already washed gently because of the pilling. A second warning that it
      // will now be washed gently is a promise the app already keeps.
      final report = read(
        [seen(WearType.tear, WearSeverity.moderate)],
        item: itemWith([recorded(WearType.pilling, WearSeverity.severe)]),
      );

      expect(report.noticed.single.changesCare, isFalse);
    });
  });

  test('an accepted observation records what the model actually said', () {
    final report = read([
      seen(WearType.pilling, WearSeverity.moderate, note: 'at the cuffs'),
    ]);

    final observation = report.noticed.single.asObservation(
      now,
      photoUri: 'file://check.png',
    );

    expect(observation.type, WearType.pilling);
    expect(observation.severity, WearSeverity.moderate);
    expect(observation.observedAt, now);
    expect(observation.note, 'at the cuffs');
    // Evidence, so the next check can be compared against this one rather than
    // against a memory of it.
    expect(observation.photoUri, 'file://check.png');
  });

  test('one dismissal does not take the rest with it', () {
    final report = read([
      seen(WearType.pilling, WearSeverity.moderate),
      seen(WearType.hole, WearSeverity.severe, confidence: 0.2),
      seen(WearType.fading, WearSeverity.slight),
    ]);

    expect(report.noticed, hasLength(2));
    expect(report.dismissed, hasLength(1));
  });

  test('a garment with nothing wrong with it is an empty report', () {
    final report = read(const []);

    expect(report.isEmpty, isTrue);
    expect(report.changesCare, isFalse);
  });
}
