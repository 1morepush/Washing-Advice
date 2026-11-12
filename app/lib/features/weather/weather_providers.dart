/// The weather, as the rest of the app sees it.
///
/// Settings (on/off, place, unit) are state seeded from the store; the forecast
/// is fetched through a [WeatherSource] and cached; and everything the Outfits
/// screen needs comes out as one [WeatherView], so the screen is a `switch`
/// over five cases and none of them is an error screen.
///
/// Caching: a forecast is reused for [forecastTtl] from memory, so opening the
/// tab does not refetch every time. The last good forecast is also kept in
/// preferences so a cold start (or a failed fetch) can still show today's
/// weather when it is recent enough ([lastGoodTtl]) instead of nothing.
library;

import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_source.dart';

/// How long a fetched forecast is reused without asking again.
const forecastTtl = Duration(hours: 1);

/// How old a stored forecast may be and still be shown when a fetch fails.
const lastGoodTtl = Duration(hours: 6);

/// The HTTP client weather requests go through. Overridden in tests.
final weatherHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final weatherSourceProvider = Provider<WeatherSource>(
  (ref) => OpenMeteoWeatherSource(client: ref.watch(weatherHttpClientProvider)),
);

/// Whether weather shapes the ideas at all.
///
/// Plain defaults rather than reads of the store, for the reason given on
/// `splitDryingProvider`: the Outfits and Settings screens watch these, and
/// making every test that builds either wire up SharedPreferences first would
/// be the tail wagging the dog. [weatherSeedOverrides] seeds them from the
/// stored values at startup, and the Settings section writes through to both.
final weatherOnProvider = StateProvider<bool>((ref) => true);

final weatherPlaceProvider = StateProvider<Place?>((ref) => null);

/// Celsius or Fahrenheit. Defaults to what the device locale expects
/// (Fahrenheit in the US) until a choice is stored.
final temperatureUnitProvider = StateProvider<WeatherUnit>(
  (ref) =>
      WeatherUnit.forCountry(PlatformDispatcher.instance.locale.countryCode),
);

/// The stored weather settings, as overrides for `main()`.
List<Override> weatherSeedOverrides(SettingsStore settings) {
  Place? place;
  final storedPlace = settings.weatherPlaceJson;
  if (storedPlace != null) {
    try {
      place = Place.tryFromJson(jsonDecode(storedPlace));
    } on FormatException {
      place = null;
    }
  }
  final unit = WeatherUnit.values.asNameMap()[settings.weatherUnitName];
  return [
    weatherOnProvider.overrideWith((ref) => settings.weatherOn),
    weatherPlaceProvider.overrideWith((ref) => place),
    if (unit != null) temperatureUnitProvider.overrideWith((ref) => unit),
  ];
}

/// "Show me ideas ignoring the weather", for this session only.
final ignoreWeatherProvider = StateProvider<bool>((ref) => false);

/// The clock the cache reads. Overridden in tests.
final weatherClockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now(),
);

/// Holds the in-memory forecast and decides when to fetch.
class WeatherService {
  WeatherService(this._ref);

  final Ref _ref;

  WeatherForecast? _memory;
  bool _forceNext = false;

  /// Makes the next [load] skip the cache. Called by "Refresh".
  void forceRefresh() => _forceNext = true;

  /// The forecast for [place], or null when it cannot be had.
  Future<WeatherForecast?> load(Place place) async {
    final now = _ref.read(weatherClockProvider)().toUtc();
    final force = _forceNext;
    _forceNext = false;

    bool fresh(WeatherForecast f, Duration ttl) =>
        f.place == place && now.difference(f.fetchedAt) < ttl;

    final cached = _memory;
    if (!force && cached != null && fresh(cached, forecastTtl)) return cached;

    final store = _ref.read(settingsStoreProvider);
    final stored = _readStored(store);

    // A cold start: the stored forecast is as good as a memory one.
    if (!force && stored != null && fresh(stored, forecastTtl)) {
      return _memory = stored;
    }

    try {
      final fetched = await _ref.read(weatherSourceProvider).forecast(place);
      // Stamped with our clock rather than trusting the source's, so the
      // cache age is measured on one clock.
      final forecast = WeatherForecast(
        place: place,
        fetchedAt: now,
        today: fetched.today,
        tomorrow: fetched.tomorrow,
        lowC: fetched.lowC,
        highC: fetched.highC,
        currentC: fetched.currentC,
        currentFeelsLikeC: fetched.currentFeelsLikeC,
        rainPeak: fetched.rainPeak,
      );
      _memory = forecast;
      await store.setWeatherLastGoodJson(jsonEncode(forecast.toJson()));
      return forecast;
    } on Object {
      // Offline, rate-limited, malformed: fall back to something recent, or
      // to nothing. Never an error.
      final fallback = _memory ?? stored;
      if (fallback != null && fresh(fallback, lastGoodTtl)) return fallback;
      return null;
    }
  }

