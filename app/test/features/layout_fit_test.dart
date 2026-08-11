/// Whether the text actually fits on a phone.
///
/// Two things make this different from an ordinary widget test.
///
/// The surface is 320dp wide — the narrowest phone still in use — rather than
/// the 800dp test default, which is wider than any handset and hides exactly
/// the bug this file exists to catch: a `Text` sitting unflexed in a `Row`
/// next to something that already fills the width.
///
/// And the real font is loaded. `flutter_test`'s default font draws every
/// glyph as a square of the font size, so a string measures roughly twice its
/// true width and screens that fit perfectly well are reported as
/// overflowing. Liberation Sans is what this app actually renders with in a
/// browser — which is what the installed PWA is — so loading it is what makes
/// a failure here mean a failure on the phone.
///
/// A `RenderFlex` overflow is reported through `FlutterError`, so
/// `expect(takeException(), isNull)` after a pump is the whole assertion.
/// These are tests rather than screenshots because an overflow is invisible
/// in a release build, and a release build is what ships.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/insights/insights_screen.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';
import 'package:washing_advice/features/packing/packing_screen.dart';
import 'package:washing_advice/features/settings/settings_screen.dart';
import 'package:washing_advice/features/wardrobe/edit_item_screen.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';
import 'package:washing_advice/features/wardrobe/wardrobe_screen.dart';

import '../support/fixtures.dart';

/// The narrowest phone worth supporting, made tall enough that nothing is
/// below the fold.
///
/// The height is not any device's: these screens are lazy lists, so at a real
/// 568dp the widgets further down are never built and an overflow in them
/// cannot be seen. Stretching the surface vertically builds all of them at
/// the width that actually matters.
const _narrow = Size(320, 4000);

