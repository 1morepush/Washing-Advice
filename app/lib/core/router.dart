/// Navigation.
///
/// Routes are addressable by URL, which is not decoration: it makes the whole
/// app reachable from a browser, so screens can be driven and screenshotted in
/// CI without an emulator. `/item/abc` opens that item directly.
library;

import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../features/chat/chat_screen.dart';
import '../features/insights/insights_screen.dart';
import '../features/laundry/laundry_screen.dart';
import '../features/laundry/worn_today_screen.dart';
import '../features/more/more_screen.dart';
import '../features/outfits/outfits_screen.dart';
import '../features/packing/packing_screen.dart';
import '../features/pile/pile_screen.dart';
import '../features/scan/bulk_screen.dart';
import '../features/scan/care_tag_screen.dart';
import '../features/scan/retake_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/scan/spread_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stains/stain_screen.dart';
import '../features/wardrobe/edit_item_screen.dart';
import '../features/wardrobe/item_detail_screen.dart';
import '../features/wardrobe/mask_editor_screen.dart';
import '../features/wardrobe/wardrobe_screen.dart';
import '../widgets/app_shell.dart';

/// Builds the app's router.
///
/// Two kinds of destination. The five places on the bottom bar are the
/// branches of one `StatefulShellRoute`: each keeps its own stack, and Back
/// from them goes to the first place and then leaves the app. Everything else
/// — a garment, a scan, a stain, Packing, Insights, Settings — is a top-level
/// route reached with `push`, so it covers the bar and Back returns to where
/// the user was (see `back_navigation.dart`). What is a screen *of* a place,
/// rather than a task of its own, sits inside that place's branch and keeps
/// the bar: Worn Today under Laundry.
///
/// [initialLocation] is a parameter so a test can start on the screen it is
/// about, and so a future session restore can reopen where the user left off,
/// rather than every entry point having to navigate from the wardrobe.
GoRouter buildRouter({String initialLocation = '/'}) {
  // Without this, go_router leaves the browser address at whatever `go` last
  // set, however many screens have been pushed since — so after Wardrobe,
  // garment, stain the address still said `/`, and a reload, bookmark or
  // shared link of a pushed screen opened the wrong one. Set here, where
  // every router is built, because it is a process-wide flag that has to be
  // in place before the first one.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  return _router(initialLocation);
}

GoRouter _router(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(shell: shell),
      // In the order of the bar: `AppDestination` indexes these.
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const WardrobeScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/laundry',
              builder: (_, _) => const LaundryScreen(),
              routes: [
                // A child of the laundry screen rather than a sibling, so that
                // `go('/laundry/worn')` — which is how a tapped reminder
                // arrives — builds the laundry screen underneath and Back has
                // somewhere to go. From inside the app it is pushed, and the
                // stack is the same.
                GoRoute(
                  path: 'worn',
                  builder: (_, _) => const WornTodayScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/outfits', builder: (_, _) => const OutfitsScreen()),
            // The same screen opened on its Saved tab, so that tab has an
            // address a browser can be sent to. A sibling and not a child: a
            // child would be pushed over the Ideas screen it is a tab of.
            GoRoute(
              path: '/outfits/saved',
              builder: (_, _) =>
                  const OutfitsScreen(initialTab: OutfitsTab.saved),
            ),
            // The Stylist used to be a destination of its own. It is now
            // part of Ideas, so an old link lands there.
            GoRoute(path: '/outfits/stylist', redirect: (_, _) => '/outfits'),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/ask', builder: (_, _) => const ChatScreen()),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/more', builder: (_, _) => const MoreScreen()),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/item/:id',
      builder: (_, state) =>
          ItemDetailScreen(id: ItemId(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/item/:id/edit',
      builder: (_, state) =>
          EditItemScreen(id: ItemId(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/item/:id/retake',
      builder: (_, state) =>
          RetakeScreen(id: ItemId(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/item/:id/mask',
      builder: (_, state) =>
          MaskEditorScreen(id: ItemId(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/item/:id/stain',
      builder: (_, state) =>
          StainScreen(id: ItemId(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/item/:id/care-label',
      builder: (_, state) =>
          CareTagScreen(id: ItemId(state.pathParameters['id']!)),
    ),
    GoRoute(path: '/packing', builder: (_, _) => const PackingScreen()),
    GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen()),
    GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
    GoRoute(path: '/scan/bulk', builder: (_, _) => const BulkScanScreen()),
    GoRoute(path: '/scan/spread', builder: (_, _) => const SpreadScanScreen()),
    GoRoute(path: '/pile', builder: (_, _) => const PileScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);
