/// Weather, in Settings: a switch, a city, and a unit.
///
/// The city is typed and picked from matches, never read from the device, so
/// there is no location permission and nothing to explain beyond one sentence
/// of what leaves the phone: the search text and the chosen coordinates go to
/// Open-Meteo, and nothing about the wardrobe does.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../data/weather/weather_models.dart';
import '../weather/weather_providers.dart';
import 'setting_info.dart';

/// What the group's info button says, and the privacy statement in full.
const weatherInfo =
    'Outfit ideas can take today\'s weather into account: a layer when it is '
    'cold, a waterproof one when it will rain, lighter pieces in the heat.\n\n'
    'You type a city and pick it from the matches; the phone\'s location is '
    'never used. What leaves your phone: the text you search for, and the '
    'coordinates of the city you pick, which go to Open-Meteo (a free weather '
    'service, no account) to get the forecast. Nothing about your wardrobe is '
    'sent.';

/// The one-line version, shown under the controls.
const weatherPrivacyLine =
    'Only the city you search for and its coordinates are sent to Open-Meteo. '
    'Nothing about your wardrobe leaves the phone.';

class WeatherSection extends ConsumerStatefulWidget {
  const WeatherSection({super.key});

  @override
  ConsumerState<WeatherSection> createState() => _WeatherSectionState();
}

class _WeatherSectionState extends ConsumerState<WeatherSection> {
  final _query = TextEditingController();

  List<Place>? _matches;
  bool _searching = false;
  bool _failed = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    if (text.length < 2 || _searching) return;
    setState(() {
      _searching = true;
      _failed = false;
    });
    try {
      final found = await ref.read(weatherSourceProvider).search(text);
      if (!mounted) return;
      setState(() => _matches = found);
    } on Object {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _matches = null;
      });
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _pick(Place place) async {
    final store = ref.read(settingsStoreProvider);
    final notifier = ref.read(weatherPlaceProvider.notifier);
    await store.setWeatherPlaceJson(jsonEncode(place.toJson()));
    notifier.state = place;
    if (!mounted) return;
    setState(() {
      _matches = null;
      _query.clear();
    });
  }

  Future<void> _clear() async {
    final store = ref.read(settingsStoreProvider);
    final notifier = ref.read(weatherPlaceProvider.notifier);
    await store.setWeatherPlaceJson(null);
    await store.setWeatherLastGoodJson(null);
    notifier.state = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = ref.watch(weatherOnProvider);
    final place = ref.watch(weatherPlaceProvider);
    final unit = ref.watch(temperatureUnitProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          value: on,
          onChanged: (value) async {
            final store = ref.read(settingsStoreProvider);
            final notifier = ref.read(weatherOnProvider.notifier);
            await store.setWeatherOn(value);
            notifier.state = value;
          },
          contentPadding: EdgeInsets.zero,
          title: const Text('Use the weather for outfit ideas'),
          subtitle: Text(on ? 'On' : 'Off'),
        ),
        if (on) ...[
          const RowDivider(),
          const SizedBox(height: 8),
          Text('Your city', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          if (place != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    place.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: context.rinse.textAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton(onPressed: _clear, child: const Text('Remove')),
              ],
            )
          else
            Text(
              'No city set yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: place == null ? 'Search for a city' : 'Change city',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(
              onPressed: _searching ? null : _search,
              child: Text(_searching ? 'Searching…' : 'Search'),
            ),
          ),
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              'Could not search just now. Check your connection and try '
              'again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_matches case final matches?) ...[
            const SizedBox(height: 8),
            if (matches.isEmpty)
              Text(
                'No city found for "${_query.text.trim()}". Try the name on '
                'its own, without the country.',
                style: theme.textTheme.bodyMedium,
              )
            else
              for (final match in matches)
                ListTile(
                  key: ValueKey('match-${match.latitude}-${match.longitude}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(match.name),
                  subtitle: Text(
                    [
                      if (match.region case final String r) r,
                      if (match.country case final String c) c,
                    ].join(', '),
                  ),
                  trailing: Text(
                    'Use this',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: context.rinse.textAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onTap: () => _pick(match),
                ),
          ],
          const RowDivider(),
          const SizedBox(height: 8),
          Text('Temperatures in', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<WeatherUnit>(
            segments: [
              for (final option in WeatherUnit.values)
                ButtonSegment(value: option, label: Text(option.symbol)),
            ],
            selected: {unit},
            showSelectedIcon: false,
            onSelectionChanged: (chosen) async {
              final store = ref.read(settingsStoreProvider);
              final notifier = ref.read(temperatureUnitProvider.notifier);
              await store.setWeatherUnitName(chosen.single.name);
              notifier.state = chosen.single;
            },
          ),
          const SizedBox(height: 12),
          Text(
            weatherPrivacyLine,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// The group's header value: the city, or what is missing.
String weatherValue({required bool on, required Place? place}) =>
    !on ? 'Off' : (place?.name ?? 'No city');
