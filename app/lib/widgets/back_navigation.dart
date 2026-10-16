/// Going back, for screens that are reached by pushing.
///
/// Detail screens (a garment, a scan, a stain) sit on top of wherever the user
/// was, so Back — the app bar's arrow and Android's system gesture alike — is
/// simply a pop and returns to that place. The places on the bottom bar each
/// keep a stack of their own instead, and Back from one goes to the first
/// place and then leaves the app (see `app_shell.dart`).
///
/// The one case a pop cannot cover is a screen opened *directly*, with nothing
/// beneath it: a link to `/item/abc`, or a browser reload. [backLeading] and
/// [BackNavigation.backOr] send those to a parent the screen names.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

extension BackNavigation on BuildContext {
  /// Pops to where the user came from, or goes to [fallback] when this screen
  /// was opened directly and there is nothing to return to.
  void backOr(String fallback) {
    if (!Navigator.of(this).canPop()) return go(fallback);
    final router = GoRouter.maybeOf(this);
    router == null ? Navigator.of(this).pop() : router.pop();
  }
}

/// The app bar's `leading` for a pushed screen.
///
/// Null when there is somewhere to go back to, so the app bar draws its own
/// Back arrow and pops. Otherwise a button to [fallback], so a directly-opened
/// screen still has a way out. [onLeave] runs when that button is used; a pop
/// is covered by [LeaveScope].
Widget? backLeading(
  BuildContext context,
  String fallback, {
  VoidCallback? onLeave,
}) {
  if (Navigator.of(context).canPop()) return null;
  return BackButton(
    onPressed: () {
      onLeave?.call();
      context.go(fallback);
    },
  );
}

/// Runs [onLeave] whenever the screen is popped by any route: the Back arrow,
/// the system gesture, or a button that calls `pop`. For screens whose state
/// should not outlive a visit, which the old hand-written Back buttons cleared.
class LeaveScope extends StatelessWidget {
  const LeaveScope({required this.onLeave, required this.child, super.key});

  final VoidCallback onLeave;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) onLeave();
    },
    child: child,
  );
}
