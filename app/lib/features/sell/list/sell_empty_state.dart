/// What the Sell tab says before there is anything on it.
///
/// It has to explain the tab and not only the lack: a seller opening it for the
/// first time has no listings, and "Nothing here yet" would leave them to guess
/// what it is for. So it says what the app does, and what it will not — it posts
/// nothing, because Depop has no way to be told to. Both ways in are buttons
/// here, though the New listing button is on the screen as well, since the first
/// listing should not wait on someone finding a button in the corner.
///
/// Scrolls, because at a large text size on a small phone this is taller than
/// the screen, and a centred column that cannot scroll would cut off the second
/// button.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../widgets/rinse_kit.dart';
import 'new_listing_sheet.dart';

class SellEmptyState extends StatelessWidget {
  const SellEmptyState({super.key});

  static const _edge = 32.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.colorScheme.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(_edge, _edge, _edge, _edge),
        child: ConstrainedBox(
          // Centred when it fits, scrolling when it does not.
          constraints: BoxConstraints(
            minHeight: math.max(0.0, constraints.maxHeight - 2 * _edge),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const IconBadge(Icons.sell_outlined, size: 96),
                const SizedBox(height: 20),
                Text(
                  'Sell what you no longer wear',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'It writes the Depop description, suggests a price from '
                  'Depop and shop prices, and keeps track of what has sold and '
                  'what Depop\'s fees leave you. Nothing is posted for you: '
                  'you copy the listing into Depop.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: quiet),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push(newFromPhotosRoute),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Photograph something to sell'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.push(newFromWardrobeRoute),
                    icon: const Icon(Icons.checkroom_outlined),
                    label: const Text('Choose from my wardrobe'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
