/// Navigation between the app's top-level places.
///
/// A bottom bar of five, because the places someone moves between all day —
/// the wardrobe, the washing, what to wear, what is up for sale — belong under
/// a thumb, and a menu behind an icon hid every one of them. Ask, Packing,
/// Insights and Settings are used far less often and live one tap away under
/// More.
///
/// Each place keeps its own history: the shell is a `StatefulShellRoute`, so
/// switching away and back finds the screen, its stack and its scroll where
/// they were left, and tapping the place you are already in returns it to its
/// first screen.
///
/// Only screens that are *part of* a place sit inside the shell and show the
/// bar (the laundry's Worn Today, say). Anything that is a task of its own — a
/// garment, a listing being written, a scan, a stain, a pile photo, Ask,
/// Settings — is pushed over the whole shell and covers the bar, so the bar
/// never offers a way out of the middle of one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/wardrobe/wardrobe_screen.dart'
    show wardrobeSelectionProvider;
import 'rinse_kit.dart';

/// One place on the bar, in the order they appear.
enum AppDestination {
  wardrobe('Wardrobe', '/', Icons.checkroom_outlined, Icons.checkroom),
  laundry(
    'Laundry',
    '/laundry',
    Icons.local_laundry_service_outlined,
    Icons.local_laundry_service,
  ),
  outfits('Outfits', '/outfits', Icons.style_outlined, Icons.style),
  sell('Sell', '/sell', Icons.sell_outlined, Icons.sell),
  more('More', '/more', Icons.more_horiz, Icons.more_horiz);

  const AppDestination(this.label, this.route, this.icon, this.selectedIcon);

  final String label;
  final String route;
  final IconData icon;
  final IconData selectedIcon;
}

/// How far the bottom bar's labels follow the system text size.
const _maxBarTextScale = 1.05;

class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = shell.currentIndex;

    // While garments are being picked out the wardrobe takes over the bottom of
    // the screen with its own action, and a second bar under it would be two
    // rows of buttons about different things.
    final selecting =
        index == AppDestination.wardrobe.index &&
        ref.watch(wardrobeSelectionProvider).isNotEmpty;

    // Read here, above the Scaffold, where the keyboard's inset is still whole.
    // The bar goes while the keyboard is up: with the shell resizing for it, the
    // body ends at the top of the keys, and a bar left on screen would float on
    // them. The screens inside then see no inset of their own and lay out
    // against the real bottom edge, so a composer sits directly on the keyboard.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      // Back from inside a place pops within it first (the navigator under the
      // shell answers before this is asked). Out of ideas there, Back goes to
      // the first place, and only from the first place does it leave the app.
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: selecting || typing
            ? null
            : RinseNavBar(
                // A fifth of a 320 dp phone is room for "Wardrobe" at
                // about the normal type size and not beyond: the
                // label would break inside the word. The bar's labels stop
                // growing there (the rest of the app keeps going), as
                // Material's own guidance for a bottom bar has it.
                bar: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: _maxBarTextScale,
                  child: NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: (selected) => shell.goBranch(
                      selected,
                      // The place you are in: back to its first screen.
                      initialLocation: selected == index,
                    ),
                    destinations: [
                      for (final destination in AppDestination.values)
                        NavigationDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: destination.label,
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
