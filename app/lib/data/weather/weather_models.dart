/// What the app knows about a place and its forecast.
///
/// Plain values, no I/O. The core owns the weather *rule* (`Weather` and
/// `DressingNeeds`); these are the app's wrapper around it: where the forecast
/// is for, when it was fetched, and the few extra facts the screen shows that
/// the rule does not need (the current temperature, which part of the day the
/// rain is expected in).
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// A city the person picked in Settings.
///
/// Stored as name plus coordinates and nothing else: the coordinates are what
/// the forecast needs and the name is what the person recognises. No device
/// location is ever read.
final class Place {
  const Place({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.region,
    this.country,
  });

  final String name;

  /// The state, county or province, when the geocoder gave one.
  final String? region;
  final String? country;
  final double latitude;
  final double longitude;

  /// "Portland, Oregon, United States": what a match is listed as, so two
  /// places with one name can be told apart.
  String get label {
    final area = region;
    return [
      name,
      if (area != null && area != name) area,
      if (country case final String c) c,
    ].join(', ');
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    if (region != null) 'region': region,
    if (country != null) 'country': country,
  };

  /// Null for anything that is not a usable place, rather than throwing: a
  /// stored value from another build must not break startup.
  static Place? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final lat = json['latitude'];
    final lon = json['longitude'];
    if (name is! String || name.isEmpty || lat is! num || lon is! num) {
      return null;
    }
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    return Place(
      name: name,
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      region: json['region'] is String ? json['region'] as String : null,
      country: json['country'] is String ? json['country'] as String : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Place &&
      other.name == name &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(name, latitude, longitude);
}

/// Part of the day, for "rain likely this afternoon".
enum DayPart {
  morning('this morning'),
  afternoon('this afternoon'),
  evening('this evening'),
  night('tonight');

  const DayPart(this.phrase);

  final String phrase;

  static DayPart ofHour(int hour) {
    if (hour < 6) return night;
    if (hour < 12) return morning;
    if (hour < 18) return afternoon;
    if (hour < 22) return evening;
    return night;
  }
}

/// A forecast for [place], as fetched at [fetchedAt].
final class WeatherForecast {
  const WeatherForecast({
    required this.place,
    required this.fetchedAt,
    required this.today,
    required this.lowC,
    required this.highC,
    this.tomorrow,
    this.currentC,
    this.currentFeelsLikeC,
    this.rainPeak,
  });

  final Place place;
  final DateTime fetchedAt;

  /// Today, in the shape the core reasons about (feels-like range, rain,
  /// wind, sky).
  final Weather today;
  final Weather? tomorrow;

  /// Air temperature range for today, which is what people read on a
  /// forecast; the feels-like range is inside [today].
  final double lowC;
  final double highC;

  final double? currentC;
  final double? currentFeelsLikeC;

  /// When today's rain chance peaks, if the hourly data said.
  final DayPart? rainPeak;

  Map<String, Object?> toJson() => {
    'place': place.toJson(),
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'today': _weatherToJson(today),
    if (tomorrow != null) 'tomorrow': _weatherToJson(tomorrow!),
    'lowC': lowC,
    'highC': highC,
    if (currentC != null) 'currentC': currentC,
    if (currentFeelsLikeC != null) 'currentFeelsLikeC': currentFeelsLikeC,
    if (rainPeak != null) 'rainPeak': rainPeak!.name,
  };

  /// Null when the stored value is unreadable; the cache is only ever a
  /// convenience.
  static WeatherForecast? tryFromJson(Object? json) {
    try {
      if (json is! Map) return null;
      final place = Place.tryFromJson(json['place']);
      final today = _weatherFromJson(json['today']);
      final fetched = DateTime.tryParse('${json['fetchedAt']}');
      final low = json['lowC'];
      final high = json['highC'];
      if (place == null ||
          today == null ||
          fetched == null ||
          low is! num ||
          high is! num) {
        return null;
      }
      return WeatherForecast(
        place: place,
        fetchedAt: fetched.toUtc(),
        today: today,
        tomorrow: _weatherFromJson(json['tomorrow']),
        lowC: low.toDouble(),
        highC: high.toDouble(),
        currentC: (json['currentC'] as num?)?.toDouble(),
        currentFeelsLikeC: (json['currentFeelsLikeC'] as num?)?.toDouble(),
        rainPeak: DayPart.values.asNameMap()[json['rainPeak']],
      );
    } on Object {
      return null;
    }
  }
}

Map<String, Object?> _weatherToJson(Weather w) => {
  'low': w.feelsLikeLowC,
  'high': w.feelsLikeHighC,
  if (w.rainChancePercent != null) 'rainChance': w.rainChancePercent,
  if (w.rainMm != null) 'rainMm': w.rainMm,
  if (w.windKph != null) 'windKph': w.windKph,
  'condition': w.condition.name,
};

Weather? _weatherFromJson(Object? json) {
  if (json is! Map) return null;
  final low = json['low'];
  final high = json['high'];
  if (low is! num || high is! num) return null;
  return Weather(
    feelsLikeLowC: low.toDouble(),
    feelsLikeHighC: high.toDouble(),
    rainChancePercent: (json['rainChance'] as num?)?.toDouble(),
    rainMm: (json['rainMm'] as num?)?.toDouble(),
    windKph: (json['windKph'] as num?)?.toDouble(),
    condition:
        WeatherCondition.values.asNameMap()[json['condition']] ??
        WeatherCondition.unknown,
  );
}

/// How temperatures are shown. The rule always works in Celsius.
enum WeatherUnit {
  celsius('Celsius', '°C'),
  fahrenheit('Fahrenheit', '°F');

  const WeatherUnit(this.label, this.symbol);

  final String label;
  final String symbol;

  double fromCelsius(double c) => this == celsius ? c : c * 9 / 5 + 32;

  /// A whole number with a bare degree sign, e.g. `9°` or `48°`.
  String degrees(double celsius) => '${fromCelsius(celsius).round()}°';

  /// A range, e.g. `9–14°`. A single value when both round to the same.
  String range(double lowC, double highC) {
    final low = fromCelsius(lowC).round();
    final high = fromCelsius(highC).round();
    return low == high ? '$low°' : '$low–$high°';
  }

  /// The unit people in [countryCode] expect: Fahrenheit in the handful of
  /// places that use it, Celsius everywhere else and when the locale does not
  /// say.
  static WeatherUnit forCountry(String? countryCode) =>
      switch (countryCode?.toUpperCase()) {
        'US' || 'LR' || 'MM' || 'BS' || 'BZ' || 'KY' || 'PW' => fahrenheit,
        _ => celsius,
      };
}
