/// Today's weather, at the top of Ideas.
///
/// One compact line, then what the wardrobe is missing for the day, then the
/// two controls: refresh, and a switch to see the ideas without the weather.
/// With no city chosen it is a one-line invitation instead, and with weather
/// switched off or unavailable it is nothing or a quiet note: the ideas below
/// work exactly as they did before weather existed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/weather/weather_models.dart';
import '../weather/weather_providers.dart';

/// "London · 9–14°, feels 7° · rain likely this afternoon".
///
/// Pure, so the wording is tested without a widget. "Feels" is the current
/// feels-like when the source gave one and the day's feels-like range when it
/// did not.
String weatherLine(WeatherForecast forecast, WeatherUnit unit) {
  final today = forecast.today;
  final feels = forecast.currentFeelsLikeC != null
      ? 'feels ${unit.degrees(forecast.currentFeelsLikeC!)}'
      : 'feels ${unit.range(today.feelsLikeLowC, today.feelsLikeHighC)}';

  final needs = DressingNeeds.of(today);
  final sky = needs.snow
      ? 'snow'
      : needs.rainLikely
      ? ['rain likely', ?forecast.rainPeak?.phrase].join(' ')
      : needs.rainPossible
      ? 'chance of rain'
      : today.condition == WeatherCondition.unknown
      ? null
      : today.condition.label.toLowerCase();

  return [
    forecast.place.name,
    '${unit.range(forecast.lowC, forecast.highC)}, $feels',
    ?sky,
    if (needs.windy) 'windy',
  ].join(' · ');
}

class WeatherStrip extends ConsumerWidget {
  const WeatherStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unit = ref.watch(temperatureUnitProvider);
    final ignoring = ref.watch(ignoreWeatherProvider);

    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return switch (ref.watch(weatherViewProvider)) {
      WeatherOff() => const SizedBox.shrink(),
      WeatherNoPlace() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text('Set a city to dress for the weather.', style: muted),
            TextButton(
              onPressed: () => context.push('/settings'),
              child: const Text('Set a city'),
            ),
          ],
        ),
      ),
      WeatherLoading() => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('Checking the weather…', style: muted),
      ),
      WeatherMissing(:final place) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text('Weather unavailable for ${place.name}.', style: muted),
            TextButton(
              onPressed: () => refreshWeather(ref),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
      WeatherReady(:final forecast, :final needs) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              child: Text(
                weatherLine(forecast, unit),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!ignoring)
              for (final gap in _gaps(ref, needs))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(gap, style: muted),
                ),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Ignore the weather'),
                  selected: ignoring,
                  onSelected: (on) =>
                      ref.read(ignoreWeatherProvider.notifier).state = on,
                ),
                TextButton(
                  onPressed: () => refreshWeather(ref),
                  child: const Text('Refresh weather'),
                ),
              ],
            ),
          ],
        ),
      ),
    };
  }

  List<String> _gaps(WidgetRef ref, DressingNeeds needs) {
    final items = ref.watch(ownedItemsProvider).valueOrNull;
    if (items == null) return const [];
    return weatherGaps(items, needs);
  }
}