  WeatherForecast? _readStored(SettingsStore store) {
    final raw = store.weatherLastGoodJson;
    if (raw == null) return null;
    try {
      return WeatherForecast.tryFromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }
}

final weatherServiceProvider = Provider<WeatherService>(WeatherService.new);

/// Bumped to refetch.
final weatherRefreshProvider = StateProvider<int>((ref) => 0);

/// Asks for a fresh forecast, skipping the cache.
void refreshWeather(WidgetRef ref) {
  ref.read(weatherServiceProvider).forceRefresh();
  ref.read(weatherRefreshProvider.notifier).state++;
}

final forecastProvider = FutureProvider<WeatherForecast?>((ref) {
  final place = ref.watch(weatherPlaceProvider);
  final on = ref.watch(weatherOnProvider);
  ref.watch(weatherRefreshProvider);
  if (!on || place == null) return null;
  return ref.read(weatherServiceProvider).load(place);
});

/// What the Outfits screen shows, one case at a time.
sealed class WeatherView {
  const WeatherView();
}

/// Switched off in Settings: the screen shows nothing about weather.
final class WeatherOff extends WeatherView {
  const WeatherOff();
}

/// On, but no city chosen yet: the screen invites one.
final class WeatherNoPlace extends WeatherView {
  const WeatherNoPlace();
}

final class WeatherLoading extends WeatherView {
  const WeatherLoading(this.place);
  final Place place;
}

/// A quiet "weather unavailable"; ideas work as before.
final class WeatherMissing extends WeatherView {
  const WeatherMissing(this.place);
  final Place place;
}

final class WeatherReady extends WeatherView {
  const WeatherReady(this.forecast, this.needs);
  final WeatherForecast forecast;
  final DressingNeeds needs;
}

final weatherViewProvider = Provider<WeatherView>((ref) {
  if (!ref.watch(weatherOnProvider)) return const WeatherOff();
  final place = ref.watch(weatherPlaceProvider);
  if (place == null) return const WeatherNoPlace();
  final forecast = ref.watch(forecastProvider);
  return forecast.when(
    loading: () => WeatherLoading(place),
    error: (_, _) => WeatherMissing(place),
    data: (f) => f == null
        ? WeatherMissing(place)
        : WeatherReady(f, DressingNeeds.of(f.today)),
  );
});

/// The needs the builder is given: the forecast's, unless there is none or the
/// person asked to ignore the weather.
final weatherNeedsProvider = Provider<DressingNeeds?>((ref) {
  if (ref.watch(ignoreWeatherProvider)) return null;
  return switch (ref.watch(weatherViewProvider)) {
    WeatherReady(:final needs) => needs,
    _ => null,
  };
});

/// What the builder is asked, with the weather folded in.
///
/// Kept apart from [outfitRequestProvider] so that stays the person's own
/// choices (occasion, season, layer) and the weather is layered on top at the
/// last moment.
final weatherAwareRequestProvider = Provider<OutfitRequest>((ref) {
  final request = ref.watch(outfitRequestProvider);
  final needs = ref.watch(weatherNeedsProvider);
  if (needs == null) return request;
  return OutfitRequest(
    occasion: request.occasion,
    season: request.season,
    count: request.count,
    includeOuterwear: request.includeOuterwear,
    includeFootwear: request.includeFootwear,
    mustInclude: request.mustInclude,
    exclude: request.exclude,
    needs: needs,
  );
});
