/// Fibre composition and the physical behaviour that follows from it.
///
/// Nearly every care decision traces back to what a garment is made of: wool
/// felts, viscose loses most of its strength when wet, elastane dies in a hot
/// dryer. Encoding those properties on the fibre itself keeps that knowledge in
/// one place instead of scattered through the rule table and the sorter.
///
/// Note what is deliberately *absent*: lint shedding. That is a property of
/// construction — terry towelling, flannel, fleece — not of the fibre. Cotton
/// jersey barely sheds while cotton towelling sheds heavily, so the behaviour
/// lives on [ItemType.producesLint] instead. Putting it here would make every
/// cotton t-shirt incompatible with every fleece and split an ordinary wash
/// into needless loads.
library;

/// How much mechanical action a fabric can survive.
///
/// Ordered from most to least fragile, so the sorter can take the minimum
/// across a load with a plain comparison.
enum FabricClass {
  /// Silk, wool, lace. Minimal agitation, low spin, usually no dryer.
  delicate(label: 'Delicate'),

  /// Cotton jersey, poly blends, most of a wardrobe.
  normal(label: 'Everyday'),

  /// Denim, canvas, towels, work wear. Tolerates a full-strength cycle.
  heavy(label: 'Heavy duty');

  const FabricClass({required this.label});

  /// How robust the item is, in words. "Everyday" rather than "Normal", which
  /// reads as a judgement about the garment instead of a washing instruction.
  final String label;

  /// The more fragile of two classes — the safe choice for a shared load.
  FabricClass leastRobust(FabricClass other) =>
      index <= other.index ? this : other;
}

/// A textile fibre, with the properties that drive its care.
enum Fiber {
  cotton(label: 'Cotton', shrinksWithHeat: true),
  linen(label: 'Linen', shrinksWithHeat: true, wrinklesReadily: true),
  hemp(label: 'Hemp', shrinksWithHeat: true),
  ramie(label: 'Ramie', shrinksWithHeat: true),

  // Protein fibres. Alkali and heat destroy them; agitation felts them.
  wool(
    label: 'Wool',
    naturalClass: FabricClass.delicate,
    isProtein: true,
    feltsWithAgitation: true,
    shrinksWithHeat: true,
    escalationThreshold: 15,
  ),
  cashmere(
    label: 'Cashmere',
    naturalClass: FabricClass.delicate,
    isProtein: true,
    feltsWithAgitation: true,
    shrinksWithHeat: true,
    escalationThreshold: 10,
  ),
  silk(
    label: 'Silk',
    naturalClass: FabricClass.delicate,
    isProtein: true,
    escalationThreshold: 10,
  ),

  // Regenerated cellulosics. Viscose in particular is notoriously weak wet.
  viscose(
    label: 'Viscose',
    naturalClass: FabricClass.delicate,
    weakensWhenWet: true,
    shrinksWithHeat: true,
    escalationThreshold: 20,
  ),
  modal(label: 'Modal', shrinksWithHeat: true),
  lyocell(label: 'Lyocell'),
  acetate(
    label: 'Acetate',
    naturalClass: FabricClass.delicate,
    weakensWhenWet: true,
    escalationThreshold: 15,
  ),

  // Thermoplastic synthetics. They melt rather than scorch, and hold odour.
  polyester(
    label: 'Polyester',
    isThermoplastic: true,
    holdsOdour: true,
    attractsLint: true,
  ),
  nylon(
    label: 'Nylon',
    isThermoplastic: true,
    holdsOdour: true,
    attractsLint: true,
  ),
  acrylic(
    label: 'Acrylic',
    isThermoplastic: true,
    pillsReadily: true,
    attractsLint: true,
  ),
  elastane(
    label: 'Elastane',
    isThermoplastic: true,
    degradesWithHeat: true,
    // A few percent is enough to ruin a garment in a hot dryer, so even a
    // trace escalates its care.
    escalationThreshold: 3,
  ),

  // Non-textiles that still turn up in a wardrobe.
  down(
    label: 'Down',
    naturalClass: FabricClass.delicate,
    escalationThreshold: 5,
  ),
  leather(
    label: 'Leather',
    naturalClass: FabricClass.delicate,
    isProtein: true,
    escalationThreshold: 1,
  ),
  other(label: 'Other');

  const Fiber({
    required this.label,
    this.naturalClass = FabricClass.normal,
    this.isProtein = false,
    this.isThermoplastic = false,
    this.feltsWithAgitation = false,
    this.shrinksWithHeat = false,
    this.degradesWithHeat = false,
    this.weakensWhenWet = false,
    this.holdsOdour = false,
    this.pillsReadily = false,
    this.wrinklesReadily = false,
    this.attractsLint = false,
    this.escalationThreshold = 50,
  });

  /// Human-readable name, as it would appear on a care label.
  final String label;

  /// How robust this fibre is on its own.
  final FabricClass naturalClass;

  /// Wool, silk, cashmere, leather. Damaged by alkaline detergent, chlorine
  /// bleach and heat.
  final bool isProtein;

  /// Melts under heat instead of scorching, and traps body odour.
  final bool isThermoplastic;

  /// Mechanical action mats the fibres irreversibly.
  final bool feltsWithAgitation;

  /// Hot water or a hot dryer shrinks it.
  final bool shrinksWithHeat;

  /// Heat destroys the fibre outright rather than merely shrinking it.
  final bool degradesWithHeat;

  /// Loses significant tensile strength while wet, so it must not be wrung,
  /// spun hard, or hung heavy to dry.
  final bool weakensWhenWet;

  /// Retains odour through a normal wash; benefits from a longer cycle.
  final bool holdsOdour;

  /// Forms surface pills with abrasion; wash inside out.
  final bool pillsReadily;

