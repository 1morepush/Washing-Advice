/// The five ISO 3758 care symbols, modelled as data.
///
/// Care labels are a closed, standardised vocabulary: a wash tub, a triangle, a
/// square, an iron and a circle. Storing them as structured values rather than
/// free text is what makes the rest of the system possible — you cannot sort a
/// pile of laundry by comparing the strings `"Cold"` and `"cold wash"`, but you
/// can compare `maxTempC: 30` against `maxTempC: 40`.
///
/// Every type here supports a *restrictive merge*: combining two requirements
/// yields the safer of the two. That single operation drives both care
/// resolution (when a label and a fibre rule disagree) and load building (where
/// a load must satisfy its most delicate member).
library;

/// How a garment may be washed. Ordered from most to least permissive.
enum WashMethod {
  machine('Machine wash'),
  hand('Hand wash'),
  doNotWash('Do not wash');

  const WashMethod(this.label);

  final String label;

  /// The stricter of two methods.
  WashMethod stricter(WashMethod other) => index >= other.index ? this : other;
}

/// Mechanical action, as shown by the bars beneath the wash tub.
///
/// No bar is a normal cycle, one bar is mild ("permanent press"), two bars is
/// very mild ("delicate").
enum Agitation {
  normal('Normal', barCount: 0),
  mild('Permanent press', barCount: 1),
  veryMild('Delicate', barCount: 2);

  const Agitation(this.label, {required this.barCount});

  final String label;

  /// Bars printed under the tub or circle on the label.
  final int barCount;

  /// The gentler of two settings.
  Agitation gentler(Agitation other) => index >= other.index ? this : other;
}

/// The word a label prints instead of a number.
///
/// American labels say "machine wash warm"; European ones print a number in
/// the tub. Both mean something, and only the number can drive a machine — but
/// showing a user "up to 40°C" when their label says "warm" makes the app look
/// like it read a different garment. So the word is carried alongside the
/// number rather than converted away.
///
/// The Celsius values are the conventional readings of each word, and they are
/// what the server is told to report in `maxTempC`. They live here so the
/// convention is stated once, in the core, rather than implied by a prompt.
enum WashTemperature {
  cold('Cold', 30),
  warm('Warm', 40),
  hot('Hot', 60);

  const WashTemperature(this.label, this.conventionalMaxC);

  final String label;

  /// What this word is normally taken to mean, in Celsius.
  final int conventionalMaxC;
}

/// The wash-tub symbol.
final class WashCare {
  const WashCare({
    required this.method,
    this.maxTempC,
    this.agitation = Agitation.normal,
    this.statedAs,
  });

  /// The safe assumption when nothing is known: a cool, gentle machine wash.
  ///
  /// Deliberately not "do not wash" — an app that refuses to wash anything it
  /// is unsure about is useless — but cool and mild enough to be survivable by
  /// almost anything.
  const WashCare.unknown()
      : method = WashMethod.machine,
        maxTempC = 30,
        agitation = Agitation.mild,
        statedAs = null;

  final WashMethod method;

  /// Maximum wash temperature in Celsius. Null means the label set no limit.
  final int? maxTempC;

  final Agitation agitation;

  /// The word the label printed, when it printed one rather than a number.
  ///
  /// Presentation only — [maxTempC] is what any machine decision reads. This
  /// exists so the app can repeat the manufacturer's own wording back to the
  /// user instead of silently replacing "warm" with a figure they never saw.
  final WashTemperature? statedAs;

  bool get isWashable => method != WashMethod.doNotWash;

  /// Combines two requirements into one that satisfies both.
  WashCare restrictiveMerge(WashCare other) => WashCare(
        method: method.stricter(other.method),
        maxTempC: switch ((maxTempC, other.maxTempC)) {
          (null, final b) => b,
          (final a, null) => a,
          (final a?, final b?) => a < b ? a : b,
        },
        agitation: agitation.gentler(other.agitation),
        // Kept only while it still describes the temperature in force. A
        // "warm" carried onto a load the rules have since capped at 30 would
        // be repeating a manufacturer's word about a wash that is no longer
        // the one being recommended.
        statedAs: switch ((maxTempC, other.maxTempC)) {
          (null, _) => other.statedAs,
          (_, null) => statedAs,
          (final a?, final b?) => a <= b ? statedAs : other.statedAs,
        },
      );

