/// Colour, held perceptually rather than as RGB.
///
/// Two jobs depend on getting colour right: splitting a pile into whites,
/// lights, darks and brights, and recognising a garment we have already seen.
/// RGB distance is a poor proxy for "do these look the same" — it rates dark
/// navy and dark brown as far apart while calling two obviously different
/// pastels close. Everything here therefore works in CIELAB with the CIEDE2000
/// difference metric, which is built to track human perception.
library;

import 'dart:math' as math;

/// The laundry-relevant colour families.
enum ColorClass {
  /// Bright white and off-white. Ruined by a single stray dark sock.
  whites(label: 'Whites'),

  /// Pastels, beige, light grey. Tolerant of each other, not of dye bleed.
  lights(label: 'Lights'),

  /// Saturated reds, blues, oranges. The category that bleeds.
  brights(label: 'Brights'),

  /// Navy, charcoal, black, dark brown.
  darks(label: 'Darks');

  const ColorClass({required this.label});

  /// What to call this pile when telling someone which load it goes in.
  final String label;
}

/// A colour in CIELAB (D65), with the share of the garment it covers.
final class ItemColor {
  const ItemColor({
    required this.lightness,
    required this.a,
    required this.b,
    this.coverage = 1.0,
    this.name,
  });

  /// Builds a colour from 8-bit sRGB, converting through linear RGB and XYZ.
  factory ItemColor.fromRgb(
    int red,
    int green,
    int blue, {
    double coverage = 1.0,
    String? name,
  }) {
    double toLinear(int channel) {
      final v = channel / 255.0;
      return v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = toLinear(red);
    final g = toLinear(green);
    final bl = toLinear(blue);

    // sRGB D65 primaries.
    final x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * bl;
    final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * bl;
    final z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * bl;

    // D65 reference white.
    const xn = 0.95047, yn = 1.0, zn = 1.08883;
    const delta = 6.0 / 29.0;

    double f(double t) => t > delta * delta * delta
        ? math.pow(t, 1.0 / 3.0).toDouble()
        : t / (3 * delta * delta) + 4.0 / 29.0;

    final fx = f(x / xn), fy = f(y / yn), fz = f(z / zn);

    return ItemColor(
      lightness: 116 * fy - 16,
      a: 500 * (fx - fy),
      b: 200 * (fy - fz),
      coverage: coverage,
      name: name,
    );
  }

  /// Parses `#RRGGBB` or `RRGGBB`.
  factory ItemColor.fromHex(
    String hex, {
    double coverage = 1.0,
    String? name,
  }) {
    final cleaned = hex.replaceFirst('#', '').trim();
    if (cleaned.length != 6) {
      throw FormatException('Expected a 6-digit hex color, got "$hex"');
    }
    final value = int.parse(cleaned, radix: 16);
    return ItemColor.fromRgb(
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
      coverage: coverage,
      name: name,
    );
  }

  /// CIE L*, `0` (black) to `100` (white).
  final double lightness;

  /// CIE a*, green (negative) to red (positive).
  final double a;

  /// CIE b*, blue (negative) to yellow (positive).
  final double b;

  /// Share of the garment showing this colour, `0..1`.
  final double coverage;

  /// Optional human label, e.g. `'Navy'`, for display and search.
  final String? name;

  /// Distance from the neutral axis. High chroma means a saturated colour, and
  /// saturated usually means dye that can bleed.
  double get chroma => math.sqrt(a * a + b * b);

  /// Hue angle in degrees, `0..360`, measured anticlockwise from the red-green
  /// axis. This is CIE h°, the same quantity a colour wheel shows.
  ///
  /// Only meaningful when [chroma] is appreciable: near the neutral axis the
  /// angle is numerically defined but perceptually arbitrary, since a grey has
  /// no hue to speak of. Callers that compare hues must check chroma first.
  double get hue {
    final degrees = math.atan2(b, a) * 180 / math.pi;
    return degrees < 0 ? degrees + 360 : degrees;
  }

  /// Whether the colour reads as a neutral — black, white, grey, beige, navy.
  ///
  /// The threshold is generous on purpose, and navy is why. A typical navy
  /// measures a chroma of about 18, which is enough to be a colour by the
  /// numbers and nowhere near enough to behave like one: navy goes with
  /// everything, which is the entire reason wardrobes are full of it. A cream
  /// with a warm cast is the same story at the other end of the lightness
  /// scale. So the line is drawn above both.
  ///
  /// This is a *styling* judgement and is deliberately looser than the
  /// bleed-risk and pile thresholds above, which answer a different question:
  /// navy is emphatically not neutral in a wash with whites.
  bool get isNeutral => chroma < 22;

  /// Which laundry pile this colour belongs in.
  ///
  /// Checked in order of consequence: a stray dark item ruins a white load, so
  /// whites are identified strictly, and anything mid-toned and unsaturated
  /// falls to [ColorClass.darks] because that is the harmless mistake.
  ColorClass get colorClass {
    if (lightness >= 85 && chroma <= 12) return ColorClass.whites;
    if (lightness <= 35) return ColorClass.darks;
    if (chroma >= 40) return ColorClass.brights;
    if (lightness >= 60) return ColorClass.lights;
    return ColorClass.darks;
  }

  /// Whether this colour is saturated enough that its dye is likely to run.
  bool get isLikelyToBleed => chroma >= 45 && lightness <= 70;

  /// Back to 8-bit sRGB, as `0xRRGGBB`.
  ///
  /// The exact inverse of [ItemColor.fromRgb]. It lives here rather than in the
  /// app because the core owns the colour space: a widget that reimplemented
  /// CIELAB inversion would be a second, quietly diverging opinion about what a
  /// stored colour looks like.
  ///
  /// Lab covers colours sRGB cannot show, so the channels are clamped. That is
  /// a real conversion loss and not an error — the alternative is a garment
  /// swatch with a negative amount of green in it.
  int get rgb {
    const xn = 0.95047, yn = 1.0, zn = 1.08883;
    const delta = 6.0 / 29.0;

    final fy = (lightness + 16) / 116;
    final fx = fy + a / 500;
    final fz = fy - b / 200;

    double invert(double t) =>
        t > delta ? t * t * t : 3 * delta * delta * (t - 4.0 / 29.0);

    final x = xn * invert(fx), y = yn * invert(fy), z = zn * invert(fz);

    // Inverse of the sRGB D65 primaries used in `fromRgb`.
    final r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    final g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    final bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

    int channel(double linear) {
      final companded = linear <= 0.0031308
          ? 12.92 * linear
          : 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;
      return (companded.clamp(0.0, 1.0) * 255).round();
    }

    return (channel(r) << 16) | (channel(g) << 8) | channel(bl);
  }

  /// As `#RRGGBB`, for display and for anything that speaks CSS.
  String get hex => '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Perceptual difference between two colours, per CIEDE2000.
  ///
  /// Roughly: below 1 is imperceptible, below about 5 reads as "the same
  /// colour", and above 10 is plainly different.
  static double difference(ItemColor x, ItemColor y) {
    const kL = 1.0, kC = 1.0, kH = 1.0;
    const pow25To7 = 6103515625.0; // 25^7

    double radians(double degrees) => degrees * math.pi / 180.0;
    double degrees(double rad) => rad * 180.0 / math.pi;

    final c1 = math.sqrt(x.a * x.a + x.b * x.b);
    final c2 = math.sqrt(y.a * y.a + y.b * y.b);
    final cBar = (c1 + c2) / 2.0;
    final cBar7 = math.pow(cBar, 7).toDouble();

    final g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + pow25To7)));
    final a1p = (1 + g) * x.a;
    final a2p = (1 + g) * y.a;

    final c1p = math.sqrt(a1p * a1p + x.b * x.b);
    final c2p = math.sqrt(a2p * a2p + y.b * y.b);

    double hueOf(double bChannel, double aPrime) {
      if (aPrime == 0 && bChannel == 0) return 0;
      final h = degrees(math.atan2(bChannel, aPrime));
      return h >= 0 ? h : h + 360;
    }

    final h1p = hueOf(x.b, a1p);
    final h2p = hueOf(y.b, a2p);

    final deltaLp = y.lightness - x.lightness;
    final deltaCp = c2p - c1p;

    final double deltahp;
    if (c1p * c2p == 0) {
      deltahp = 0;
    } else if ((h2p - h1p).abs() <= 180) {
      deltahp = h2p - h1p;
    } else if (h2p - h1p > 180) {
      deltahp = h2p - h1p - 360;
    } else {
      deltahp = h2p - h1p + 360;
    }

    final deltaHp = 2 * math.sqrt(c1p * c2p) * math.sin(radians(deltahp / 2));

    final lBarP = (x.lightness + y.lightness) / 2;
    final cBarP = (c1p + c2p) / 2;

    final double hBarP;
    if (c1p * c2p == 0) {
      hBarP = h1p + h2p;
    } else if ((h1p - h2p).abs() <= 180) {
      hBarP = (h1p + h2p) / 2;
    } else if (h1p + h2p < 360) {
      hBarP = (h1p + h2p + 360) / 2;
    } else {
      hBarP = (h1p + h2p - 360) / 2;
    }

    final t = 1 -
        0.17 * math.cos(radians(hBarP - 30)) +
        0.24 * math.cos(radians(2 * hBarP)) +
        0.32 * math.cos(radians(3 * hBarP + 6)) -
        0.20 * math.cos(radians(4 * hBarP - 63));

    final deltaTheta = 30 * math.exp(-math.pow((hBarP - 275) / 25, 2));
    final cBarP7 = math.pow(cBarP, 7).toDouble();
    final rc = 2 * math.sqrt(cBarP7 / (cBarP7 + pow25To7));

    final lBarMinus50Sq = (lBarP - 50) * (lBarP - 50);
    final sl = 1 + (0.015 * lBarMinus50Sq) / math.sqrt(20 + lBarMinus50Sq);
    final sc = 1 + 0.045 * cBarP;
    final sh = 1 + 0.015 * cBarP * t;
    final rt = -math.sin(radians(2 * deltaTheta)) * rc;

    final lTerm = deltaLp / (kL * sl);
    final cTerm = deltaCp / (kC * sc);
    final hTerm = deltaHp / (kH * sh);

    return math.sqrt(
      lTerm * lTerm + cTerm * cTerm + hTerm * hTerm + rt * cTerm * hTerm,
    );
  }

  ItemColor copyWith({double? coverage, String? name}) => ItemColor(
        lightness: lightness,
        a: a,
        b: b,
        coverage: coverage ?? this.coverage,
        name: name ?? this.name,
      );

  Map<String, Object?> toJson() => {
        'l': lightness,
        'a': a,
        'b': b,
        'coverage': coverage,
        if (name != null) 'name': name,
      };

  static ItemColor fromJson(Map<String, Object?> json) => ItemColor(
        lightness: (json['l']! as num).toDouble(),
        a: (json['a']! as num).toDouble(),
        b: (json['b']! as num).toDouble(),
        coverage: (json['coverage'] as num?)?.toDouble() ?? 1.0,
        name: json['name'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemColor &&
          other.lightness == lightness &&
          other.a == a &&
          other.b == b &&
          other.coverage == coverage &&
          other.name == name;

  @override
  int get hashCode => Object.hash(lightness, a, b, coverage, name);

  @override
  String toString() => name != null
      ? 'ItemColor($name, L=${lightness.toStringAsFixed(1)})'
      : 'ItemColor(L=${lightness.toStringAsFixed(1)}, '
          'a=${a.toStringAsFixed(1)}, b=${b.toStringAsFixed(1)})';
}

/// The set of colours on one garment, ordered by how much of it they cover.
final class ColorPalette {
  ColorPalette(List<ItemColor> colors)
      : _colors = List.unmodifiable(
          // Explicitly typed: see the note in ConditionAssessment — the literal
          // would otherwise infer as `List<dynamic>` from the parameter type.
          <ItemColor>[...colors]
            ..sort((x, y) => y.coverage.compareTo(x.coverage)),
        );

  ColorPalette.single(ItemColor color) : this([color]);

  ColorPalette.empty() : this(const []);

  /// A palette whose order was *stated* rather than measured.
  ///
  /// A camera reports the coverage it actually saw. A person naming colours by
  /// hand is saying "mostly this, and some of that" and has no percentage in
  /// mind, so coverage is derived from the order they gave: descending, and
  /// summing to one.
  ///
  /// Derived rather than split equally, for a reason that would otherwise be a
  /// very quiet bug: [ColorPalette] sorts by coverage, and Dart's sort is not
  /// stable. Equal coverages would leave which colour counts as [dominant] up
  /// to the sort's internals — and dominance decides the laundry pile.
  factory ColorPalette.ordered(List<ItemColor> colors) {
    final count = colors.length;
    // 1 + 2 + ... + count, so the weights below sum to exactly one.
    final total = count * (count + 1) / 2;
    return ColorPalette([
      for (final (index, color) in colors.indexed)
        color.copyWith(coverage: (count - index) / total),
    ]);
  }

  final List<ItemColor> _colors;

  List<ItemColor> get colors => _colors;

  bool get isEmpty => _colors.isEmpty;

  /// The colour covering most of the garment.
  ItemColor? get dominant => _colors.isEmpty ? null : _colors.first;

  /// Which pile the garment as a whole belongs in.
  ///
  /// Not simply the dominant colour's class: a mostly-white tee with a large
  /// navy print cannot go in a whites load. Any sufficiently visible dark or
  /// bright element pulls the whole garment out of [ColorClass.whites].
  ColorClass get colorClass {
    if (_colors.isEmpty) return ColorClass.darks;
    final dominantClass = _colors.first.colorClass;
    if (dominantClass != ColorClass.whites) return dominantClass;

    for (final color in _colors.skip(1)) {
      final isVisible = color.coverage >= 0.12;
      final isRisky = color.colorClass == ColorClass.darks ||
          color.colorClass == ColorClass.brights;
      if (isVisible && isRisky) return ColorClass.lights;
    }
    return ColorClass.whites;
  }

  /// Whether any colour present is saturated enough to run in the wash.
  bool get isLikelyToBleed => _colors.any((c) => c.isLikelyToBleed);

  List<Object?> toJson() => _colors.map((c) => c.toJson()).toList();

  static ColorPalette fromJson(List<Object?> json) => ColorPalette([
        for (final entry in json)
          ItemColor.fromJson(entry! as Map<String, Object?>),
      ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorPalette &&
          other._colors.length == _colors.length &&
          List.generate(_colors.length, (i) => _colors[i] == other._colors[i])
              .every((equal) => equal);

  @override
  int get hashCode => Object.hashAll(_colors);

  @override
  String toString() => 'ColorPalette(${_colors.join(', ')})';
}
