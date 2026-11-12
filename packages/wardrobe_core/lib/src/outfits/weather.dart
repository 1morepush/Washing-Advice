/// Turning a forecast into what a person needs to put on.
///
/// This file is deliberately the *whole* of the weather reasoning and
/// deliberately small. A forecast is a handful of numbers; the decisions people
/// actually make from it are "is it cold, is it wet, is it windy". Each of
/// those is a visible threshold below, so a suggestion can say why it was made
/// and a reader can disagree with a number rather than with a black box.
///
/// It knows nothing about where the numbers came from (the app fetches them),
/// nothing about units (Celsius throughout; the screen converts for display)
/// and nothing about the wardrobe (`weather_fit.dart` does that).
library;

/// The sky, reduced to what changes how a person dresses.
enum WeatherCondition {
  clear('Clear'),
  partlyCloudy('Partly cloudy'),
  cloudy('Cloudy'),
  fog('Fog'),
  drizzle('Drizzle'),
  rain('Rain'),
  snow('Snow'),
  thunderstorm('Thunderstorms'),
  unknown('Unknown');

  const WeatherCondition(this.label);

  final String label;

  /// Whether the sky itself is wet, whatever the probabilities say.
  bool get isWet => switch (this) {
        drizzle || rain || snow || thunderstorm => true,
        _ => false,
      };

  /// From a WMO weather interpretation code, the scheme Open-Meteo reports.
  ///
  /// Unrecognised codes are [unknown] rather than an error: a source that
  /// adds a code tomorrow must not break outfit suggestions today.
  static WeatherCondition fromWmoCode(int? code) => switch (code) {
        0 => clear,
        1 || 2 => partlyCloudy,
        3 => cloudy,
        45 || 48 => fog,
        51 || 53 || 55 || 56 || 57 => drizzle,
        61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => rain,
        71 || 73 || 75 || 77 || 85 || 86 => snow,
        95 || 96 || 99 => thunderstorm,
        _ => unknown,
      };
}

/// A day's weather, in Celsius, km/h and millimetres.
final class Weather {
  const Weather({
    required this.feelsLikeLowC,
    required this.feelsLikeHighC,
    this.rainChancePercent,
    this.rainMm,
    this.windKph,
    this.condition = WeatherCondition.unknown,
  });

  /// "Feels like" rather than air temperature, because wind and damp are what
  /// make a 5° day need a coat or not, and the source already accounts for
  /// them.
  final double feelsLikeLowC;
  final double feelsLikeHighC;

  /// `0..100`, or null when the source did not say.
  final double? rainChancePercent;
  final double? rainMm;
  final double? windKph;
  final WeatherCondition condition;

  Weather copyWith({
    double? feelsLikeLowC,
    double? feelsLikeHighC,
    double? rainChancePercent,
    double? rainMm,
    double? windKph,
    WeatherCondition? condition,
  }) =>
      Weather(
        feelsLikeLowC: feelsLikeLowC ?? this.feelsLikeLowC,
        feelsLikeHighC: feelsLikeHighC ?? this.feelsLikeHighC,
        rainChancePercent: rainChancePercent ?? this.rainChancePercent,
        rainMm: rainMm ?? this.rainMm,
        windKph: windKph ?? this.windKph,
        condition: condition ?? this.condition,
      );

  @override
  String toString() =>
      'Weather(${feelsLikeLowC.round()}..${feelsLikeHighC.round()} C feels, '
      'rain $rainChancePercent% / $rainMm mm, wind $windKph, '
      '${condition.name})';
}

/// How warm it feels, coldest first.
enum WarmthBand {
  freezing('freezing'),
  cold('cold'),
  cool('cool'),
  mild('mild'),
  warm('warm'),
  hot('hot');

  const WarmthBand(this.label);

  final String label;

  /// Upper edges in feels-like Celsius: a temperature below the edge is in that
  /// band, at or above it is in the next.
  ///
  /// | feels like | band |
  /// |---|---|
  /// | below 0 | freezing |
  /// | 0 to under 8 | cold |
  /// | 8 to under 15 | cool |
  /// | 15 to under 21 | mild |
  /// | 21 to under 27 | warm |
  /// | 27 and over | hot |
  ///
  /// Chosen as the points where the answer to "what do I wear" changes for a
  /// typical person: 0 is where wet becomes ice, 8 is where a jumper stops
  /// being enough without a layer, 15 and 21 bracket "a long sleeve is fine"
  /// to "short sleeves", and 27 is where heavy fabric becomes unpleasant.
  static const double freezingBelow = 0;
  static const double coldBelow = 8;
  static const double coolBelow = 15;
  static const double mildBelow = 21;
  static const double warmBelow = 27;