  WashCare copyWith({
    WashMethod? method,
    int? maxTempC,
    Agitation? agitation,
    WashTemperature? statedAs,
  }) =>
      WashCare(
        method: method ?? this.method,
        maxTempC: maxTempC ?? this.maxTempC,
        agitation: agitation ?? this.agitation,
        statedAs: statedAs ?? this.statedAs,
      );

  Map<String, Object?> toJson() => {
        'method': method.name,
        if (maxTempC != null) 'maxTempC': maxTempC,
        'agitation': agitation.name,
        if (statedAs != null) 'statedAs': statedAs!.name,
      };

  static WashCare fromJson(Map<String, Object?> json) => WashCare(
        method: WashMethod.values.byName(json['method']! as String),
        maxTempC: (json['maxTempC'] as num?)?.toInt(),
        agitation: json['agitation'] == null
            ? Agitation.normal
            : Agitation.values.byName(json['agitation']! as String),
        statedAs: json['statedAs'] == null
            ? null
            : WashTemperature.values.byName(json['statedAs']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WashCare &&
          other.method == method &&
          other.maxTempC == maxTempC &&
          other.agitation == agitation &&
          other.statedAs == statedAs;

  @override
  int get hashCode => Object.hash(method, maxTempC, agitation, statedAs);

  @override
  String toString() => 'WashCare(${method.name}, ${maxTempC ?? "any"}C, '
      '${agitation.name})';
}

/// The triangle symbol.
enum BleachAllowance {
  /// Empty triangle: any bleach.
  any('Any bleach allowed'),

  /// Triangle with two diagonal lines: oxygen bleach only.
  nonChlorineOnly('Non-chlorine bleach only'),

  /// Crossed triangle.
  none('Do not bleach');

  const BleachAllowance(this.label);

  final String label;

  BleachAllowance stricter(BleachAllowance other) =>
      index >= other.index ? this : other;
}

/// Tumble-dryer heat, as shown by dots inside the circle-in-a-square.
enum TumbleDryHeat {
  /// No dots with a filled circle, or an explicit air-dry setting.
  noHeat('No heat', dots: 0),

  /// One dot, up to about 60 degrees exhaust.
  low('Low heat', dots: 1),

  /// Two dots, up to about 80 degrees.
  medium('Medium heat', dots: 2),

  /// Three dots. Beyond ISO 3758 proper but common on North American labels.
  high('High heat', dots: 3);

  const TumbleDryHeat(this.label, {required this.dots});

  final String label;
  final int dots;

  /// The cooler of two settings.
  TumbleDryHeat cooler(TumbleDryHeat other) =>
      index <= other.index ? this : other;
}

/// The square-with-circle symbol, plus the natural-drying square symbols.
final class DryCare {
  const DryCare({
    required this.tumbleDryAllowed,
    this.tumbleDryHeat = TumbleDryHeat.low,
    this.naturalDry,
    this.dryInShade = false,
    this.doNotWring = false,
  });

  /// Conservative default: air-dry, since heat damage is irreversible and
  /// hanging something up never destroyed a garment.
  const DryCare.unknown()
      : tumbleDryAllowed = false,
        tumbleDryHeat = TumbleDryHeat.noHeat,
        naturalDry = NaturalDryMethod.lineDry,
        dryInShade = false,
        doNotWring = false;

  final bool tumbleDryAllowed;
  final TumbleDryHeat tumbleDryHeat;

  /// How to dry without a machine. Null when the label says nothing.
  final NaturalDryMethod? naturalDry;

  /// Dry away from direct sunlight, which fades and yellows.
  final bool dryInShade;

  /// Never twist to remove water — the fabric loses strength when wet.
  final bool doNotWring;

  DryCare restrictiveMerge(DryCare other) => DryCare(
        tumbleDryAllowed: tumbleDryAllowed && other.tumbleDryAllowed,
        tumbleDryHeat: tumbleDryHeat.cooler(other.tumbleDryHeat),
        // Prefer the more cautious instruction: flat beats drip beats line.
        naturalDry: switch ((naturalDry, other.naturalDry)) {
          (null, final b) => b,
          (final a, null) => a,
          (final a?, final b?) => a.index >= b.index ? a : b,
        },
        dryInShade: dryInShade || other.dryInShade,
        doNotWring: doNotWring || other.doNotWring,
      );

  Map<String, Object?> toJson() => {
        'tumbleDryAllowed': tumbleDryAllowed,
        'tumbleDryHeat': tumbleDryHeat.name,
        if (naturalDry != null) 'naturalDry': naturalDry!.name,
        'dryInShade': dryInShade,
        'doNotWring': doNotWring,
      };

  static DryCare fromJson(Map<String, Object?> json) => DryCare(
        tumbleDryAllowed: json['tumbleDryAllowed']! as bool,
        tumbleDryHeat: json['tumbleDryHeat'] == null
            ? TumbleDryHeat.low
            : TumbleDryHeat.values.byName(json['tumbleDryHeat']! as String),
        naturalDry: json['naturalDry'] == null
            ? null
            : NaturalDryMethod.values.byName(json['naturalDry']! as String),
        dryInShade: json['dryInShade'] as bool? ?? false,
        doNotWring: json['doNotWring'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DryCare &&
          other.tumbleDryAllowed == tumbleDryAllowed &&
          other.tumbleDryHeat == tumbleDryHeat &&
          other.naturalDry == naturalDry &&
          other.dryInShade == dryInShade &&
          other.doNotWring == doNotWring;

  @override
  int get hashCode => Object.hash(
        tumbleDryAllowed,
        tumbleDryHeat,
        naturalDry,
        dryInShade,
        doNotWring,
      );

  @override
  String toString() =>
      'DryCare(tumble=$tumbleDryAllowed/${tumbleDryHeat.name}, '
      'natural=${naturalDry?.name})';
}

/// Drying without a machine. Ordered by how much support the garment needs.
enum NaturalDryMethod {
  /// Hang on a line.
  lineDry('Line dry'),

  /// Hang soaking wet without spinning, so the weight pulls creases out.
  dripDry('Drip dry'),

  /// Lay flat, so the garment does not stretch under its own wet weight.
  flatDry('Dry flat');

  const NaturalDryMethod(this.label);

  final String label;
}

/// Iron temperature, as shown by dots inside the iron.
enum IronTemperature {
  none('Do not iron', dots: 0, maxPlateC: null),
  low('Low heat', dots: 1, maxPlateC: 110),
  medium('Medium heat', dots: 2, maxPlateC: 150),
  high('High heat', dots: 3, maxPlateC: 200);

  const IronTemperature(this.label,
      {required this.dots, required this.maxPlateC});

  final String label;
  final int dots;

  /// Maximum soleplate temperature in Celsius.
  final int? maxPlateC;

  IronTemperature cooler(IronTemperature other) =>
      index <= other.index ? this : other;
}

/// The iron symbol.
final class IronCare {
  const IronCare({required this.temperature, this.steamAllowed = true});

  const IronCare.unknown()
      : temperature = IronTemperature.low,
        steamAllowed = false;

  final IronTemperature temperature;
  final bool steamAllowed;

  bool get isIronable => temperature != IronTemperature.none;

  IronCare restrictiveMerge(IronCare other) => IronCare(
        temperature: temperature.cooler(other.temperature),
        steamAllowed: steamAllowed && other.steamAllowed,
      );

  Map<String, Object?> toJson() => {
        'temperature': temperature.name,
        'steamAllowed': steamAllowed,
      };

  static IronCare fromJson(Map<String, Object?> json) => IronCare(
        temperature:
            IronTemperature.values.byName(json['temperature']! as String),
        steamAllowed: json['steamAllowed'] as bool? ?? true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IronCare &&
          other.temperature == temperature &&
          other.steamAllowed == steamAllowed;

  @override
  int get hashCode => Object.hash(temperature, steamAllowed);

  @override
  String toString() => 'IronCare(${temperature.name}, steam=$steamAllowed)';
}

/// Professional cleaning solvent, from the letter inside the circle.
enum CleaningSolvent {
  /// P: tetrachloroethylene and hydrocarbons.
  perchloroethylene('P'),

  /// F: hydrocarbons only.
  hydrocarbon('F'),

  /// W: professional wet cleaning.
  wetClean('W');

  const CleaningSolvent(this.code);

  final String code;
}

/// The circle symbol.
final class ProfessionalCare {
  const ProfessionalCare({
    this.solvent,
    this.gentleCycle = false,
    this.doNotDryClean = false,
  });

  const ProfessionalCare.unspecified()
      : solvent = null,
        gentleCycle = false,
        doNotDryClean = false;

  const ProfessionalCare.forbidden()
      : solvent = null,
        gentleCycle = false,
        doNotDryClean = true;

  /// The permitted solvent, or null when the label says nothing.
  final CleaningSolvent? solvent;

  /// An underline on the circle: reduced moisture, heat and mechanical action.
  final bool gentleCycle;

  final bool doNotDryClean;

  /// True when professional cleaning is the only route — the label forbids
  /// domestic washing but names a solvent.
  bool get isAvailable => !doNotDryClean && solvent != null;

  ProfessionalCare restrictiveMerge(ProfessionalCare other) => ProfessionalCare(
        solvent: solvent ?? other.solvent,
        gentleCycle: gentleCycle || other.gentleCycle,
        doNotDryClean: doNotDryClean || other.doNotDryClean,
      );

  Map<String, Object?> toJson() => {
        if (solvent != null) 'solvent': solvent!.name,
        'gentleCycle': gentleCycle,
        'doNotDryClean': doNotDryClean,
      };

  static ProfessionalCare fromJson(Map<String, Object?> json) =>
      ProfessionalCare(
        solvent: json['solvent'] == null
            ? null
            : CleaningSolvent.values.byName(json['solvent']! as String),
        gentleCycle: json['gentleCycle'] as bool? ?? false,
        doNotDryClean: json['doNotDryClean'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfessionalCare &&
          other.solvent == solvent &&
          other.gentleCycle == gentleCycle &&
          other.doNotDryClean == doNotDryClean;

  @override
  int get hashCode => Object.hash(solvent, gentleCycle, doNotDryClean);

  @override
  String toString() => 'ProfessionalCare(${solvent?.code ?? "-"}, '
      'doNotDryClean=$doNotDryClean)';
}

/// Extra handling instructions that labels print as words rather than symbols.
///
/// Every member must exist under the same identifier in the server's
/// `CareWarning` and in `contracts/care_constraint.schema.json`: the wire
/// carries the identifier and `values.byName` matches on it, so a member that
/// differs by a letter is a decode failure rather than a mismatch anyone sees.
enum CareWarning {
  washInsideOut('Wash inside out'),
  washSeparately('Wash separately'),
  washWithLikeColours('Wash with like colors'),
  doNotSoak('Do not soak', isProhibition: true),
  useMeshBag('Use a mesh laundry bag'),
  closeFastenings('Close zips and fastenings'),
  removePromptly('Remove promptly to avoid creasing'),
  reshapeWhileDamp('Reshape while damp'),
  doNotUseSoftener('Do not use fabric softener', isProhibition: true),
  ironOnReverse('Iron on reverse'),

  /// The printed graphic must not be ironed, though the garment may be.
  ///
  /// Not [ironOnReverse], which says how to iron the whole garment, and not an
  /// absent iron temperature, which would forbid ironing the fabric too.
  doNotIronDecoration(
    'Do not iron the print or decoration',
    isProhibition: true,
  );

  const CareWarning(this.label, {this.isProhibition = false});

  final String label;

  /// Whether this forbids something, so the UI can mark it clearly.
  ///
  /// Declared per member rather than tested for by name at the call site. The
  /// renderer used to hard-code two of them, so a third prohibition added
  /// later rendered as a neutral suggestion — and "do not" advice that does
  /// not look like a prohibition is the kind that gets skimmed past.
  final bool isProhibition;
}
