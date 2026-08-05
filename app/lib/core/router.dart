/// Navigation.
///
/// Routes are addressable by URL, which is not decoration: it makes the whole
/// app reachable from a browser, so screens can be driven and screenshotted in
/// CI without an emulator. `/item/abc` opens that item directly.
library;

import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/wardrobe/item_detail_screen.dart';
import '../features/wardrobe/wardrobe_screen.dart';

GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const WardrobeScreen()),
    GoRoute(
      path: '/item/:id',
      builder: (_, state) =>
          ItemDetailScreen(id: ItemId(state.pathParameters['id']!)),
    ),
    GoRoute(path: '/scan', builder: (_, _) => const ScanScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
  ],
);
