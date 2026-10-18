/// The bottom bar: five places, each keeping its own history.
///
/// Replaces the drawer, and the questions are the ones a drawer never had to
/// answer. A drawer used `go`, so every move threw the previous screen away; a
/// bar that did the same would be a menu that happened to sit lower down. What
/// is pinned here is what makes it a set of places instead: leaving one and
/// coming back finds it as it was, tapping the one you are in starts it over,
/// and Back walks out in the order a person expects.
///
/// Sell has the seat Ask used to have. Ask moved into More, and the tests for
/// the two moves are here with the rest of what the bar promises.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/chat/chat_screen.dart';
import 'package:washing_advice/features/insights/insights_screen.dart';
import 'package:washing_advice/features/laundry/evening_nudge.dart';
import 'package:washing_advice/features/laundry/laundry_screen.dart';
import 'package:washing_advice/features/laundry/worn_today_screen.dart';
import 'package:washing_advice/features/more/more_screen.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';
import 'package:washing_advice/features/packing/packing_screen.dart';
import 'package:washing_advice/features/sell/listing_editor_screen.dart';
import 'package:washing_advice/features/sell/new_listing_screen.dart';
import 'package:washing_advice/features/sell/pick_garment_screen.dart';
import 'package:washing_advice/features/sell/sell_screen.dart';
import 'package:washing_advice/features/settings/settings_screen.dart';
import 'package:washing_advice/features/wardrobe/item_detail_screen.dart';
import 'package:washing_advice/features/wardrobe/wardrobe_screen.dart';
import 'package:washing_advice/main.dart';
import 'package:washing_advice/widgets/app_shell.dart';

import '../support/contrast.dart';
import '../support/fixtures.dart';
import '../support/recording_nudges.dart';

