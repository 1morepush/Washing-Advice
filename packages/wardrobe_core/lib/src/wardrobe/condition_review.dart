/// Wear a model believes it can see, checked before anybody is told about it.
///
/// The vision side of [ConditionAssessment], which has existed since M1 with
/// nothing to feed it but a form. Automatic detection is worth having because
/// nobody opens a form to report pilling: the condition of a wardrobe is
/// exactly the sort of fact that is true, useful, changes how things get
/// washed, and never gets entered by hand.
///
/// ## Why this is not simply recorded
///
/// A wear observation is not cosmetic. It changes the grade, it can push a
/// garment to [ConditionGrade.endOfLife], and through
/// [ConditionAssessment.warrantsGentlerCare] it changes how the thing is
/// washed from the next load onward. A model that mistook a shadow for a hole
/// would silently rewrite laundry advice on evidence nobody saw.
///
/// So nothing here records anything. It reads proposals and says which are
/// worth *asking about*, which is the same division of labour as everywhere
/// else: the model perceives, and something else decides.
///
/// ## What is checked
///
/// * A guess is worse than silence. Below the confidence floor it is dropped,
///   because a feature that cries pilling at shadows is one people learn to
///   ignore — and then miss the real one.
/// * What is already on record is not news. Confirming a fact the user entered
///   themselves last week wastes the one moment of their attention this feature
///   gets.
/// * Clothes do not un-wear. A photograph reporting *less* of an irreversible
///   problem than is already recorded is a worse look at the same garment, not
///   a garment recovering — see [WearType.isReversible], which is why a stain
///   coming out is treated differently from a hole closing up.
library;

import 'model/condition.dart';
import 'model/wardrobe_item.dart';

/// One thing a model believes it can see on a garment.
final class ObservedWear {
  const ObservedWear({
    required this.type,
    required this.severity,
    required this.confidence,
    this.note,
  });

  final WearType type;
  final WearSeverity severity;

  /// `0..1`, the model's own assessment.
  final double confidence;

  /// Where on the garment, in the model's words — "along the inner sleeve".
  ///
  /// Shown rather than summarised, because it is what lets somebody check the
  /// claim against the actual garment in about two seconds. A report of
  /// pilling with nowhere to look is one nobody can confirm or deny.
  final String? note;
}

/// Why a proposal was not worth asking about.
enum WearDismissal {
  /// Below the confidence floor.
  unsure('Not sure enough to be worth asking about'),

  /// The same problem, at the same severity or worse, is already recorded.
  alreadyKnown('Already recorded'),

  /// Reported as less than what is already recorded, for a kind of wear that
  /// does not get better on its own.
  lessThanKnown('Less than what is already recorded');

  const WearDismissal(this.reason);

  final String reason;
}

/// A proposal worth putting to the user.
final class NoticedWear {
  const NoticedWear({required this.observed, required this.changesCare});

  final ObservedWear observed;

  /// Whether accepting this would make the app wash the garment more gently.
  ///
  /// The reason to interrupt somebody at all. "Your jumper is pilling" is a
  /// remark; "and it will be washed inside out on a gentler cycle from now on"
  /// is a consequence, and the screen that hides the second is asking for a
  /// decision without saying what it decides.
  final bool changesCare;

  WearType get type => observed.type;
  WearSeverity get severity => observed.severity;

  /// The observation to record if the user accepts it.
  WearObservation asObservation(DateTime at, {String? photoUri}) =>
      WearObservation(
        type: observed.type,
        severity: observed.severity,
        observedAt: at,
        note: observed.note,
        photoUri: photoUri,
      );
}

/// What reading a batch of proposals produced.
final class ConditionReport {
  const ConditionReport({this.noticed = const [], this.dismissed = const []});

  final List<NoticedWear> noticed;
  final List<({ObservedWear observed, WearDismissal why})> dismissed;

  bool get isEmpty => noticed.isEmpty;

  /// Whether accepting everything noticed would change how this is washed.
  bool get changesCare => noticed.any((wear) => wear.changesCare);
}

/// Decides which observed wear is worth asking a user about.
final class ConditionReview {
  const ConditionReview({this.floor = 0.6});

  /// How sure the model has to be.
  ///
  /// Deliberately higher than the floor used for garment attributes. Getting a
  /// sleeve length wrong shows a wrong word on a screen somebody can correct;
  /// getting wear wrong changes how a garment is washed and, repeated, tells
  /// somebody to throw out a jumper that is fine.
  final double floor;

  ConditionReport read(
    List<ObservedWear> observed, {
    required WardrobeItem item,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now();
    final known = item.condition.current;

    final noticed = <NoticedWear>[];
    final dismissed = <({ObservedWear observed, WearDismissal why})>[];

    void drop(ObservedWear wear, WearDismissal why) =>
        dismissed.add((observed: wear, why: why));

    for (final wear in observed) {
      if (wear.confidence < floor) {
        drop(wear, WearDismissal.unsure);
        continue;
      }

      final onRecord = known[wear.type];
      if (onRecord != null) {
        final difference = wear.severity.index - onRecord.severity.index;
        if (difference == 0) {
          drop(wear, WearDismissal.alreadyKnown);
          continue;
        }
        // Worse is always news. Better is news only for the kinds of wear that
        // can honestly get better — a stain comes out, a hole does not close.
        if (difference < 0 && !wear.type.isReversible) {
          drop(wear, WearDismissal.lessThanKnown);
          continue;
        }
      }

      noticed.add(
        NoticedWear(
          observed: wear,
          changesCare: _changesCare(item, wear, now),
        ),
      );
    }

    return ConditionReport(noticed: noticed, dismissed: dismissed);
  }

  /// Whether recording this would newly warrant gentler care.
  ///
  /// Asked of the core rather than restated. A second copy of the rule here
  /// would eventually disagree with the one actually doing the washing.
  bool _changesCare(WardrobeItem item, ObservedWear wear, DateTime now) {
    if (item.condition.warrantsGentlerCare) return false;
    return item.condition
        .record(
          WearObservation(
            type: wear.type,
            severity: wear.severity,
            observedAt: now,
          ),
        )
        .warrantsGentlerCare;
  }
}
