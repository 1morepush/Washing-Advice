/// Weather on the Outfits tab and in Settings.
///
/// Everything runs against a `FakeWeatherSource` and in-memory stores, so no
/// test reaches the network. The rule itself is tested in the core; what this
/// covers is that it reaches the screen, that the cache behaves, and that the
/// controls in Settings do what they say.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/data/weather/fake_weather_source.dart';
import 'package:washing_advice/data/weather/weather_models.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';
import 'package:washing_advice/features/settings/weather_section.dart';
import 'package:washing_advice/features/weather/weather_providers.dart';

import '../support/fixtures.dart';

const _london = demoPlace;

void main() {
  late InMemoryWardrobeRepository repository;
  late SettingsStore store;
  late FakeWeatherSource source;
  late DateTime now;

  // The real font, as `layout_fit_test.dart` loads it: the test default draws
  // every glyph as a square and reports screens that fit as overflowing.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader(rinseFontFamily);
    for (final file in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/Nunito-$file.ttf'));
    }
    await loader.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = SettingsStore(await SharedPreferences.getInstance());
    source = FakeWeatherSource();
    now = DateTime.utc(2026, 11, 12, 9);
    repository = InMemoryWardrobeRepository();
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'White tee'),
      confidentItem(
        id: 'long',
        name: 'Navy long sleeve',
        type: ItemType.longSleeveShirt,
      ),
      confidentItem(id: 'jeans', name: 'Selvedge jeans', type: ItemType.jeans),
      confidentItem(
        id: 'mac',
        name: 'Yellow mac',
        type: ItemType.jacket,
        tags: {'waterproof'},
      ),
      confidentItem(id: 'boots', name: 'Brown boots', type: ItemType.boots),
      confidentItem(id: 'sandals', name: 'Tan sandals', type: ItemType.sandals),
    ]);
  });

  ProviderContainer containerWith({
    Place? place = _london,
    bool on = true,
    WeatherUnit unit = WeatherUnit.celsius,
  }) {
    final container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        weatherSourceProvider.overrideWithValue(source),
        weatherClockProvider.overrideWithValue(() => now),
        weatherPlaceProvider.overrideWith((ref) => place),
        weatherOnProvider.overrideWith((ref) => on),
        temperatureUnitProvider.overrideWith((ref) => unit),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'w'),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpOutfits(
    WidgetTester tester,
    ProviderContainer container, {
    Size size = const Size(1000, 2400),
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const OutfitsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the forecast cache', () {
    test('a second look within the hour does not fetch again', () async {
      final c = containerWith();
      final service = c.read(weatherServiceProvider);

      await service.load(_london);
      now = now.add(const Duration(minutes: 59));
      await service.load(_london);

      expect(source.forecastCalls, 1);
    });

    test('after the hour it fetches again', () async {
      final c = containerWith();
      final service = c.read(weatherServiceProvider);

      await service.load(_london);
      now = now.add(const Duration(minutes: 61));
      await service.load(_london);

      expect(source.forecastCalls, 2);
    });

    test('refresh skips the cache once', () async {
      final c = containerWith();
      final service = c.read(weatherServiceProvider);

      await service.load(_london);
      service.forceRefresh();
      await service.load(_london);
      await service.load(_london);

      expect(source.forecastCalls, 2);
    });

    test(
      'a different place is never served from the first place\'s cache',
      () async {
        final c = containerWith();
        final service = c.read(weatherServiceProvider);
        await service.load(_london);
        await service.load(
          const Place(name: 'Paris', latitude: 48.85, longitude: 2.35),
        );
        expect(source.forecastCalls, 2);
      },
    );

    test('a cold start reuses the stored forecast while it is fresh', () async {
      final first = containerWith();
      await first.read(weatherServiceProvider).load(_london);
      expect(store.weatherLastGoodJson, isNotNull);

      now = now.add(const Duration(minutes: 20));
      final second = containerWith();
      final f = await second.read(weatherServiceProvider).load(_london);

      expect(f, isNotNull);
      expect(source.forecastCalls, 1);
    });

    test('a failed fetch falls back to a recent stored forecast', () async {
      await containerWith().read(weatherServiceProvider).load(_london);

      now = now.add(const Duration(hours: 3));
      source.fail = true;
      final f = await containerWith()
          .read(weatherServiceProvider)
          .load(_london);

      expect(f, isNotNull, reason: 'three hours old is still today\'s weather');
    });

    test('a failed fetch with nothing recent is simply no weather', () async {
      await containerWith().read(weatherServiceProvider).load(_london);

      now = now.add(const Duration(hours: 7));
      source.fail = true;
      final f = await containerWith()
          .read(weatherServiceProvider)
          .load(_london);

      expect(f, isNull);
    });

    test(
      'a failure with nothing stored is no weather, not an exception',
      () async {
        source.fail = true;
        final f = await containerWith()
            .read(weatherServiceProvider)
            .load(_london);
        expect(f, isNull);
      },
    );

    test('a corrupt stored forecast is ignored', () async {
      await store.setWeatherLastGoodJson('{not json');
      final f = await containerWith()
          .read(weatherServiceProvider)
          .load(_london);
      expect(f, isNotNull);
      expect(source.forecastCalls, 1);
    });
  });

  group('the view', () {
    test('off, no place, unavailable and ready are distinct', () async {
      expect(
        containerWith(on: false).read(weatherViewProvider),
        isA<WeatherOff>(),
      );
      expect(
        containerWith(place: null).read(weatherViewProvider),
        isA<WeatherNoPlace>(),
      );

      source.fail = true;
      final broken = containerWith();
      await broken.read(forecastProvider.future);
      expect(broken.read(weatherViewProvider), isA<WeatherMissing>());
      expect(broken.read(weatherNeedsProvider), isNull);

      source.fail = false;
      final ok = containerWith();
      await ok.read(forecastProvider.future);
      expect(ok.read(weatherViewProvider), isA<WeatherReady>());
      expect(ok.read(weatherNeedsProvider), isNotNull);
    });

    test(
      'ignoring the weather drops the needs but keeps the forecast',
      () async {
        final c = containerWith();
        await c.read(forecastProvider.future);
        c.read(ignoreWeatherProvider.notifier).state = true;
        expect(c.read(weatherNeedsProvider), isNull);
        expect(c.read(weatherViewProvider), isA<WeatherReady>());
        expect(c.read(weatherAwareRequestProvider).needs, isNull);
      },
    );
  });

  group('Outfits', () {
    testWidgets('shows the weather line and the weather reason on each idea', (
      tester,
    ) async {
      await pumpOutfits(tester, containerWith());

      expect(
        find.text('London · 9–14°, feels 7° · rain likely this afternoon'),
        findsOneWidget,
      );
      // Rainy and cool: the waterproof mac and closed shoes.
      expect(find.textContaining('a waterproof jacket'), findsWidgets);
      expect(find.textContaining('closed shoes'), findsWidgets);
    });

    testWidgets('shows the line in Fahrenheit when asked', (tester) async {
      await pumpOutfits(tester, containerWith(unit: WeatherUnit.fahrenheit));
      expect(
        find.text('London · 48–57°, feels 45° · rain likely this afternoon'),
        findsOneWidget,
      );
    });

    testWidgets('the rain ideas leave sandals out', (tester) async {
      final c = containerWith();
      await pumpOutfits(tester, c);
      final ideas = c.read(outfitSuggestionsProvider).value!;
      expect(ideas, isNotEmpty);
      for (final idea in ideas) {
        expect(idea.items.map((i) => i.id.value), isNot(contains('sandals')));
        expect(idea.items.map((i) => i.id.value), contains('mac'));
      }
    });

    testWidgets('says what the wardrobe lacks', (tester) async {
      await repository.delete(ItemId('mac'));
      await repository.saveAll([
        confidentItem(id: 'cag', name: 'Plain jacket', type: ItemType.jacket),
      ]);
      await pumpOutfits(tester, containerWith());
      expect(
        find.textContaining('No waterproof layer in your wardrobe'),
        findsOneWidget,
      );
    });

    testWidgets('"Ignore the weather" brings back the plain ideas', (
      tester,
    ) async {
      final c = containerWith();
      await pumpOutfits(tester, c);
      expect(find.textContaining('a waterproof jacket'), findsWidgets);

      await tester.tap(find.text('Ignore the weather'));
      await tester.pumpAndSettle();

      expect(find.textContaining('a waterproof jacket'), findsNothing);
      // The line itself stays: it is the weather, not the ideas, that was
      // set aside.
      expect(find.textContaining('London ·'), findsOneWidget);
      expect(c.read(weatherAwareRequestProvider).needs, isNull);
    });

    testWidgets('the occasion filter keeps working alongside', (tester) async {
      final c = containerWith();
      await pumpOutfits(tester, c);
      await tester.tap(find.text('Lounge'));
      await tester.pumpAndSettle();
      expect(c.read(outfitRequestProvider).occasion, Occasion.lounge);
      expect(c.read(weatherAwareRequestProvider).occasion, Occasion.lounge);
      expect(c.read(weatherAwareRequestProvider).needs, isNotNull);
    });

    testWidgets('refresh asks for a new forecast', (tester) async {
      await pumpOutfits(tester, containerWith());
      expect(source.forecastCalls, 1);

      await tester.tap(find.text('Refresh weather'));
      await tester.pumpAndSettle();

      expect(source.forecastCalls, 2);
    });

    testWidgets('with weather off there is no weather line and no reasons', (
      tester,
    ) async {
      await pumpOutfits(tester, containerWith(on: false));
      expect(find.textContaining('London'), findsNothing);
      expect(find.text('Ignore the weather'), findsNothing);
      expect(find.textContaining('waterproof'), findsNothing);
      expect(source.forecastCalls, 0);
    });

    testWidgets('with no place it invites one and works as before', (
      tester,
    ) async {
      final c = containerWith(place: null);
      await pumpOutfits(tester, c);
      expect(find.text('Set a city to dress for the weather.'), findsOneWidget);
      expect(find.text('Set a city'), findsOneWidget);
      expect(c.read(outfitSuggestionsProvider).value, isNotEmpty);
      expect(source.forecastCalls, 0);
    });

    testWidgets('when the weather is unavailable it says so quietly', (
      tester,
    ) async {
      source.fail = true;
      final c = containerWith();
      await pumpOutfits(tester, c);
      expect(find.text('Weather unavailable for London.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(c.read(outfitSuggestionsProvider).value, isNotEmpty);
    });

    for (final (name, theme) in [
      ('Light', AppTheme.light()),
      ('Dark', AppTheme.dark()),
    ]) {
      testWidgets('fits 320 px wide at 1.6 text scale in $name', (
        tester,
      ) async {
        await pumpOutfits(
          tester,
          containerWith(),
          size: const Size(320, 4000),
          textScale: 1.6,
          theme: theme,
        );
        expect(tester.takeException(), isNull);

        // And the no-place and unavailable states, which are different
        // widgets.
        await pumpOutfits(
          tester,
          containerWith(place: null),
          size: const Size(320, 4000),
          textScale: 1.6,
          theme: theme,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Settings', () {
    Future<ProviderContainer> pumpSection(
      WidgetTester tester, {
      Place? place,
      double textScale = 1,
      Size size = const Size(1000, 2400),
      ThemeData? theme,
    }) async {
      final container = containerWith(place: place);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: WeatherSection(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('searching lists matches by name, region and country', (
      tester,
    ) async {
      source.places = const [
        _london,
        Place(
          name: 'London',
          region: 'Ontario',
          country: 'Canada',
          latitude: 42.98,
          longitude: -81.23,
        ),
      ];
      await pumpSection(tester);

      await tester.enterText(find.byType(TextField), 'London');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(source.searches, ['London']);
      expect(find.text('England, United Kingdom'), findsOneWidget);
      expect(find.text('Ontario, Canada'), findsOneWidget);
    });

    testWidgets('picking a match stores the name and coordinates', (
      tester,
    ) async {
      final c = await pumpSection(tester);

      await tester.enterText(find.byType(TextField), 'London');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();

      expect(c.read(weatherPlaceProvider), _london);
      final stored = jsonDecode(store.weatherPlaceJson!) as Map;
      expect(stored['name'], 'London');
      expect(stored['latitude'], 51.50853);
      expect(stored['longitude'], -0.12574);
      expect(find.text('London, England, United Kingdom'), findsOneWidget);
    });

    testWidgets('no matches and a failed search are both said plainly', (
      tester,
    ) async {
      source.places = const [];
      await pumpSection(tester);
      await tester.enterText(find.byType(TextField), 'Zzzz');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No city found for "Zzzz"'), findsOneWidget);

      source.fail = true;
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not search just now'), findsOneWidget);
    });

    testWidgets('removing the city clears it and its cached forecast', (
      tester,
    ) async {
      await store.setWeatherLastGoodJson('{}');
      final c = await pumpSection(tester, place: _london);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(c.read(weatherPlaceProvider), isNull);
      expect(store.weatherPlaceJson, isNull);
      expect(store.weatherLastGoodJson, isNull);
    });

    testWidgets('the unit switch is kept', (tester) async {
      final c = await pumpSection(tester);
      await tester.tap(find.text('°F'));
      await tester.pumpAndSettle();
      expect(c.read(temperatureUnitProvider), WeatherUnit.fahrenheit);
      expect(store.weatherUnitName, 'fahrenheit');
    });

    testWidgets('the switch turns weather off and hides the controls', (
      tester,
    ) async {
      final c = await pumpSection(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(c.read(weatherOnProvider), isFalse);
      expect(store.weatherOn, isFalse);
      expect(find.text('Search'), findsNothing);
    });

    testWidgets('says what leaves the phone', (tester) async {
      await pumpSection(tester);
      expect(find.text(weatherPrivacyLine), findsOneWidget);
      expect(weatherInfo, contains('Open-Meteo'));
      expect(weatherInfo, contains('Nothing about your wardrobe is sent'));
    });

    test('startup seeds the providers from the stored values', () async {
      await store.setWeatherOn(false);
      await store.setWeatherPlaceJson(jsonEncode(_london.toJson()));
      await store.setWeatherUnitName('fahrenheit');
      final c = ProviderContainer(overrides: weatherSeedOverrides(store));
      addTearDown(c.dispose);
      expect(c.read(weatherOnProvider), isFalse);
      expect(c.read(weatherPlaceProvider), _london);
      expect(c.read(temperatureUnitProvider), WeatherUnit.fahrenheit);
    });

    test('an unreadable stored place is no place', () async {
      await store.setWeatherPlaceJson('not json');
      final c = ProviderContainer(overrides: weatherSeedOverrides(store));
      addTearDown(c.dispose);
      expect(c.read(weatherPlaceProvider), isNull);
    });

    for (final (name, theme) in [
      ('Light', AppTheme.light()),
      ('Dark', AppTheme.dark()),
    ]) {
      testWidgets('fits 320 px wide at 1.6 text scale in $name', (
        tester,
      ) async {
        source.places = const [
          Place(
            name: 'Llanfairpwllgwyngyll',
            region: 'Isle of Anglesey County',
            country: 'United Kingdom',
            latitude: 53.2,
            longitude: -4.2,
          ),
        ];
        await pumpSection(
          tester,
          place: _london,
          size: const Size(320, 3000),
          textScale: 1.6,
          theme: theme,
        );
        await tester.enterText(find.byType(TextField), 'Llan');
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
