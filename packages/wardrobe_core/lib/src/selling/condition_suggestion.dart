/// A Depop condition for a garment already in the wardrobe, and why.
///
/// Somebody listing a hoodie they have owned for three years is asked to
/// grade it, and they are the worst-placed person to: they stopped seeing the
/// cuffs a long time ago. The wardrobe has been paying attention. It knows what
/// wear has been reported on the garment and how many times it has been worn,
/// which is most of what Depop's five words are asking.
///
/// This only suggests. The person looks at the garment and confirms, and the
/// reasons are there so that disagreeing is easy — "Worn 4 times, no wear
/// reported" is something to check against the thing in your hands, where a bare
/// "Used - Excellent" is something to take or leave.
library;

import '../wardrobe/model/condition.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'depop.dart';
import 'garment_facts.dart';

/// The condition to suggest, the evidence behind it, and the flaws to disclose.
final class ConditionSuggestion {
  const ConditionSuggestion({
    required this.condition,
    required this.reasons,
    required this.flaws,
  });

  final DepopCondition condition;

  /// What the suggestion rests on, one plain sentence each.
  final List<String> reasons;

  /// Every wear observation currently on record, worst first, as a buyer
  /// would want it said: `slight pilling`, `small stain`.
  ///
  /// All of them, not only the ones that decided [condition]. A buyer who
  /// finds a flaw the seller knew about and did not mention asks for their
  /// money back, so the list is complete even where the grade is not moved by
  /// it.
  final List<String> flaws;
}

/// Suggests how to describe [item]'s condition on Depop.
///
/// From the wear currently on record — the latest observation of each kind —
/// and, failing that, from how much it has been worn:
///
/// * a hole or a tear at any size, or anything severe: **Used - Fair**. Depop's
///   Fair means flaws a buyer must be told about, and a hole is one however
///   small;
/// * otherwise anything moderate: **Used - Good**;
/// * otherwise anything slight: **Used - Excellent**;
/// * with no wear reported, by how worn it is: never worn, or worn up to three
///   times, is **Like new**; worn more than that is **Used - Excellent**.
///
/// Never **Brand new**. That means unworn *and* usually still tagged, and a
/// wardrobe records neither whether the tags survived nor whether somebody
/// tried it on. When a garment has never been worn the reason says so, and
/// that Brand new is the person's call if the tags are still on.
ConditionSuggestion suggestCondition(WardrobeItem item) {
  final observations = item.condition.current.values.toList()
    ..sort(_worstFirst);
  final flaws = [
    for (final o in observations) _flawPhrase(o.type, o.severity),
  ];

  final fair = [
    for (final o in observations)
      if (_makesItFair(o)) o,
  ];
  if (fair.isNotEmpty) {
    return ConditionSuggestion(
      condition: DepopCondition.usedFair,
      reasons: _reported(fair),
      flaws: flaws,
    );
  }

  final moderate = _withSeverity(observations, WearSeverity.moderate);
  if (moderate.isNotEmpty) {
    return ConditionSuggestion(
      condition: DepopCondition.usedGood,
      reasons: _reported(moderate),
      flaws: flaws,
    );
  }

  final slight = _withSeverity(observations, WearSeverity.slight);
  if (slight.isNotEmpty) {
    return ConditionSuggestion(
      condition: DepopCondition.usedExcellent,
      reasons: _reported(slight),
      flaws: flaws,
    );
  }

  final worn = item.usage.timesWorn;
  if (worn <= 0) {
    return const ConditionSuggestion(
      condition: DepopCondition.likeNew,
      reasons: [
        'Never worn in your records — Brand new only if the tags are still on.',
      ],
      flaws: [],
    );
  }

  return ConditionSuggestion(
    condition: worn <= _likeNewWears
        ? DepopCondition.likeNew
        : DepopCondition.usedExcellent,
    reasons: ['Worn ${timesWornPhrase(worn)}, no wear reported.'],
    flaws: const [],
  );
}

/// Up to this many wears, with nothing reported, a garment is still Like new.
const int _likeNewWears = 3;

bool _makesItFair(WearObservation o) =>
    o.type == WearType.hole ||
    o.type == WearType.tear ||
    o.severity == WearSeverity.severe;

List<WearObservation> _withSeverity(
  List<WearObservation> observations,
  WearSeverity severity,
) =>
    [
      for (final o in observations)
        if (o.severity == severity) o,
    ];

/// Worst first, and by kind of wear within a severity so the order is the same
/// every time rather than whichever observation happened to be recorded last.
int _worstFirst(WearObservation a, WearObservation b) {
  final bySeverity = b.severity.index.compareTo(a.severity.index);
  return bySeverity != 0 ? bySeverity : a.type.index.compareTo(b.type.index);
}

List<String> _reported(List<WearObservation> observations) => [
      for (final o in observations)
        '${_sentenceCase(_flawPhrase(o.type, o.severity))} reported.',
    ];

String _sentenceCase(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// One flaw in the words a seller would use: `slight pilling`, `small stain`.
///
/// Per kind of wear rather than assembled from the two labels, because the
/// labels do not compose — "slight stretched out" and "severe hole" are not
/// things anyone says. Exhaustive, so a new kind of wear has to be given words
/// before it can appear in a listing.
String _flawPhrase(WearType type, WearSeverity severity) => switch (type) {
      WearType.fading => '${_degree(severity)} fading',
      WearType.pilling => '${_degree(severity)} pilling',
      WearType.looseSeam => '${_degree(severity)} loose seam',
      WearType.hole => '${_size(severity)} hole',
      WearType.tear => '${_size(severity)} tear',
      WearType.stain => '${_size(severity)} stain',
      WearType.stretchedOut => '${_manner(severity)} stretched out',
      WearType.shrunk => '${_manner(severity)} shrunk',
      WearType.odour => '${_strength(severity)} odor',
      WearType.brokenFastener => 'broken fastener',
    };

String _degree(WearSeverity severity) => severity.label.toLowerCase();

String _size(WearSeverity severity) => switch (severity) {
      WearSeverity.slight => 'small',
      WearSeverity.moderate => 'medium',
      WearSeverity.severe => 'large',
    };

String _manner(WearSeverity severity) => switch (severity) {
      WearSeverity.slight => 'slightly',
      WearSeverity.moderate => 'moderately',
      WearSeverity.severe => 'badly',
    };

String _strength(WearSeverity severity) => switch (severity) {
      WearSeverity.slight => 'faint',
      WearSeverity.moderate => 'noticeable',
      WearSeverity.severe => 'strong',
    };
