/// A single thing the user owns.
///
/// Named [WardrobeItem] rather than "garment" on purpose: shoes, bags and bed
/// linen belong in a wardrobe app too, and they differ from a shirt only in
/// their [ItemType]. Nothing here is specific to clothing.
///
/// ## Which fields carry confidence
///
/// Attributes the *camera* produces — type, brand, composition, colour, pattern
/// — are wrapped in [Confident], because they are inferences that can be wrong
/// in ways that damage clothes. Attributes the *user* controls — name, size,
/// favourite, notes — are plain values, since there is no uncertainty to track.
/// Wrapping everything uniformly would add ceremony without adding information.
library;

import '../../care/model/care_instructions.dart';
import '../../care/model/care_symbols.dart';
import '../../care/rules/care_rule.dart';
import '../../shared/confidence.dart';
import '../../shared/ids.dart';
import 'condition.dart';
import 'fabric.dart';
import 'item_attributes.dart';
import 'item_color.dart';
import 'lifecycle.dart';
import 'ownership.dart';
import 'photo.dart';

/// One owned item, with everything known about it.
final class WardrobeItem {
  const WardrobeItem({
    required this.id,
    required this.name,
    required this.type,
    required this.composition,
    required this.colors,
    required this.care,
    required this.addedAt,
    required this.updatedAt,
    this.brand,
    this.pattern,
    this.careLabel,
    this.photos = PhotoSet.empty,
    this.lifecycle = LifecycleState.active,
    this.condition = ConditionAssessment.pristine,
    this.usage = const UsageStats.none(),
    this.purchase,
    this.sizeLabel,
    this.sleeveLength,
    this.fit,
    this.seasons = const {},
    this.styleCut,
    this.isFavorite = false,
    this.tags = const {},
    this.notes,
    this.distinguishingText,
  });

  final ItemId id;

  /// What the user calls it, e.g. `'Gray Nike hoodie'`.
  final String name;

  final Confident<ItemType> type;
  final Confident<FabricComposition> composition;
  final Confident<ColorPalette> colors;
  final Confident<String>? brand;
  final Confident<Pattern>? pattern;

  /// How to wash it, and how much that belief can be trusted.
  ///
  /// A *conclusion*. [careLabel] is the evidence behind it.
  final CareProfile care;

  /// What the garment's own care label said, as read from a scan.
  ///
  /// Kept beside the resolved [care] rather than folded into it, for the same
  /// reason the event log is kept beside the usage counters: the conclusion is
  /// derived and the evidence is not. Correcting the fabric later has to
  /// re-run the rule table, and without the label preserved here that
  /// re-resolution would silently discard the manufacturer's instruction and
  /// fall back to a generic rule — telling someone to hand-wash a superwash
  /// jumper their label says is machine washable.
  ///
  /// Partial by nature: a creased or faded label states only some fields, and
  /// an absent field means the rule table fills the gap.
  final Confident<CareConstraint>? careLabel;

  final PhotoSet photos;
  final LifecycleState lifecycle;
  final ConditionAssessment condition;

  /// Cached counters. The event log is the source of truth; see [UsageStats].
  final UsageStats usage;

  final PurchaseInfo? purchase;
  final String? sizeLabel;
  final SleeveLength? sleeveLength;
  final Fit? fit;
  final Set<Season> seasons;
  final StyleCut? styleCut;
  final bool isFavorite;

  /// Free-form user labels, for grouping the app does not anticipate.
  final Set<String> tags;

  final String? notes;

  /// Text visible on the garment — a slogan, a team name, a graphic caption.
  ///
  /// Captured during scanning and kept because it is unusually discriminating
  /// for re-identification: two black t-shirts are hard to tell apart until one
  /// of them says "Nirvana".
  final String? distinguishingText;

  final DateTime addedAt;
  final DateTime updatedAt;

  // --- Derived properties -------------------------------------------------

  ItemCategory get category => type.value.category;

  ItemKind get kind => type.value.kind;

  /// How robust the item is, combining what it is made of, how it is made, and
  /// the wear it has already taken.
  ///
  /// Fibre delicacy takes precedence: silk is fragile whatever it has been
  /// sewn into. Otherwise the garment's construction decides, which is what
  /// makes cotton denim heavy while a cotton t-shirt stays ordinary. Observed
  /// damage then drops it a further class, because a care label describes a new
  /// garment and a pilling sweater is more fragile than its fibre implies.
  FabricClass get fabricClass {
    final byFibre = composition.value.fabricClass;
    final base = byFibre == FabricClass.delicate
        ? FabricClass.delicate
        : type.value.construction;

    if (!condition.warrantsGentlerCare) return base;
    return switch (base) {
      FabricClass.heavy => FabricClass.normal,
      FabricClass.normal || FabricClass.delicate => FabricClass.delicate,
    };
  }

  ColorClass get colorClass => colors.value.colorClass;

