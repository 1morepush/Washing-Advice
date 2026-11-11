/// The whole app, with a wear history, for the calendar and the "not worn in a
/// year" suggestion.
///
/// Built the way `SellHarness` is — the router, screens, controllers and
/// providers are what ships, and only what reaches outside the process is
/// replaced — but with the event log in the test's hands, since both features
/// are projections of it, and with a clock it can set.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/sell/list/listing_clock.dart';
import 'package:washing_advice/main.dart';

import '../features/sell/sell_list_harness.dart' show FakeSellGateway;
import 'fixtures.dart';

class HistoryHarness {
  HistoryHarness._(this.prefs, this.now);

  /// A fresh app whose clock reads [now] — local time, so that the day it is
  /// does not depend on the machine's zone.
  static Future<HistoryHarness> create({DateTime? now}) async {
    SharedPreferences.setMockInitialValues({});
    return HistoryHarness._(
      await SharedPreferences.getInstance(),
      now ?? DateTime(2026, 3, 15, 12),
    );
  }

  final SharedPreferences prefs;
  DateTime now;

  final wardrobe = InMemoryWardrobeRepository();
  final events = InMemoryEventLog();
  final outfits = InMemoryOutfitRepository();
  final listings = InMemoryListingRepository();
  final images = MemoryImageStore();
  final gateway = FakeSellGateway();

  var _ids = 0;

  /// The app's providers, built on first use inside the test that wants them.
  late final ProviderContainer app = newApp();

  /// A fresh set of providers over the same stores: the app as it is after a
  /// restart, with nothing in memory and everything on the "phone".
  ProviderContainer newApp() {
    final built = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(SettingsStore(prefs)),
        wardrobeRepositoryProvider.overrideWithValue(wardrobe),
        outfitRepositoryProvider.overrideWithValue(outfits),
        eventLogProvider.overrideWithValue(events),
        listingRepositoryProvider.overrideWithValue(listings),
        imageStoreProvider.overrideWithValue(images),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'new'),
        ),
        listingClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(built.dispose);
    return built;
  }

  /// A garment, optionally added on a given day and with a picture.
  Future<WardrobeItem> addGarment(
    String id, {
    String? name,
    ItemType type = ItemType.tShirt,
    DateTime? addedAt,
    UsageStats usage = const UsageStats(timesWorn: 1),
    LifecycleState lifecycle = LifecycleState.active,
    bool photo = false,
  }) async {
    var item = confidentItem(
      id: id,
      name: name ?? 'Garment $id',
      type: type,
      usage: usage,
      lifecycle: lifecycle,
    );
    if (photo) {
      final uri = await images.save(
        Uint8List.fromList(utf8.encode('photo-of-$id')),
        name: '$id-front',
      );
      item = item.copyWith(
        photos: PhotoSet([
          ItemPhoto(
            uri: uri,
            role: PhotoRole.front,
            capturedAt: DateTime.utc(2026, 8, 5),
          ),
        ]),
      );
    }
    if (addedAt != null) {
      // `copyWith` cannot move `addedAt`, deliberately; a test that needs an
      // old garment goes through JSON.
      item = WardrobeItem.fromJson({
        ...item.toJson(),
        'addedAt': addedAt.toUtc().toIso8601String(),
      });
    }
    await wardrobe.save(item);
    return item;
  }

  /// Logs a wear in the event log, at a local time.
  Future<void> wear(String id, DateTime at) => events.append(
    ItemWorn(id: EventId('seed-${_ids++}'), itemId: ItemId(id), occurredAt: at),
  );

  Future<void> open(
    WidgetTester tester, {
    required String location,
    Size size = const Size(400, 900),
    double textScale = 1,
    Appearance appearance = Appearance.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    app.read(appearanceProvider.notifier).state = appearance;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: app,
        child: WashingAdviceApp(initialLocation: location),
      ),
    );
    await tester.pumpAndSettle();
  }
}