  /// Creases badly unless removed from the machine promptly.
  final bool wrinklesReadily;

  /// Collects other fabrics' lint, showing it badly.
  final bool attractsLint;

  /// The percentage at or above which this fibre dictates the garment's care.
  ///
  /// Fragile fibres take over well below the majority: 3% elastane already
  /// rules out a hot dryer, whereas 50% cotton in a blend changes nothing.
  final int escalationThreshold;
}

/// The share at or above which a fibre is worth naming when describing a
/// garment, as opposed to when deciding how to wash it.
///
/// See [FabricComposition.isDescribedBy] for why this is separate from
/// [Fiber.escalationThreshold], and flat rather than per-fibre.
const int notableFiberPercent = 5;

/// What a garment is made of, as percentages by weight.
///
/// Mirrors a care label: `80% Cotton, 20% Polyester`.
final class FabricComposition {
  /// Creates a composition, dropping zero-percent entries.
  ///
  /// Percentages are not forced to total exactly 100 — real labels round, and
  /// OCR of a curled label is imperfect. Use [isPlausible] to check.
  FabricComposition(Map<Fiber, int> percentages)
      : _percentages = Map.unmodifiable({
          for (final entry in percentages.entries)
            if (entry.value > 0) entry.key: entry.value,
        });

  /// A single-fibre garment.
  FabricComposition.pure(Fiber fiber) : this({fiber: 100});

  /// Composition is genuinely unknown, as opposed to known to be mixed.
  FabricComposition.unknown() : this(const {});

  final Map<Fiber, int> _percentages;

  Map<Fiber, int> get percentages => _percentages;

  bool get isEmpty => _percentages.isEmpty;

  Iterable<Fiber> get fibers => _percentages.keys;

  int get total => _percentages.values.fold(0, (sum, pct) => sum + pct);

  /// Whether the percentages total something a real label could show.
  ///
  /// A tolerance of 2 points absorbs rounding and minor OCR slips; anything
  /// further out suggests the scan was misread and should be re-checked.
  bool get isPlausible => !isEmpty && (total - 100).abs() <= 2;

  int percentOf(Fiber fiber) => _percentages[fiber] ?? 0;

  /// True when [fiber] is present at [minPercent] or more.
  bool contains(Fiber fiber, {int minPercent = 1}) =>
      percentOf(fiber) >= minPercent;

  /// True when [fiber] is present in an amount worth *describing* the garment
  /// by — the question a wardrobe search asks.
  ///
  /// Deliberately not [Fiber.escalationThreshold], which answers a different
  /// question: whether a fibre dictates the *care*. The two diverge in both
  /// directions. An 80/20 cotton-polyester tee is a polyester blend by any
  /// ordinary reading, but its 20% polyester changes nothing about the wash,
  /// so its care threshold is 50 and a search that reused it would not find
  /// the shirt. Conversely 3% elastane in a waistband rules out a hot dryer
  /// while nobody would call the garment elastane.
  ///
  /// Conflating them made "show me my polyester things" miss the obvious
  /// answers and varied the bar per fibre for reasons a searching user cannot
  /// see. This threshold is therefore flat, at the 5% that EU textile
  /// labelling (Regulation 1007/2011) uses to decide whether a fibre is named
  /// on the label at all — the same "what is this made of" judgement.
  bool isDescribedBy(Fiber fiber) => percentOf(fiber) >= notableFiberPercent;

  /// True when any fibre present at its escalation threshold has [test] set.
  ///
  /// The care rules ask questions like "does this contain enough of anything
  /// that felts?", and this expresses exactly that.
  bool hasDominantTrait(bool Function(Fiber fiber) test) =>
      _percentages.entries.any(
        (entry) =>
            test(entry.key) && entry.value >= entry.key.escalationThreshold,
      );

  /// The single fibre making up most of the garment, if any.
  Fiber? get dominantFiber {
    if (isEmpty) return null;
    var winner = _percentages.entries.first;
    for (final entry in _percentages.entries) {
      if (entry.value > winner.value) winner = entry;
    }
    return winner.key;
  }

  /// How robust the garment is overall.
  ///
  /// Takes the most fragile fibre present at or above its escalation
  /// threshold, because a blend is only as washable as its weakest component.
  /// Unknown composition is assumed [FabricClass.normal] rather than delicate:
  /// treating every unidentified item as hand-wash would make the app useless,
  /// and the care rules apply a conservative temperature separately.
  FabricClass get fabricClass {
    if (isEmpty) return FabricClass.normal;
    var result = FabricClass.heavy;
    for (final entry in _percentages.entries) {
      if (entry.value >= entry.key.escalationThreshold) {
        result = result.leastRobust(entry.key.naturalClass);
      }
    }
    // A blend of nothing-in-particular is ordinary, not heavy-duty.
    return result == FabricClass.heavy ? FabricClass.normal : result;
  }

  /// As it would be written on a label, strongest fibre first.
  String get label {
    if (isEmpty) return 'Unknown composition';
    final entries = _percentages.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => '${e.value}% ${e.key.label}').join(', ');
  }

  Map<String, Object?> toJson() => {
        for (final entry in _percentages.entries) entry.key.name: entry.value,
      };

  static FabricComposition fromJson(Map<String, Object?> json) =>
      FabricComposition({
        for (final entry in json.entries)
          Fiber.values.byName(entry.key): (entry.value! as num).toInt(),
      });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FabricComposition) return false;
    if (other._percentages.length != _percentages.length) return false;
    for (final entry in _percentages.entries) {
      if (other._percentages[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
        _percentages.entries.map((e) => Object.hash(e.key, e.value)),
      );

  @override
  String toString() => 'FabricComposition($label)';
}
