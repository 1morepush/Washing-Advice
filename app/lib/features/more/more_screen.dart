/// The places that are not on the bar: Ask, Packing, Insights and Settings.
///
/// A list in words rather than four more icons, for the reason the drawer it
/// replaces gave: a feature with an unlabelled icon is a feature nobody finds.
/// Each opens over the bar, as its own screen with a Back arrow, and Back
/// returns here.
///
/// Ask is first. It had a seat on the bar until Sell took it, and of what is
/// left it is the one a person is most likely to come looking for.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/rinse_kit.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: const [
        GroupCard(
          children: [
            _Place(
              icon: Icons.chat_bubble_outline,
              title: 'Ask',
              subtitle: 'Questions about your clothes and their care',
              route: '/ask',
            ),
            _Place(
              icon: Icons.luggage_outlined,
              title: 'Packing',
              subtitle: 'What to take, from what you own',
              route: '/packing',
            ),
            _Place(
              icon: Icons.insights_outlined,
              title: 'Insights',
              subtitle: 'What your wardrobe is made of and how it is used',
              route: '/insights',
            ),
            _Place(
              icon: Icons.settings_outlined,
              title: 'Settings',
              subtitle: 'Machines, reminders, sync and appearance',
              route: '/settings',
            ),
          ],
        ),
      ],
    ),
  );
}

class _Place extends StatelessWidget {
  const _Place({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: context.rinse.tileBorderRadius,
        ),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: scheme.onPrimaryContainer),
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
      onTap: () => context.push(route),
    );
  }
}