void main() {
  late RecordingNudges nudges;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    nudges = RecordingNudges();
    final repository = InMemoryWardrobeRepository();
    await repository.save(confidentItem(id: 'a', name: 'Blue jumper'));
    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          SettingsStore(await SharedPreferences.getInstance()),
        ),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
        // The Sell screens read the listings, and Sell itself is among the
        // places opened here. Lazily, so `container.exists` below still says
        // whether a screen reached for them: only the Sell screens may.
        listingRepositoryProvider.overrideWith(
          (ref) => InMemoryListingRepository(),
        ),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        nudgesProvider.overrideWithValue(nudges),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> open(
    WidgetTester tester, {
    String location = '/',
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: WashingAdviceApp(initialLocation: location),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A place on the bar. Found inside the bar because the same word is also a
  /// screen's title, and `find.text('Laundry')` is then two things.
  Finder place(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  Future<void> tapPlace(WidgetTester tester, String label) async {
    await tester.tap(place(label));
    await tester.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('the bar names five places, in order', (tester) async {
    await open(tester);

    final destinations = tester
        .widgetList<NavigationDestination>(find.byType(NavigationDestination))
        .map((d) => d.label)
        .toList();
    expect(destinations, ['Wardrobe', 'Laundry', 'Outfits', 'Sell', 'More']);
    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.byType(Drawer), findsNothing);
  });

  testWidgets('Sell has the seat Ask had, and Ask is not on the bar', (
    tester,
  ) async {
    await open(tester);

    expect(place('Sell'), findsOneWidget);
    expect(place('Ask'), findsNothing);
    // In the order the bar names them: the fourth place, before More.
    expect(AppDestination.sell.index, 3);
    expect(AppDestination.values.map((d) => d.label), isNot(contains('Ask')));
  });

  group('every place the drawer had is still reachable', () {
    testWidgets('Wardrobe, Laundry, Outfits and Sell from the bar', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(WardrobeScreen), findsOneWidget);

      await tapPlace(tester, 'Laundry');
      expect(find.byType(LaundryScreen), findsOneWidget);

      await tapPlace(tester, 'Outfits');
      expect(find.byType(OutfitsScreen), findsOneWidget);

      await tapPlace(tester, 'Sell');
      expect(find.byType(SellScreen), findsOneWidget);

      await tapPlace(tester, 'Wardrobe');
      expect(find.byType(WardrobeScreen), findsOneWidget);
    });

    testWidgets('Ask, Packing, Insights and Settings from More', (
      tester,
    ) async {
      await open(tester);
      await tapPlace(tester, 'More');
      expect(find.byType(MoreScreen), findsOneWidget);

      for (final (title, screen) in [
        ('Ask', ChatScreen),
        ('Packing', PackingScreen),
        ('Insights', InsightsScreen),
        ('Settings', SettingsScreen),
      ]) {
        await tester.tap(find.widgetWithText(ListTile, title));
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget, reason: title);

        // And back to the list, not out of the app.
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.byType(MoreScreen), findsOneWidget, reason: title);
      }
    });
  });

  group('each place keeps its own history', () {
    testWidgets('switching away and back finds the screen it was on', (
      tester,
    ) async {
      await open(tester, location: '/laundry');
      await tester.tap(find.text('What did you wear today?'));
      await tester.pumpAndSettle();
      expect(find.byType(WornTodayScreen), findsOneWidget);

      await tapPlace(tester, 'Outfits');
      expect(find.byType(WornTodayScreen), findsNothing);

      await tapPlace(tester, 'Laundry');
      expect(find.byType(WornTodayScreen), findsOneWidget);
    });

    testWidgets('and what was typed, which a rebuilt screen would lose', (
      tester,
    ) async {
      // The stylist's note is held by the screen and not by a provider, so
      // only a screen that is kept rather than rebuilt still has it.
      await open(tester, location: '/outfits');
      final note = find.widgetWithText(
        TextField,
        'Anything to add? (optional)',
      );
      await tester.scrollUntilVisible(
        note,
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.vertical,
            )
            .first,
      );
      await tester.enterText(note, 'Can I tumble wool?');
      await tester.pump();

      await tapPlace(tester, 'Wardrobe');
      await tapPlace(tester, 'Outfits');

      expect(find.text('Can I tumble wool?'), findsOneWidget);
    });

    testWidgets('tapping the place you are in returns it to its first screen', (
      tester,
    ) async {
      await open(tester, location: '/laundry');
      await tester.tap(find.text('What did you wear today?'));
      await tester.pumpAndSettle();
      expect(find.byType(WornTodayScreen), findsOneWidget);

      await tapPlace(tester, 'Laundry');

      expect(find.byType(WornTodayScreen), findsNothing);
      expect(find.byType(LaundryScreen), findsOneWidget);
    });
  });

  group('Back', () {
    var left = 0;

    setUp(() {
      left = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'SystemNavigator.pop') left++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
    });

    testWidgets('pops inside a place, then goes to the first, then leaves', (
      tester,
    ) async {
      await open(tester);
      await tapPlace(tester, 'Laundry');
      await tester.tap(find.text('What did you wear today?'));
      await tester.pumpAndSettle();

      await systemBack(tester);
      expect(find.byType(WornTodayScreen), findsNothing);
      expect(find.byType(LaundryScreen), findsOneWidget);

      await systemBack(tester);
      expect(find.byType(WardrobeScreen), findsOneWidget);
      expect(left, 0, reason: 'the app must not close on the way to the first');

      await systemBack(tester);
      expect(left, 1);
    });

    testWidgets('from a pushed screen returns to the place it came from', (
      tester,
    ) async {
      await open(tester);
      await tapPlace(tester, 'Outfits');
      await tapPlace(tester, 'More');
      await tester.tap(find.widgetWithText(ListTile, 'Settings'));
      await tester.pumpAndSettle();

      await systemBack(tester);
      expect(find.byType(MoreScreen), findsOneWidget);

      // Not Outfits, and not the wardrobe: More is where it was left.
      await systemBack(tester);
      expect(find.byType(WardrobeScreen), findsOneWidget);
    });
  });

  group('the bar and the screens over it', () {
    testWidgets('the evening reminder opens Worn Today with the bar present', (
      tester,
    ) async {
      await open(tester, location: '/sell');

      nudges.tapped.add(eveningNudge.route);
      await tester.pumpAndSettle();

      expect(find.byType(WornTodayScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      // The place it belongs to is the one lit.
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );

      await systemBack(tester);
      expect(find.byType(LaundryScreen), findsOneWidget);
    });

    testWidgets('a garment covers the bar, and Back brings it back', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Blue jumper'));
      await tester.pumpAndSettle();
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('the bar steps aside while garments are being selected', (
      tester,
    ) async {
      await open(tester);
      container.read(wardrobeSelectionProvider.notifier).state = {
        const ItemId('a'),
      };
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);

      container.read(wardrobeSelectionProvider.notifier).state = {};
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('Sell is a place', () {
    testWidgets('/sell shows the Sell screen on the bar, with Sell lit', (
      tester,
    ) async {
      await open(tester, location: '/sell');

      expect(find.byType(SellScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        AppDestination.sell.index,
      );
      // A place on the bar has no Back arrow: Back from it goes to the first
      // place, like the others.
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('and no other screen has read the listings', (tester) async {
      // The listings are Drift-backed unless overridden, and this app has only
      // its wardrobe overridden: a screen that read them would open a real
      // database, as every test that pumps the app would then be doing. Only
      // the Sell screens, and the controller when it is asked, are to.
      await open(tester);

      // The wardrobe, and a garment on it.
      await tester.tap(find.text('Blue jumper'));
      await tester.pumpAndSettle();
      expect(find.byType(ItemDetailScreen), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // The other places, and everything More opens.
      await tapPlace(tester, 'Laundry');
      await tapPlace(tester, 'Outfits');
      await tapPlace(tester, 'More');
      for (final title in ['Ask', 'Packing', 'Insights', 'Settings']) {
        await tester.tap(find.widgetWithText(ListTile, title));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      }

      expect(container.exists(listingRepositoryProvider), isFalse);
      expect(container.exists(listingsProvider), isFalse);
      expect(container.exists(databaseProvider), isFalse);
    });

    testWidgets('Back from Sell goes to the first place', (tester) async {
      await open(tester);
      await tapPlace(tester, 'Sell');

      await systemBack(tester);

      expect(find.byType(WardrobeScreen), findsOneWidget);
    });
  });

  group('Ask is opened from More', () {
    testWidgets('More lists Ask first, and opens it over the bar', (
      tester,
    ) async {
      await open(tester);
      await tapPlace(tester, 'More');

      final titles = tester
          .widgetList<ListTile>(
            find.descendant(
              of: find.byType(MoreScreen),
              matching: find.byType(ListTile),
            ),
          )
          .map((tile) => (tile.title! as Text).data);
      expect(titles, ['Ask', 'Packing', 'Insights', 'Settings']);

      await tester.tap(find.widgetWithText(ListTile, 'Ask'));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('and Back from it returns to More, with the bar', (
      tester,
    ) async {
      await open(tester);
      await tapPlace(tester, 'More');
      await tester.tap(find.widgetWithText(ListTile, 'Ask'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(MoreScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);

      // The system gesture does the same.
      await tester.tap(find.widgetWithText(ListTile, 'Ask'));
      await tester.pumpAndSettle();
      await systemBack(tester);
      expect(find.byType(MoreScreen), findsOneWidget);
    });

    testWidgets('an old /ask link still opens the chat, with a way back', (
      tester,
    ) async {
      await open(tester, location: '/ask');

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      // Nothing beneath it to pop to, so the arrow goes to More.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(MoreScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('the listing screens cover the bar', () {
    /// Opens [location] directly, as a link or a reload would, then follows
    /// the arrow out. Both are a screen's own business, and a screen with no
    /// way out of a direct visit is a dead end.
    Future<void> opensAndLeaves(
      WidgetTester tester, {
      required String location,
      required Type screen,
      required Type parent,
    }) async {
      await open(tester, location: location);

      expect(find.byType(screen), findsOneWidget, reason: location);
      expect(find.byType(NavigationBar), findsNothing, reason: location);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(parent), findsOneWidget, reason: location);
    }

    testWidgets('/sell/new', (tester) async {
      await opensAndLeaves(
        tester,
        location: '/sell/new',
        screen: NewListingScreen,
        parent: SellScreen,
      );
    });

    testWidgets('/sell/from-wardrobe', (tester) async {
      await opensAndLeaves(
        tester,
        location: '/sell/from-wardrobe',
        screen: PickGarmentScreen,
        parent: SellScreen,
      );
    });

    testWidgets('/listing/:id', (tester) async {
      await opensAndLeaves(
        tester,
        location: '/listing/draft-1',
        screen: ListingEditorScreen,
        parent: SellScreen,
      );
    });

    testWidgets('an old address for starting from a garment is the picker', (
      tester,
    ) async {
      await open(tester, location: '/sell/from-wardrobe/demo-jumper');

      expect(find.byType(PickGarmentScreen), findsOneWidget);
    });

    testWidgets('the listing in the address reaches its screen', (
      tester,
    ) async {
      await open(tester, location: '/listing/draft-7');

      expect(
        tester.widget<ListingEditorScreen>(find.byType(ListingEditorScreen)).id,
        const ListingId('draft-7'),
      );
    });

    testWidgets('and Back from one opened over the bar returns to it', (
      tester,
    ) async {
      await open(tester, location: '/sell');
      final context = tester.element(find.byType(SellScreen));
      GoRouter.of(context).push('/listing/draft-1');
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('layout', () {
    for (final (width, scale) in [(320.0, 1.0), (320.0, 2.0), (400.0, 3.0)]) {
      testWidgets('${width.toInt()} dp wide at ${scale}x text', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await open(tester, size: Size(width, 640));

        // Every label is on screen, and none of them overflowed: a failed
        // layout is an exception in the frame, which the test fails on.
        expect(tester.takeException(), isNull);
        for (final label in [
          'Wardrobe',
          'Laundry',
          'Outfits',
          'Sell',
          'More',
        ]) {
          expect(place(label), findsOneWidget);
          final box = tester.getRect(place(label));
          expect(box.left, greaterThanOrEqualTo(0), reason: label);
          expect(box.right, lessThanOrEqualTo(width), reason: label);
        }
      });
    }
  });

  group('true black', () {
    testWidgets('the selected place can be told from the black around it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = AppTheme.amoled();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            bottomNavigationBar: NavigationBar(
              selectedIndex: 0,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.checkroom), label: 'A'),
                NavigationDestination(icon: Icon(Icons.style), label: 'B'),
              ],
            ),
          ),
        ),
      );

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      final context = tester.element(find.byType(NavigationBar));
      final indicator =
          bar.indicatorColor ??
          NavigationBarTheme.of(context).indicatorColor ??
          theme.colorScheme.secondaryContainer;
      expect(
        NavigationBarTheme.of(context).indicatorColor,
        isNotNull,
        reason:
            'true black sets its own pill rather than inheriting Material\'s',
      );
      final ground = NavigationBarTheme.of(context).backgroundColor!;

      // The bar is black. The pill is the design's soft wash, a shade above
      // it, so the selected place is carried by the glyph and label instead:
      // the icon reads on the pill and on the bar at 4.5:1, and the label is
      // full ink where the others are muted.
      expect(ground, theme.colorScheme.surface);
      expect(indicator, isNot(ground));
      final nav = NavigationBarTheme.of(context);
      final icon = nav.iconTheme!.resolve({WidgetState.selected})!.color!;
      expect(contrastBetween(icon, indicator), greaterThanOrEqualTo(4.5));
      expect(contrastBetween(icon, ground), greaterThanOrEqualTo(4.5));
      expect(
        nav.labelTextStyle!.resolve({WidgetState.selected})!.color,
        isNot(nav.labelTextStyle!.resolve({})!.color),
      );
    });
  });
}
