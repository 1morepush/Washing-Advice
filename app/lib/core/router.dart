/// Navigation.
///
/// Routes are addressable by URL, which is not decoration: it makes the whole
/// app reachable from a browser, so screens can be driven and screenshotted in
/// CI without an emulator. `/item/abc` opens that item directly.
library;

import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../features/insights/insights_screen.dart';
import '../features/laundry/laundry_screen.dart';
import '../features/outfits/outfits_screen.dart';
import '../features/packing/packing_screen.dart';
import '../features/pile/pile_screen.dart';
import '../features/scan/care_tag_screen.dart';
import '../features/scan/retake_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/stains/stain_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/wardrobe/edit_item_screen.dart';
import '../features/wardrobe/item_detail_screen.dart';
import '../features/wardrobe/mask_editor_screen.dart';
import '../features/wardrobe/wardrobe_screen.dart';

/// Builds the app's router.
///
/// [initialLocation] is a parameter so a test can start on the screen it is
/// about, and so a future session restore can reopen where the user left off,
/// rather than every entry point having to navigate from the wardrobe.
GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', builder: (_, _) => const WardrobeScreen()),
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
    GoRoute(path: '/laundry', builder: (_, _) => const LaundryScreen()),
    GoRoute(path: '/outfits', builder: (_, _) => const OutfitsScreen()),
    GoRoute(
      path: '/outfits/saved',
      builder: (_, _) => const OutfitsScreen(initialTab: 1),
    ),
    GoRoute(path: '/packing', builder: (_, _) => const PackingScreen()),
    GoRoute(path: '/insights', builder: (_, _) => const InsightsScreen()),
    GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
    GoRoute(path: '/pile', builder: (_, _) => const PileScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);