void main() {
  late InMemoryWardrobeRepository repository;
  late ThemeData theme;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Liberation Sans')
          ..addFont(rootBundle.load('assets/fonts/LiberationSans-Regular.ttf')))
        .load();

    final base = AppTheme.light();
    theme = base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: 'Liberation Sans'),
    );
  });

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'White cotton tee'),
      confidentItem(id: 'tee-2', name: 'Grey marl tee'),
      confidentItem(id: 'jeans', name: 'Selvedge jeans', type: ItemType.jeans),
      confidentItem(id: 'chinos', name: 'Stone chinos', type: ItemType.chinos),
      confidentItem(id: 'socks', name: 'Black socks', type: ItemType.socks),
      confidentItem(id: 'pants', name: 'Grey shorts', type: ItemType.underwear),
      confidentItem(
        id: 'trainers',
        name: 'White trainers',
        type: ItemType.sneakers,
      ),
      confidentItem(
        id: 'jacket',
        name: 'Olive field jacket',
        type: ItemType.jacket,
      ),
    ]);
  });

  /// Larger-than-default system text.
  ///
  /// 1.5 is ordinary rather than exotic — iOS's Larger Text slider passes it
  /// well before its accessibility sizes begin — and it is the setting that
  /// turns a row with no slack in it into a row that overflows. Every screen
  /// below is expected to survive it.
  const enlarged = TextScaler.linear(1.5);

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    List<Override> overrides = const [],
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = _narrow;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          outfitRepositoryProvider.overrideWithValue(
            InMemoryOutfitRepository(),
          ),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'fit'),
          ),
          washerBrandProvider.overrideWith((ref) => null),
          dryerBrandProvider.overrideWith((ref) => null),
          customWasherProvider.overrideWith((ref) => null),
          customDryerProvider.overrideWith((ref) => null),
          ...overrides,
        ],
        child: MaterialApp(
          theme: theme,
          home: screen,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the packing list fits when a trip covers every occasion', (
    tester,
  ) async {
    // The case that overflowed. The per-category reason for footwear is "For "
    // plus every selected occasion joined with " and ", so all six produce a
    // line several times wider than a phone — and it sat in a `Row` with
    // nothing flexible around it.
    await pump(
      tester,
      const PackingScreen(),
      overrides: [
        tripSpecProvider.overrideWith(
          (ref) => const TripSpec(days: 14, occasions: {...Occasion.values}),
        ),
      ],
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the packing list fits for an ordinary trip', (tester) async {
    await pump(tester, const PackingScreen());

    expect(tester.takeException(), isNull);
  });

  testWidgets('the packing list fits with larger text', (tester) async {
    await pump(tester, const PackingScreen(), textScaler: enlarged);

    expect(tester.takeException(), isNull);
  });

  testWidgets('insights fit', (tester) async {
    await pump(tester, const InsightsScreen());

    expect(tester.takeException(), isNull);
  });

  testWidgets('insights fit with larger text', (tester) async {
    await pump(tester, const InsightsScreen(), textScaler: enlarged);

    expect(tester.takeException(), isNull);
  });

  testWidgets('outfit suggestions fit', (tester) async {
    await pump(tester, const OutfitsScreen());

    expect(tester.takeException(), isNull);
  });

  testWidgets('outfit suggestions fit with larger text', (tester) async {
    await pump(tester, const OutfitsScreen(), textScaler: enlarged);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the wardrobe grid fits', (tester) async {
    await pump(tester, const WardrobeScreen());

    expect(tester.takeException(), isNull);
  });

  testWidgets('the wardrobe list fits', (tester) async {
    await pump(
      tester,
      const WardrobeScreen(),
      overrides: [
        wardrobeViewProvider.overrideWith((ref) => WardrobeView.list),
      ],
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('the wardrobe list fits with larger text', (tester) async {
    await pump(
      tester,
      const WardrobeScreen(),
      overrides: [
        wardrobeViewProvider.overrideWith((ref) => WardrobeView.list),
      ],
      textScaler: enlarged,
    );

    expect(tester.takeException(), isNull);
  });

  group('one garment', () {
    /// The most fact-dense screen in the app, and the one most likely to be
    /// read on a phone held in one hand at a machine. Given a garment that
    /// states everything it can — a scanned label with warnings, a price, a
    /// size, a long name — every row has something in it.
    Future<void> pumpDetail(
      WidgetTester tester, {
      TextScaler textScaler = TextScaler.noScaling,
    }) async {
      final base = confidentItem(
        id: 'loaded',
        name: 'Charcoal merino crew-neck jumper',
        type: ItemType.sweater,
        composition: const {
          Fiber.wool: 70,
          Fiber.polyester: 25,
          Fiber.nylon: 5,
        },
        purchase: PurchaseInfo(
          priceMinorUnits: 12999,
          currencyCode: 'EUR',
          purchasedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final labelled = base.copyWith(
        brand: Confident.fromUser('Uniqlo'),
        sizeLabel: 'XL',
        careLabel: Confident(
          const CareConstraint(
            method: WashMethod.hand,
            maxTempC: 30,
            doNotDryClean: true,
            warnings: {
              CareWarning.washInsideOut,
              CareWarning.washWithLikeColours,
              CareWarning.doNotIronDecoration,
            },
          ),
          confidence: 0.95,
          source: Provenance.tagScan,
        ),
      );
      await repository.save(
        labelled.copyWith(care: const CareResolver().forItem(labelled).profile),
      );

      await pump(
        tester,
        const ItemDetailScreen(id: ItemId('loaded')),
        overrides: [imageStoreProvider.overrideWithValue(MemoryImageStore())],
        textScaler: textScaler,
      );
    }

    testWidgets('the detail screen fits', (tester) async {
      await pumpDetail(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the detail screen fits with larger text', (tester) async {
      await pumpDetail(tester, textScaler: enlarged);

      expect(tester.takeException(), isNull);
    });

    testWidgets('the edit screen fits', (tester) async {
      await pump(
        tester,
        const EditItemScreen(id: ItemId('jeans')),
        overrides: [imageStoreProvider.overrideWithValue(MemoryImageStore())],
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('the edit screen fits with larger text', (tester) async {
      await pump(
        tester,
        const EditItemScreen(id: ItemId('jeans')),
        overrides: [imageStoreProvider.overrideWithValue(MemoryImageStore())],
        textScaler: enlarged,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('settings', () {
    Future<void> pumpSettings(
      WidgetTester tester, {
      TextScaler textScaler = TextScaler.noScaling,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsStore(await SharedPreferences.getInstance());

      await pump(
        tester,
        const SettingsScreen(),
        overrides: [
          settingsStoreProvider.overrideWithValue(settings),
          // The section is only built on web, which is what the installed app
          // is — so it has to be measured, not skipped.
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
        ],
        textScaler: textScaler,
      );
    }

    testWidgets('settings fit', (tester) async {
      await pumpSettings(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('settings fit with larger text', (tester) async {
      await pumpSettings(tester, textScaler: enlarged);

      expect(tester.takeException(), isNull);
    });
  });
}