  /// Whether this item's dye is likely to run onto others in the wash.
  ///
  /// New saturated items are the real hazard: dye loss falls off sharply after
  /// the first few washes, so an old red shirt is treated as safe while a brand
  /// new one is isolated.
  bool get isLikelyToBleed =>
      colors.value.isLikelyToBleed && usage.timesWashed < 3;

  /// Sheds fibres onto everything else in a shared load.
  ///
  /// Driven by construction rather than fibre — see the note on [Fiber].
  bool get producesLint => type.value.producesLint;

  /// Shows other fabrics' lint badly.
  bool get attractsLint =>
      type.value.attractsLint ||
      composition.value.hasDominantTrait((f) => f.attractsLint);

  /// Whether the laundry engine should consider this item at all.
  bool get isLaunderable =>
      type.value.isWashable &&
      lifecycle.isLaunderable &&
      care.instructions.wash.method != WashMethod.doNotWash;

  /// Effective drum space in grams-equivalent, for filling a machine.
  double get drumLoadGrams => type.value.drumLoadGrams;

  /// Care instructions adjusted for the item's actual condition.
  ///
  /// A care label describes a new garment. Once something is pilling or has a
  /// loose seam, the label's normal cycle will finish it off, so observed wear
  /// pulls the instructions gentler.
  CareInstructions get effectiveCare {
    if (!condition.warrantsGentlerCare) return care.instructions;
    return care.instructions.restrictiveMerge(
      CareInstructions(
        wash: WashCare(
          method: care.instructions.wash.method,
          maxTempC: 30,
          agitation: Agitation.veryMild,
        ),
        bleach: BleachAllowance.none,
        dry: const DryCare(
          tumbleDryAllowed: false,
          tumbleDryHeat: TumbleDryHeat.noHeat,
        ),
        iron: care.instructions.iron,
        professional: care.instructions.professional,
        warnings: const {CareWarning.washInsideOut},
      ),
    );
  }

  /// Whether the user should be prompted to scan the care label.
  bool get needsCareTagScan => care.shouldPromptForTagScan && isLaunderable;

  double? get costPerWear => usage.costPerWear(purchase);

  /// What the care rules are allowed to see.
  ///
  /// The rules take an [ItemFacts] rather than a whole item on purpose: the
  /// care context should not be able to reach into lifecycle, photos or
  /// purchase history, and keeping the input narrow is what makes a rule easy
  /// to reason about and to test.
  ///
  /// This getter is the single definition of that projection. Building the
  /// struct at each call site instead would let one caller quietly omit
  /// `timesWashed` and get different advice for the same garment.
  ///
  /// Confidence is dropped here, not lost: [factsConfidence] carries it, and a
  /// rule asking "is there enough wool in this?" cannot act on a maybe.
  ItemFacts get facts => ItemFacts(
        type: type.value,
        composition: composition.value,
        colors: colors.value,
        pattern: pattern?.value,
        conditionGrade: condition.grade,
        timesWashed: usage.timesWashed,
      );

  /// How much [facts] can be trusted, for attenuating anything derived from it.
  ///
  /// The weakest link, not an average: the rules reason from type *and*
  /// composition together, so a confident reading of one cannot compensate for
  /// a shaky reading of the other. Averaging would let "definitely a jumper,
  /// possibly wool" pass as reasonably certain, which is precisely the case
  /// where the advice needs a caveat.
  double get factsConfidence => type.confidence < composition.confidence
      ? type.confidence
      : composition.confidence;

  /// A display label such as `'Nike Hoodie'`.
  String get displayName => name.isNotEmpty
      ? name
      : [brand?.value, type.value.label].whereType<String>().join(' ');

