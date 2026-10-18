/// What the Sell list and the ways a listing starts need to run as the app does.
///
/// The whole app is built, with its address given and every outside thing
/// replaced: the repositories are in memory, the photographs are kept in memory,
/// the camera hands back what it is told to, the server is a fake that records
/// what it was asked, and the clock says what the test says it is. What is in
/// between — the router, the screens, the controller, the providers — is what
/// ships, which is the point of building it this way instead of pumping one
/// screen alone.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart' show rinseFontFamily;
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/sell/list/listing_clock.dart';
import 'package:washing_advice/main.dart';

import '../../support/recording_link_opener.dart';

/// The real typeface, for a test that is about whether text fits.
///
/// The test font draws every glyph a full em wide, which breaks any word on a
/// phone and says nothing about the app. Nunito is what ships.
Future<void> loadAppFont() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader(rinseFontFamily);
  for (final file in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/Nunito-$file.ttf'));
  }
  await loader.load();
}

/// A photograph that is a few letters, so that which one is which is readable.
ScanImage photoOf(String mark) => ScanImage(bytes: utf8.encode(mark));

/// What a photograph says it is, for a test that wants to know which went where.
String markOf(ScanImage image) => utf8.decode(image.bytes);

/// The server, as far as the Sell screens can tell.
///
/// Overrides the one call these screens make and records what it was asked. It
/// never answers from a network.
class FakeSellGateway extends AiGateway {
  FakeSellGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  /// What a description answers.
  ListingFacts facts = ListingFacts(
    title: 'Nike vintage crewneck sweatshirt grey',
    itemType: ItemType.sweatshirt,
    brand: Confident('Nike', confidence: 0.93, source: Provenance.aiInference),
    colors: const ['Grey'],
    material: '80% cotton, 20% polyester',
    sizeOnTag: Confident('M', confidence: 0.9, source: Provenance.aiInference),
    styleWords: const ['vintage', 'crewneck'],
    era: '90s',
    visibleFlaws: const ['small mark on the left cuff'],
    searchQueries: const SearchQueries(
      depop: 'Nike vintage crewneck sweatshirt grey',
      retail: 'Nike Club Fleece crew sweatshirt grey',
    ),
  );

  /// Thrown instead of answering, when set.
  Object? describeError;

  /// When set, a description waits for it: the server taking its time.
  Completer<void>? hold;

  final described =
      <({List<ScanImage> images, Map<String, Object?>? context})>[];

  @override
  Future<ListingFacts> describeListing(
    List<ScanImage> images, {
    Map<String, Object?>? context,
  }) async {
    described.add((images: images, context: context));
    await hold?.future;
    if (describeError case final Object error) throw error;
    return facts;
  }
}

/// A camera that hands back numbered photographs, or whatever it is told to.
class ScriptedCamera implements ImageCaptureSource {
  /// How many photographs [capture] has handed over.
  int taken = 0;

  /// What [pickMultiple] hands over.
  List<ScanImage> picks = [];

  /// Thrown by either call instead of answering, when set.
  CaptureFailure? failure;

  /// Whether the next [capture] is backed out of.
  bool backOut = false;

  @override
  Future<ScanImage?> capture() async {
    if (failure case final CaptureFailure failure) throw failure;
    if (backOut) {
      backOut = false;
      return null;
    }
    return photoOf('shot-${++taken}');
  }

  @override
  Future<List<ScanImage>> pickMultiple() async {
    if (failure case final CaptureFailure failure) throw failure;
    return picks;
  }
}

/// The app, built the way the test needs it.
class SellHarness {
  SellHarness._(this._preferences, this.now);

  /// A fresh app, whose clock reads [now] (the 17th of October, noon, UTC,
  /// unless it is told otherwise).
  static Future<SellHarness> create({DateTime? now}) async {
    SharedPreferences.setMockInitialValues({});
    return SellHarness._(
      await SharedPreferences.getInstance(),
      now ?? DateTime.utc(2026, 10, 17, 12),
    );
  }

  final SharedPreferences _preferences;

  final listings = InMemoryListingRepository();
  final wardrobe = InMemoryWardrobeRepository();
  final images = MemoryImageStore();
  final gateway = FakeSellGateway();
  final camera = ScriptedCamera();
  final links = RecordingLinkOpener();

  /// What the screens think the time is. Change it to move the clock.
  DateTime now;

  /// The providers, built on first use inside the test that wants them and
  /// torn down with it.
  late final ProviderContainer app = () {
    final built = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(SettingsStore(_preferences)),
        wardrobeRepositoryProvider.overrideWithValue(wardrobe),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        listingRepositoryProvider.overrideWithValue(listings),
        imageStoreProvider.overrideWithValue(images),
        aiGatewayProvider.overrideWithValue(gateway),
        imageCaptureProvider.overrideWithValue(camera),
        linkOpenerProvider.overrideWithValue(links),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'listing'),
        ),
        listingClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(built.dispose);
    return built;
  }();

  /// Opens the app at [location].
  ///
  /// [size] is a phone's, in logical pixels, and [textScale] the system's text
  /// size. Pumps until the first screen has settled, so it is not for a screen
  /// that animates for ever.
  Future<void> open(
    WidgetTester tester, {
    String location = '/sell',
    Size size = const Size(400, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: app,
        child: WashingAdviceApp(initialLocation: location),
      ),
    );
    await tester.pumpAndSettle();
  }
}
