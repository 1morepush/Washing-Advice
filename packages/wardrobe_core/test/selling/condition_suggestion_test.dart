import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

WearObservation wear(
  WearType type,
  WearSeverity severity, {
  DateTime? at,
}) =>
    WearObservation(
      type: type,
      severity: severity,
      observedAt: at ?? DateTime.utc(2026, 2, 1),
    );

WardrobeItem garment({
  List<WearObservation> wearObservations = const [],
  int timesWorn = 10,
}) =>
    buildItem(
      condition: ConditionAssessment(wearObservations),
      usage: UsageStats(timesWorn: timesWorn),
    );

void main() {
  group('with wear on record', () {
    test('a hole is Fair, however small', () {
      final suggestion = suggestCondition(
        garment(
          wearObservations: [wear(WearType.hole, WearSeverity.slight)],
        ),
      );

      expect(suggestion.condition, DepopCondition.usedFair);
      expect(suggestion.reasons, ['Small hole reported.']);
      expect(suggestion.flaws, ['small hole']);
    });

    test('a tear is Fair, however small', () {
      final suggestion = suggestCondition(
        garment(
          wearObservations: [wear(WearType.tear, WearSeverity.slight)],
        ),
      );

      expect(suggestion.condition, DepopCondition.usedFair);
      expect(suggestion.reasons, ['Small tear reported.']);
    });

    test('anything severe is Fair', () {
      final suggestion = suggestCondition(
        garment(
          wearObservations: [wear(WearType.fading, WearSeverity.severe)],
        ),
      );

      expect(suggestion.condition, DepopCondition.usedFair);
      expect(suggestion.reasons, ['Severe fading reported.']);
    });

    test('anything moderate, with nothing worse, is Good', () {
      final suggestion = suggestCondition(
        garment(
          wearObservations: [wear(WearType.fading, WearSeverity.moderate)],
        ),
      );

      expect(suggestion.condition, DepopCondition.usedGood);
      expect(suggestion.reasons, ['Moderate fading reported.']);
      expect(suggestion.flaws, ['moderate fading']);
    });

    test('anything slight, with nothing worse, is Excellent', () {
      final suggestion = suggestCondition(
        garment(
          wearObservations: [wear(WearType.pilling, WearSeverity.slight)],
        ),
      );

      expect(suggestion.condition, DepopCondition.usedExcellent);
      expect(suggestion.reasons, ['Slight pilling reported.']);
      expect(suggestion.flaws, ['slight pilling']);
    });

    test('the worst thing decides, and the reasons name only what decided', () {
      final suggestion = suggestCondition(
        garment(
          wearObservations: [
            wear(WearType.pilling, WearSeverity.slight),
            wear(WearType.fading, WearSeverity.moderate),
            wear(WearType.hole, WearSeverity.slight),
          ],
        ),
      );

      expect(suggestion.condition, DepopCondition.usedFair);
      expect(suggestion.reasons, ['Small hole reported.']);
    });

    test('every flaw on record is disclosed, not only the one that decided',
        () {
      // A buyer who finds a flaw the seller knew about and left out asks for
      // their money back. The grade is Good because of the fading; the
      // pilling is still said.
      final suggestion = suggestCondition(
        garment(
          wearObservations: [
            wear(WearType.pilling, WearSeverity.slight),
            wear(WearType.fading, WearSeverity.moderate),
          ],
        ),
      );

      expect(suggestion.condition, DepopCondition.usedGood);
      expect(suggestion.flaws, ['moderate fading', 'slight pilling']);
      expect(suggestion.reasons, ['Moderate fading reported.']);
    });

    test('flaws come worst first, in the same order every time', () {
      final observations = [
        wear(WearType.pilling, WearSeverity.slight),
        wear(WearType.stain, WearSeverity.moderate),
        wear(WearType.fading, WearSeverity.moderate),
        wear(WearType.looseSeam, WearSeverity.severe),
      ];

      final forwards = suggestCondition(
        garment(wearObservations: observations),
      );
      final backwards = suggestCondition(
        garment(wearObservations: observations.reversed.toList()),
      );

      expect(forwards.flaws, [
        'severe loose seam',
        'moderate fading',
        'medium stain',
        'slight pilling',
      ]);
      expect(backwards.flaws, forwards.flaws);
    });

    test('only the latest observation of each kind counts', () {
      // A stain that was severe in January and slight after a treatment in
      // March is a slight stain.
      final suggestion = suggestCondition(
        garment(
          wearObservations: [
            wear(
              WearType.stain,
              WearSeverity.severe,
              at: DateTime.utc(2026, 1, 1),
            ),
            wear(
              WearType.stain,
              WearSeverity.slight,
              at: DateTime.utc(2026, 3, 1),
            ),
          ],
        ),
      );

      expect(suggestion.condition, DepopCondition.usedExcellent);
      expect(suggestion.flaws, ['small stain']);
    });

    test('wear on record outweighs how few times it has been worn', () {
      final suggestion = suggestCondition(
        garment(
          wearObservations: [wear(WearType.pilling, WearSeverity.slight)],
          timesWorn: 0,
        ),
      );

      expect(suggestion.condition, DepopCondition.usedExcellent);
    });

    test('is never Brand new, however much wear is missing', () {
      for (final worn in [0, 1, 3, 50]) {
        expect(
          suggestCondition(garment(timesWorn: worn)).condition,
          isNot(DepopCondition.brandNew),
          reason: '$worn wears',
        );
      }
    });
  });

  group('with no wear on record', () {
    test('never worn is Like new, and says Brand new is the person\'s call',
        () {
      final suggestion = suggestCondition(garment(timesWorn: 0));

      expect(suggestion.condition, DepopCondition.likeNew);
      expect(suggestion.reasons, [
        'Never worn in your records — Brand new only if the tags are still on.',
      ]);
      expect(suggestion.flaws, isEmpty);
    });

    test('worn once is Like new', () {
      final suggestion = suggestCondition(garment(timesWorn: 1));

      expect(suggestion.condition, DepopCondition.likeNew);
      expect(suggestion.reasons, ['Worn once, no wear reported.']);
    });

    test('worn up to three times is still Like new', () {
      final suggestion = suggestCondition(garment(timesWorn: 3));

      expect(suggestion.condition, DepopCondition.likeNew);
      expect(suggestion.reasons, ['Worn 3 times, no wear reported.']);
    });

    test('worn four times is Excellent', () {
      final suggestion = suggestCondition(garment(timesWorn: 4));

      expect(suggestion.condition, DepopCondition.usedExcellent);
      expect(suggestion.reasons, ['Worn 4 times, no wear reported.']);
      expect(suggestion.flaws, isEmpty);
    });

    test('worn a great many times is still only Excellent', () {
      // Nothing was reported, and nothing is assumed from age alone.
      final suggestion = suggestCondition(garment(timesWorn: 120));

      expect(suggestion.condition, DepopCondition.usedExcellent);
      expect(suggestion.reasons, ['Worn 120 times, no wear reported.']);
    });
  });

  group('flaw wording', () {
    String flawFor(WearType type, WearSeverity severity) => suggestCondition(
          garment(wearObservations: [wear(type, severity)]),
        ).flaws.single;

    test('reads as plain English for every kind of wear and every severity',
        () {
      expect({
        for (final type in WearType.values)
          for (final severity in WearSeverity.values)
            '${type.name}/${severity.name}': flawFor(type, severity),
      }, {
        'fading/slight': 'slight fading',
        'fading/moderate': 'moderate fading',
        'fading/severe': 'severe fading',
        'pilling/slight': 'slight pilling',
        'pilling/moderate': 'moderate pilling',
        'pilling/severe': 'severe pilling',
        'hole/slight': 'small hole',
        'hole/moderate': 'medium hole',
        'hole/severe': 'large hole',
        'tear/slight': 'small tear',
        'tear/moderate': 'medium tear',
        'tear/severe': 'large tear',
        'stain/slight': 'small stain',
        'stain/moderate': 'medium stain',
        'stain/severe': 'large stain',
        'stretchedOut/slight': 'slightly stretched out',
        'stretchedOut/moderate': 'moderately stretched out',
        'stretchedOut/severe': 'badly stretched out',
        'shrunk/slight': 'slightly shrunk',
        'shrunk/moderate': 'moderately shrunk',
        'shrunk/severe': 'badly shrunk',
        'looseSeam/slight': 'slight loose seam',
        'looseSeam/moderate': 'moderate loose seam',
        'looseSeam/severe': 'severe loose seam',
        'brokenFastener/slight': 'broken fastener',
        'brokenFastener/moderate': 'broken fastener',
        'brokenFastener/severe': 'broken fastener',
        'odour/slight': 'faint odor',
        'odour/moderate': 'noticeable odor',
        'odour/severe': 'strong odor',
      });
    });

    test('is lower case, so it can sit inside a sentence', () {
      for (final type in WearType.values) {
        for (final severity in WearSeverity.values) {
          final flaw = flawFor(type, severity);
          expect(flaw, equals(flaw.toLowerCase()));
        }
      }
    });
  });
}