  static WarmthBand ofFeelsLike(double celsius) {
    if (celsius < freezingBelow) return freezing;
    if (celsius < coldBelow) return cold;
    if (celsius < coolBelow) return cool;
    if (celsius < mildBelow) return mild;
    if (celsius < warmBelow) return warm;
    return hot;
  }

  /// Whether this band is [other] or colder.
  bool isAtMost(WarmthBand other) => index <= other.index;
}

/// What the day asks of an outfit.
final class DressingNeeds {
  const DressingNeeds({
    required this.band,
    required this.rainLikely,
    required this.rainPossible,
    required this.snow,
    required this.windy,
    required this.outerLayer,
    required this.coldMorning,
  });

  /// Rain chance at or above this is "likely"; the umbrella-and-waterproof
  /// threshold.
  static const double rainLikelyPercent = 50;

  /// Rain chance at or above this (below likely) is "possible": worth a note,
  /// not worth reshuffling the wardrobe.
  static const double rainPossiblePercent = 30;

  /// Daily rain at or above this many millimetres counts as likely however the
  /// probability is phrased.
  static const double rainLikelyMm = 1;

  /// Wind at or above this (km/h) is noticeable on a bike or an open street.
  static const double windyKph = 30;

  /// A feels-like low this much or more below the day's dressing temperature
  /// makes a layer worthwhile even on a mild day: it is cold when you set off
  /// or come home.
  static const double coldMorningBelowC = 10;

  /// The band the outfit is chosen for.
  ///
  /// Computed from the *day*, not just its peak: see [of].
  final WarmthBand band;

  final bool rainLikely;
  final bool rainPossible;
  final bool snow;
  final bool windy;

  /// Whether a jacket or coat is part of the answer.
  final bool outerLayer;

  /// A mild or warmer day that starts or ends cold.
  final bool coldMorning;

  /// Whether the outfit has to cope with wet: likely rain or snow.
  bool get wet => rainLikely || snow;

  bool get isHot => band == WarmthBand.hot || band == WarmthBand.warm;
  bool get isCold => band.isAtMost(WarmthBand.cold);

  /// The decision, from a forecast.
  ///
  /// The band uses a daytime-weighted temperature, `0.4 * low + 0.6 * high`,
  /// because people are out and dressed for the warm half of the day more than
  /// the cold half; the low is then handled separately as [coldMorning] so a
  /// 4°-to-18° day still gets a layer rather than being averaged into "mild
  /// and fine".
  ///
  /// A layer is wanted when the band is cool or colder, when rain is likely or
  /// it is snowing, when it is windy and not warm, or on a cold morning.
  factory DressingNeeds.of(Weather weather) {
    final dressing = weather.feelsLikeLowC * 0.4 + weather.feelsLikeHighC * 0.6;
    final band = WarmthBand.ofFeelsLike(dressing);

    final chance = weather.rainChancePercent ?? 0;
    final mm = weather.rainMm ?? 0;
    final snow = weather.condition == WeatherCondition.snow;
    final rainLikely = chance >= rainLikelyPercent ||
        mm >= rainLikelyMm ||
        (weather.condition.isWet && !snow && weather.rainChancePercent == null);
    final rainPossible = !rainLikely && chance >= rainPossiblePercent;
    final windy = (weather.windKph ?? 0) >= windyKph;
    final coldMorning = weather.feelsLikeLowC < coldMorningBelowC &&
        band.index >= WarmthBand.mild.index;

    final layer = band.isAtMost(WarmthBand.cool) ||
        rainLikely ||
        snow ||
        (windy && band.isAtMost(WarmthBand.mild)) ||
        coldMorning;

    return DressingNeeds(
      band: band,
      rainLikely: rainLikely,
      rainPossible: rainPossible,
      snow: snow,
      windy: windy,
      outerLayer: layer,
      coldMorning: coldMorning,
    );
  }

  /// A short phrase for the day, e.g. "Cold and rainy", "Hot", "Mild and
  /// windy". Used as the lead of a weather reason.
  String get headline {
    final parts = <String>[
      band.label,
      if (snow)
        'snowy'
      else if (rainLikely)
        'rainy'
      else if (rainPossible)
        'a chance of rain',
      if (windy) 'windy',
    ];
    final text = parts.length == 1
        ? parts.single
        : '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
    return text[0].toUpperCase() + text.substring(1);
  }

  @override
  String toString() => 'DressingNeeds($headline, layer: $outerLayer)';
}
