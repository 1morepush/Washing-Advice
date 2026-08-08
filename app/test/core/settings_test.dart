/// A machine AI identified from its exact brand and model: persistence, and
/// that it wins over a seeded brand archetype once one exists.
///
/// Distinct from `washerBrand`/`dryerBrand`, which are lookup keys into a
/// catalogue that keeps improving — a custom profile is deliberately the
/// opposite, a frozen answer for one exact machine, which is the entire
/// reason asking AI for it was worth doing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/settings.dart';

void main() {
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());
  });

  WasherProfile washer({String model = 'WF45T6000AW'}) => WasherProfile(
    id: WasherId('ai.washer.samsung.${model.toLowerCase()}'),
    brand: 'Samsung',
    model: model,
    capacityKg: 9.0,
    programs: [
      WashProgram(
        id: 'p0',
        displayName: 'Cotton',
        kind: WashProgramKind.cotton,
        availableTempsC: const [0, 30, 40],
        defaultTempC: 40,
        agitation: Agitation.normal,
        spinSpeedsRpm: const [0, 800, 1200],
        suitableFor: const {FabricClass.normal},
      ),
    ],
  );

  DryerProfile dryer() => DryerProfile(
    id: const DryerId('ai.dryer.lg.dlex3900w'),
    brand: 'LG',
    model: 'DLEX3900W',
    capacityKg: 7.5,
    programs: [
      DryProgram(
        id: 'p0',
        displayName: 'Normal',
        kind: DryProgramKind.normal,
        availableHeats: const [TumbleDryHeat.medium],
        defaultHeat: TumbleDryHeat.medium,
        suitableFor: const {FabricClass.normal},
      ),
    ],
  );

  group('persistence', () {
    test('a stored washer profile round-trips exactly', () async {
      final built = washer();
      await settings.setCustomWasher(built);

      final read = settings.customWasher;

      expect(read, isNotNull);
      expect(read!.toJson(), built.toJson());
    });

    test('a stored dryer profile round-trips exactly', () async {
      final built = dryer();
      await settings.setCustomDryer(built);

      expect(settings.customDryer?.toJson(), built.toJson());
    });

    test('setting null clears a previously stored profile', () async {
      await settings.setCustomWasher(washer());
      await settings.setCustomWasher(null);

      expect(settings.customWasher, isNull);
    });

    test('nothing stored reads as null, not an error', () {
      expect(settings.customWasher, isNull);
      expect(settings.customDryer, isNull);
    });

    test(
      'a corrupted stored value reads as absent rather than throwing',
      () async {
        // The same key `setCustomWasher` writes to, poked directly to simulate
        // a record from a build old or new enough that this one cannot parse —
        // a real scenario `_readBrand`'s docstring already names for the
        // seeded-brand case, and a custom profile is no more immune to it.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('customWasherProfile', '{"not": "a washer"}');

        expect(settings.customWasher, isNull);

        await prefs.setString('customWasherProfile', 'not even json');

        expect(settings.customWasher, isNull);
      },
    );
  });

  group('precedence', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(settings)],
      );
    });

    tearDown(() => container.dispose());

    /// Mirrors what the real settings screen does: write through the store
    /// for persistence, and through the provider's own state for what this
    /// session reads immediately — the same two-step every other setting in
    /// this store already requires (`washerBrandProvider`, `syncTokenProvider`).
    Future<void> selectSeededBrand(String brand) async {
      await settings.setWasherBrand(brand);
      container.read(washerBrandProvider.notifier).state = brand;
    }

    Future<void> setCustom(WasherProfile? profile) async {
      await settings.setCustomWasher(profile);
      container.read(customWasherProvider.notifier).state = profile;
    }

    test('with nothing set, there is no washer', () {
      expect(container.read(washerProvider), isNull);
    });

    test('a seeded brand is used when no custom profile exists', () async {
      await selectSeededBrand('Bosch');

      expect(container.read(washerProvider)?.brand, 'Bosch');
    });

    test('a custom profile wins over a seeded brand selection', () async {
      await selectSeededBrand('Bosch');
      await setCustom(washer());

      expect(container.read(washerProvider)?.brand, 'Samsung');
      expect(container.read(washerProvider)?.model, 'WF45T6000AW');
    });

    test(
      'removing the custom profile falls back to the seeded brand',
      () async {
        await selectSeededBrand('Bosch');
        await setCustom(washer());
        await setCustom(null);

        expect(container.read(washerProvider)?.brand, 'Bosch');
      },
    );
  });
}
