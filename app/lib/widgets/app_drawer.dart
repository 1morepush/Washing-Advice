/// Navigation between the app's top-level places.
///
/// A drawer rather than more icons in the app bar. The wardrobe's bar already
/// carries a view toggle, a filter with a badge and a search field; adding
/// three more destinations to it would leave everything unlabelled and
/// competing. A drawer names each destination in words, which is what makes a
/// feature discoverable at all — an unlabelled icon for "packing" is a feature
/// nobody finds.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// One destination, in the order they appear.
enum AppDestination {
  wardrobe('Wardrobe', '/', Icons.checkroom_outlined, Icons.checkroom),
  laundry(
    'Laundry',
    '/laundry',
    Icons.local_laundry_service_outlined,
    Icons.local_laundry_service,
  ),
  outfits('Outfits', '/outfits', Icons.style_outlined, Icons.style),
  packing('Packing', '/packing', Icons.luggage_outlined, Icons.luggage),
  insights('Insights', '/insights', Icons.insights_outlined, Icons.insights),
  // Above settings rather than below it: this is a thing you use, and the
  // bottom of a drawer is where the things you configure once live.
  ask('Ask', '/ask', Icons.chat_bubble_outline, Icons.chat_bubble),
  settings('Settings', '/settings', Icons.settings_outlined, Icons.settings);

  const AppDestination(this.label, this.route, this.icon, this.selectedIcon);

  final String label;
  final String route;
  final IconData icon;
  final IconData selectedIcon;
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({required this.current, super.key});

  final AppDestination current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NavigationDrawer(
      selectedIndex: AppDestination.values.indexOf(current),
      onDestinationSelected: (index) {
        final destination = AppDestination.values[index];
        Navigator.of(context).pop();
        if (destination != current) context.go(destination.route);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Washing Advice', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Your wardrobe, and what to do with it',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (final destination in AppDestination.values)
          NavigationDrawerDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: Text(destination.label),
          ),
      ],
    );
  }
}