  WardrobeItem copyWith({
    String? name,
    Confident<ItemType>? type,
    Confident<FabricComposition>? composition,
    Confident<ColorPalette>? colors,
    Confident<String>? brand,
    Confident<Pattern>? pattern,
    CareProfile? care,
    Confident<CareConstraint>? careLabel,
    PhotoSet? photos,
    LifecycleState? lifecycle,
    ConditionAssessment? condition,
    UsageStats? usage,
    PurchaseInfo? purchase,
    String? sizeLabel,
    SleeveLength? sleeveLength,
    Fit? fit,
    Set<Season>? seasons,
    StyleCut? styleCut,
    bool? isFavorite,
    Set<String>? tags,
    String? notes,
    String? distinguishingText,
    DateTime? updatedAt,
  }) =>
      WardrobeItem(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        composition: composition ?? this.composition,
        colors: colors ?? this.colors,
        brand: brand ?? this.brand,
        pattern: pattern ?? this.pattern,
        care: care ?? this.care,
        careLabel: careLabel ?? this.careLabel,
        photos: photos ?? this.photos,
        lifecycle: lifecycle ?? this.lifecycle,
        condition: condition ?? this.condition,
        usage: usage ?? this.usage,
        purchase: purchase ?? this.purchase,
        sizeLabel: sizeLabel ?? this.sizeLabel,
        sleeveLength: sleeveLength ?? this.sleeveLength,
        fit: fit ?? this.fit,
        seasons: seasons ?? this.seasons,
        styleCut: styleCut ?? this.styleCut,
        isFavorite: isFavorite ?? this.isFavorite,
        tags: tags ?? this.tags,
        notes: notes ?? this.notes,
        distinguishingText: distinguishingText ?? this.distinguishingText,
        addedAt: addedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Moves the item to a new lifecycle state, refusing impossible transitions.
  ///
  /// Returns null when the move makes no sense, so callers must decide what to
  /// do rather than silently corrupting history.
  WardrobeItem? transitionTo(LifecycleState next, {required DateTime at}) =>
      lifecycle.canTransitionTo(next)
          ? copyWith(lifecycle: next, updatedAt: at)
          : null;

  Map<String, Object?> toJson() => {
        'id': id.value,
        'name': name,
        'type': type.toJson((t) => t.name),
        'composition': composition.toJson((c) => c.toJson()),
        'colors': colors.toJson((c) => c.toJson()),
        if (brand != null) 'brand': brand!.toJson((b) => b),
        if (pattern != null) 'pattern': pattern!.toJson((p) => p.name),
        'care': care.toJson(),
        if (careLabel != null)
          'careLabel': careLabel!.toJson((c) => c.toJson()),
        'photos': photos.toJson(),
        'lifecycle': lifecycle.name,
        'condition': condition.toJson(),
        'usage': usage.toJson(),
        if (purchase != null) 'purchase': purchase!.toJson(),
        if (sizeLabel != null) 'sizeLabel': sizeLabel,
        if (sleeveLength != null) 'sleeveLength': sleeveLength!.name,
        if (fit != null) 'fit': fit!.name,
        'seasons': seasons.map((s) => s.name).toList(),
        if (styleCut != null) 'styleCut': styleCut!.name,
        'isFavorite': isFavorite,
        'tags': tags.toList(),
        if (notes != null) 'notes': notes,
        if (distinguishingText != null)
          'distinguishingText': distinguishingText,
        'addedAt': addedAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static WardrobeItem fromJson(Map<String, Object?> json) => WardrobeItem(
        id: ItemId(json['id']! as String),
        name: json['name']! as String,
        type: Confident.fromJson(
          json['type']! as Map<String, Object?>,
          (raw) => ItemType.values.byName(raw! as String),
        ),
        composition: Confident.fromJson(
          json['composition']! as Map<String, Object?>,
          (raw) => FabricComposition.fromJson(raw! as Map<String, Object?>),
        ),
        colors: Confident.fromJson(
          json['colors']! as Map<String, Object?>,
          (raw) => ColorPalette.fromJson(raw! as List<Object?>),
        ),
        brand: json['brand'] == null
            ? null
            : Confident.fromJson(
                json['brand']! as Map<String, Object?>,
                (raw) => raw! as String,
              ),
        pattern: json['pattern'] == null
            ? null
            : Confident.fromJson(
                json['pattern']! as Map<String, Object?>,
                (raw) => Pattern.values.byName(raw! as String),
              ),
        care: CareProfile.fromJson(json['care']! as Map<String, Object?>),
        careLabel: json['careLabel'] == null
            ? null
            : Confident.fromJson(
                json['careLabel']! as Map<String, Object?>,
                (raw) => CareConstraint.fromJson(raw! as Map<String, Object?>),
              ),
        photos: PhotoSet.fromJson(
          json['photos'] as List<Object?>? ?? const [],
        ),
        lifecycle: LifecycleState.values.byName(json['lifecycle']! as String),
        condition: ConditionAssessment.fromJson(
          json['condition'] as List<Object?>? ?? const [],
        ),
        usage: UsageStats.fromJson(
          json['usage'] as Map<String, Object?>? ?? const {},
        ),
        purchase: json['purchase'] == null
            ? null
            : PurchaseInfo.fromJson(json['purchase']! as Map<String, Object?>),
        sizeLabel: json['sizeLabel'] as String?,
        sleeveLength: json['sleeveLength'] == null
            ? null
            : SleeveLength.values.byName(json['sleeveLength']! as String),
        fit: json['fit'] == null
            ? null
            : Fit.values.byName(json['fit']! as String),
        seasons: {
          for (final raw in (json['seasons'] as List<Object?>? ?? const []))
            Season.values.byName(raw! as String),
        },
        styleCut: json['styleCut'] == null
            ? null
            : StyleCut.values.byName(json['styleCut']! as String),
        isFavorite: json['isFavorite'] as bool? ?? false,
        tags: {
          for (final raw in (json['tags'] as List<Object?>? ?? const []))
            raw! as String,
        },
        notes: json['notes'] as String?,
        distinguishingText: json['distinguishingText'] as String?,
        addedAt: DateTime.parse(json['addedAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WardrobeItem && other.id == id;

  /// Identity is the id alone. Two loaded copies of the same item are the same
  /// item regardless of which one has staler cached counters.
  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'WardrobeItem(${id.value}, $displayName)';
}
