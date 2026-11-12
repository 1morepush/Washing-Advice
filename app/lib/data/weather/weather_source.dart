/// Where the weather comes from.
///
/// Open-Meteo, called straight from the app: free, no key, no account. Two
/// requests exist, a city search and a forecast, behind [WeatherSource] so the
/// screens and tests never see HTTP and the demo build can hand back a canned
/// forecast.
///
/// What leaves the phone: the text typed into the city search, and the
/// coordinates of the chosen place. Nothing about the wardrobe is ever sent.
///
/// Parsing is tolerant on purpose. A weather line is a nicety, and a provider
/// that renames a field or omits one must cost the person the line, not the
/// Outfits tab: every missing or oddly typed value is skipped, and a response
/// with no usable temperatures at all is [WeatherUnavailable].
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wardrobe_core/wardrobe_core.dart';

import 'weather_models.dart';

/// The weather could not be had. Never shown as an error screen.
class WeatherUnavailable implements Exception {
  const WeatherUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'WeatherUnavailable($reason)';
}

abstract interface class WeatherSource {
  /// Cities matching [query], best first. Empty for no match.
  Future<List<Place>> search(String query);

  /// The forecast for [place].
  Future<WeatherForecast> forecast(Place place);
}

class OpenMeteoWeatherSource implements WeatherSource {
  OpenMeteoWeatherSource({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _now;

  static const _timeout = Duration(seconds: 12);

  static final _geocoding = Uri.parse(
    'https://geocoding-api.open-meteo.com/v1/search',
  );
  static final _forecast = Uri.parse('https://api.open-meteo.com/v1/forecast');

  @override
  Future<List<Place>> search(String query) async {
    final text = query.trim();
    if (text.length < 2) return const [];
    final body = await _get(
      _geocoding.replace(queryParameters: {'name': text, 'count': '5'}),
    );
    return parsePlaces(body);
  }

  @override
  Future<WeatherForecast> forecast(Place place) async {
    final uri = _forecast.replace(
      queryParameters: {
        'latitude': '${place.latitude}',
        'longitude': '${place.longitude}',
        'daily': [
          'temperature_2m_max',
          'temperature_2m_min',
          'apparent_temperature_max',
          'apparent_temperature_min',
          'precipitation_probability_max',
          'precipitation_sum',
          'wind_speed_10m_max',
          'weather_code',
        ].join(','),
        'current': [
          'temperature_2m',
          'apparent_temperature',
          'precipitation',
          'weather_code',
        ].join(','),
        // Only used to say which part of the day the rain is expected in.
        'hourly': 'precipitation_probability',
        'timezone': 'auto',
        'forecast_days': '2',
      },
    );
    return parseForecast(await _get(uri), place: place, fetchedAt: _now());
  }

  Future<Object?> _get(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on Object catch (error) {
      // Offline, DNS, TLS, timeout: all the same to the person.
      throw WeatherUnavailable('request failed: ${error.runtimeType}');
    }
    if (response.statusCode != 200) {
      // Open-Meteo answers 400 or 429 with `{"error":true,"reason":...}`.
      throw WeatherUnavailable('status ${response.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const WeatherUnavailable('not JSON');
    }
  }

  /// Matches from a geocoding response, skipping any that are unusable.
  static List<Place> parsePlaces(Object? json) {
    final results = json is Map ? json['results'] : null;
    if (results is! List) return const [];
    final places = <Place>[];
    for (final r in results) {
      if (r is! Map) continue;
      final place = Place.tryFromJson({
        'name': r['name'],
        'latitude': r['latitude'],
        'longitude': r['longitude'],
        'region': r['admin1'],
        'country': r['country'],
      });
      if (place != null) places.add(place);
    }
    return places;
  }

  /// A forecast from a forecast response.
  ///
  /// Today is the first `daily` entry, tomorrow the second. Feels-like values
  /// fall back to air temperature when absent; rain, wind and sky are simply
  /// left unknown when absent.
  static WeatherForecast parseForecast(
    Object? json, {
    required Place place,
    required DateTime fetchedAt,
  }) {
    if (json is! Map || json['error'] == true) {
      throw const WeatherUnavailable('error response');
    }
    final daily = json['daily'];
    if (daily is! Map) throw const WeatherUnavailable('no daily data');

    double? at(String key, int day) {
      final series = daily[key];
      if (series is! List || series.length <= day) return null;
      final value = series[day];
      return value is num && value.isFinite ? value.toDouble() : null;
    }

    Weather? dayWeather(int day) {
      final low = at('apparent_temperature_min', day) ??
          at('temperature_2m_min', day);
      final high = at('apparent_temperature_max', day) ??
          at('temperature_2m_max', day);
      if (low == null || high == null) return null;
      final code = at('weather_code', day)?.round();
      return Weather(
        feelsLikeLowC: low <= high ? low : high,
        feelsLikeHighC: high >= low ? high : low,
        rainChancePercent: at('precipitation_probability_max', day),
        rainMm: at('precipitation_sum', day),
        windKph: at('wind_speed_10m_max', day),
        condition: WeatherCondition.fromWmoCode(code),
      );
    }

    final today = dayWeather(0);
    if (today == null) throw const WeatherUnavailable('no temperatures');

    final airLow = at('temperature_2m_min', 0) ?? today.feelsLikeLowC;
    final airHigh = at('temperature_2m_max', 0) ?? today.feelsLikeHighC;

    final current = json['current'];
    double? cur(String key) {
      final v = current is Map ? current[key] : null;
      return v is num && v.isFinite ? v.toDouble() : null;
    }

    return WeatherForecast(
      place: place,
      fetchedAt: fetchedAt,
      today: today,
      tomorrow: dayWeather(1),
      lowC: airLow <= airHigh ? airLow : airHigh,
      highC: airHigh >= airLow ? airHigh : airLow,
      currentC: cur('temperature_2m'),
      currentFeelsLikeC: cur('apparent_temperature'),
      rainPeak: _rainPeak(json['hourly'], today),
    );
  }

  /// The part of today in which the hourly rain chance peaks, if it is high
  /// enough to be worth naming (the same threshold as "rain possible").
  static DayPart? _rainPeak(Object? hourly, Weather today) {
    if (hourly is! Map) return null;
    final times = hourly['time'];
    final chances = hourly['precipitation_probability'];
    if (times is! List || chances is! List) return null;

    final dayKey = times.isEmpty ? null : '${times.first}'.split('T').first;
    var best = -1.0;
    DayPart? part;
    for (var i = 0; i < times.length && i < chances.length; i++) {
      final stamp = '${times[i]}';
      final chance = chances[i];
      if (dayKey == null || !stamp.startsWith(dayKey) || chance is! num) {
        continue;
      }
      final hour = int.tryParse(stamp.split('T').last.split(':').first);
      if (hour == null) continue;
      if (chance > best) {
        best = chance.toDouble();
        part = DayPart.ofHour(hour);
      }
    }
    return best >= DressingNeeds.rainPossiblePercent ? part : null;
  }
}
