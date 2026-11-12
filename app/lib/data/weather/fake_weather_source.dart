/// A [WeatherSource] that never touches the network.
///
/// Used by tests, and by the demo build, which shows a canned London day so
/// the weather line and reasons appear in screenshots.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

import 'weather_models.dart';
import 'weather_source.dart';

/// The place the demo build has "chosen".
const demoPlace = Place(
  name: 'London',
  region: 'England',
  country: 'United Kingdom',
  latitude: 51.50853,
  longitude: -0.12574,
);

class FakeWeatherSource implements WeatherSource {
  FakeWeatherSource({
    this.places = const [demoPlace],
    this.forecastFor,
    this.fail = false,
  });

  /// What every search returns.
  List<Place> places;

  /// Builds the forecast for a place; defaults to [cannedForecast].
  WeatherForecast Function(Place place)? forecastFor;

  /// Makes every call throw [WeatherUnavailable].
  bool fail;

  final List<String> searches = [];
  int forecastCalls = 0;

  @override
  Future<List<Place>> search(String query) async {
    searches.add(query);
    if (fail) throw const WeatherUnavailable('fake failure');
    return places;
  }

  @override
  Future<WeatherForecast> forecast(Place place) async {
    forecastCalls++;
    if (fail) throw const WeatherUnavailable('fake failure');
    return (forecastFor ?? cannedForecast)(place);
  }
}

/// A cool, wet day: 9 to 14 degrees, feeling 7 to 12, rain this afternoon.
WeatherForecast cannedForecast(Place place, {DateTime? at}) => WeatherForecast(
  place: place,
  fetchedAt: at ?? DateTime.now().toUtc(),
  lowC: 9,
  highC: 14,
  currentC: 10,
  currentFeelsLikeC: 7,
  rainPeak: DayPart.afternoon,
  today: const Weather(
    feelsLikeLowC: 7,
    feelsLikeHighC: 12,
    rainChancePercent: 80,
    rainMm: 3.2,
    windKph: 24,
    condition: WeatherCondition.rain,
  ),
  tomorrow: const Weather(
    feelsLikeLowC: 6,
    feelsLikeHighC: 13,
    rainChancePercent: 20,
    rainMm: 0,
    windKph: 15,
    condition: WeatherCondition.partlyCloudy,
  ),
);
