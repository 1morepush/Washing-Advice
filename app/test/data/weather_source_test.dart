/// The Open-Meteo client, against recorded response samples.
///
/// No test here touches the network: the HTTP client is a `MockClient`, and the
/// samples are in `test/fixtures/weather`. The geocoding sample and the
/// rate-limit error are real responses; the London forecast follows the
/// documented response shape (the live forecast endpoint was rate-limited when
/// the samples were taken).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/weather/fake_weather_source.dart';
import 'package:washing_advice/data/weather/weather_models.dart';
import 'package:washing_advice/data/weather/weather_source.dart';
import 'package:washing_advice/features/outfits/weather_strip.dart';

String fixture(String name) =>
    File('test/fixtures/weather/$name').readAsStringSync();

/// A 200 carrying a sample, as UTF-8 bytes the way the real service sends it
/// (the samples contain a degree sign).
http.Response ok(String name) =>
    http.Response.bytes(utf8.encode(fixture(name)), 200);

void main() {
  final at = DateTime.utc(2026, 11, 12, 9);

  OpenMeteoWeatherSource sourceReplying(
    http.Response Function(http.Request) handler, {
    List<Uri>? seen,
  }) => OpenMeteoWeatherSource(
    client: MockClient((request) async {
      seen?.add(request.url);
      return handler(request);
    }),
    now: () => at,
  );

  group('city search', () {
    test(
      'asks the geocoder for five matches and parses name, region, country',
      () async {
        final seen = <Uri>[];
        final source = sourceReplying(
          (_) => ok('geocoding_london.json'),
          seen: seen,
        );

        final places = await source.search('  London ');

        expect(seen.single.host, 'geocoding-api.open-meteo.com');
        expect(seen.single.path, '/v1/search');
        expect(seen.single.queryParameters, {'name': 'London', 'count': '5'});
        expect(places, hasLength(2));
        expect(places.first.name, 'London');
        expect(places.first.region, 'England');
        expect(places.first.country, 'United Kingdom');
        expect(places.first.latitude, closeTo(51.50853, 1e-6));
        expect(places.first.label, 'London, England, United Kingdom');
        expect(places.last.label, 'London, Ontario, Canada');
      },
    );

    test('no results is an empty list, not an error', () async {
      final source = sourceReplying((_) => ok('geocoding_empty.json'));
      expect(await source.search('Xyzzyville'), isEmpty);
    });

    test('a query too short to mean anything makes no request', () async {
      final seen = <Uri>[];
      final source = sourceReplying(
        (_) => http.Response('{}', 200),
        seen: seen,
      );
      expect(await source.search(' a '), isEmpty);
      expect(seen, isEmpty);
    });

    test('unusable matches are skipped', () {
      final places = OpenMeteoWeatherSource.parsePlaces({
        'results': [
          {'name': 'Nowhere'},
          {'name': 'Bad', 'latitude': 999, 'longitude': 0},
          'junk',
          {'name': 'Fine', 'latitude': 1.5, 'longitude': 2.5},
        ],
      });
      expect(places.map((p) => p.name), ['Fine']);
    });

    test('failures surface as WeatherUnavailable', () async {
      final down = sourceReplying((_) => http.Response('nope', 500));
      expect(down.search('London'), throwsA(isA<WeatherUnavailable>()));

      final limited = OpenMeteoWeatherSource(
        client: MockClient((_) async => throw const SocketException('offline')),
      );
      expect(limited.search('London'), throwsA(isA<WeatherUnavailable>()));
    });
  });

  group('forecast', () {
    const london = demoPlace;

    test('requests the daily and current fields for two days', () async {
      final seen = <Uri>[];
      final source = sourceReplying(
        (_) => ok('forecast_london.json'),
        seen: seen,
      );
      await source.forecast(london);

      final q = seen.single.queryParameters;
      expect(seen.single.host, 'api.open-meteo.com');
      expect(seen.single.path, '/v1/forecast');
      expect(q['latitude'], '51.50853');
      expect(q['longitude'], '-0.12574');
      expect(q['timezone'], 'auto');
      expect(q['forecast_days'], '2');
      expect(q['daily']!.split(','), [
        'temperature_2m_max',
        'temperature_2m_min',
        'apparent_temperature_max',
        'apparent_temperature_min',
        'precipitation_probability_max',
        'precipitation_sum',
        'wind_speed_10m_max',
        'weather_code',
      ]);
      expect(q['current']!.split(','), [
        'temperature_2m',
        'apparent_temperature',
        'precipitation',
        'weather_code',
      ]);
    });

    test(
      'parses today, tomorrow, the current reading and the rain peak',
      () async {
        final source = sourceReplying((_) => ok('forecast_london.json'));
        final f = await source.forecast(london);

        expect(f.fetchedAt, at);
        expect(f.lowC, 9.0);
        expect(f.highC, 14.1);
        expect(f.currentC, 10.2);
        expect(f.currentFeelsLikeC, 7.4);
        expect(f.today.feelsLikeLowC, 6.8);
        expect(f.today.feelsLikeHighC, 11.9);
        expect(f.today.rainChancePercent, 85);
        expect(f.today.rainMm, 3.2);
        expect(f.today.windKph, 24.5);
        expect(f.today.condition, WeatherCondition.rain);
        expect(f.tomorrow!.condition, WeatherCondition.partlyCloudy);
        expect(f.tomorrow!.rainChancePercent, 20);
        // The hourly chance peaks at 15:00.
        expect(f.rainPeak, DayPart.afternoon);
      },
    );

    test(
      'tolerates a sparse response: air temperature stands in for feels-like',
      () async {
        final source = sourceReplying((_) => ok('forecast_sparse.json'));
        final f = await source.forecast(london);

        expect(f.today.feelsLikeLowC, -2.5);
        expect(f.today.feelsLikeHighC, 3.0);
        expect(f.today.rainChancePercent, isNull);
        expect(f.today.windKph, isNull);
        // A code this build has never heard of is not an error.
        expect(f.today.condition, WeatherCondition.unknown);
        expect(f.currentC, isNull);
        expect(f.tomorrow, isNull);
        expect(f.rainPeak, isNull);
      },
    );

    test('values of the wrong type are skipped, not thrown on', () {
      final f = OpenMeteoWeatherSource.parseForecast(
        {
          'daily': {
            'temperature_2m_max': [10, 'warm'],
            'temperature_2m_min': [4, null],
            'precipitation_probability_max': ['lots'],
            'wind_speed_10m_max': 'gusty',
          },
          'current': 'nothing',
          'hourly': {'time': 5},
        },
        place: london,
        fetchedAt: at,
      );
      expect(f.today.feelsLikeHighC, 10);
      expect(f.today.rainChancePercent, isNull);
      expect(f.tomorrow, isNull);
    });

    test('a response without temperatures is unavailable', () {
      for (final bad in <Object?>[
        <String, Object?>{},
        <String, Object?>{'daily': <String, Object?>{}},
        <String, Object?>{'daily': 'x'},
        jsonDecode(fixture('error_limit.json')),
        'text',
        null,
      ]) {
        expect(
          () => OpenMeteoWeatherSource.parseForecast(
            bad,
            place: london,
            fetchedAt: at,
          ),
          throwsA(isA<WeatherUnavailable>()),
          reason: '$bad',
        );
      }
    });

    test(
      'HTTP failures, rate limits and garbage all read as unavailable',
      () async {
        for (final reply in [
          http.Response(fixture('error_limit.json'), 429),
          ok('error_limit.json'),
          http.Response('<html>', 200),
          http.Response('', 503),
        ]) {
          final source = sourceReplying((_) => reply);
          await expectLater(
            source.forecast(london),
            throwsA(isA<WeatherUnavailable>()),
            reason: '${reply.statusCode} ${reply.body}',
          );
        }
      },
    );
  });

  group('serialising', () {
    test('a forecast survives the preferences cache', () {
      final f = cannedForecast(demoPlace, at: at);
      final back = WeatherForecast.tryFromJson(
        jsonDecode(jsonEncode(f.toJson())),
      )!;
      expect(back.place, f.place);
      expect(back.fetchedAt, at);
      expect(back.today.feelsLikeLowC, f.today.feelsLikeLowC);
      expect(back.today.condition, WeatherCondition.rain);
      expect(back.rainPeak, DayPart.afternoon);
      expect(back.tomorrow!.windKph, 15);
    });

    test('a stored value that is not a forecast reads as absent', () {
      expect(WeatherForecast.tryFromJson(null), isNull);
      expect(WeatherForecast.tryFromJson('x'), isNull);
      expect(WeatherForecast.tryFromJson({'place': {}}), isNull);
      expect(Place.tryFromJson({'name': 'A', 'latitude': 'x'}), isNull);
    });
  });

  group('units', () {
    test(
      'Celsius is the default and Fahrenheit is for the US and a few more',
      () {
        expect(WeatherUnit.forCountry(null), WeatherUnit.celsius);
        expect(WeatherUnit.forCountry('GB'), WeatherUnit.celsius);
        expect(WeatherUnit.forCountry('US'), WeatherUnit.fahrenheit);
        expect(WeatherUnit.forCountry('us'), WeatherUnit.fahrenheit);
      },
    );

    test('conversion and formatting', () {
      expect(WeatherUnit.fahrenheit.fromCelsius(0), 32);
      expect(WeatherUnit.fahrenheit.fromCelsius(100), 212);
      expect(WeatherUnit.celsius.degrees(9.4), '9°');
      expect(WeatherUnit.fahrenheit.degrees(9.4), '49°');
      expect(WeatherUnit.celsius.range(9, 14.1), '9–14°');
      expect(WeatherUnit.celsius.range(9.2, 8.8), '9°');
      expect(WeatherUnit.fahrenheit.range(9, 14), '48–57°');
      expect(WeatherUnit.celsius.range(-2.5, 3), '-3–3°');
    });
  });

  group('the weather line', () {
    test('names the place, the range, how it feels and the rain', () async {
      final f = OpenMeteoWeatherSource.parseForecast(
        jsonDecode(fixture('forecast_london.json')),
        place: const Place(name: 'London', latitude: 51.5, longitude: -0.1),
        fetchedAt: at,
      );
      expect(
        weatherLine(f, WeatherUnit.celsius),
        'London · 9–14°, feels 7° · rain likely this afternoon',
      );
      expect(
        weatherLine(f, WeatherUnit.fahrenheit),
        'London · 48–57°, feels 45° · rain likely this afternoon',
      );
    });

    test('falls back to the day feels-like range and the sky', () {
      final f = OpenMeteoWeatherSource.parseForecast(
        jsonDecode(fixture('forecast_sparse.json')),
        place: const Place(name: 'New York', latitude: 40.7, longitude: -74),
        fetchedAt: at,
      );
      expect(
        weatherLine(f, WeatherUnit.celsius),
        'New York · -3–3°, feels -3–3°',
      );
    });
  });
}
