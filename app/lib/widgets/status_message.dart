/// The full-screen message a list shows when it has nothing to list.
///
/// Two shapes, and the difference matters. An *empty* state is not a problem —
/// a new wardrobe is empty and saying so cheerfully is correct. A *failure*
/// is: something the user cannot see is broken, and their next move depends on
/// knowing which.
///
/// [StatusMessage.failure] exists because six screens used to render
/// `Center(child: Text('$error'))` — a raw Dart exception, in the middle of an
/// otherwise finished app. `DriftRemoteException: ...` tells a user nothing
/// they can act on and tells them the app is broken in a way a sentence would
/// not. The wardrobe screen had always done this properly; everything else had
/// not, and the difference was invisible until something actually failed.
///
/// The exception is kept, below the sentence and in a quieter style. It is
/// useless to most people and the only useful thing in the world to whoever
/// has to work out what happened, so it is present without being the headline.
library;

import 'package:flutter/material.dart';

class StatusMessage extends StatelessWidget {
  const StatusMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
    this.technical,
    super.key,
  });

  /// A failure, phrased for a person, with the raw error kept underneath.
  ///
  /// [title] should name what could not be done rather than what went wrong
  /// internally — "Could not load your outfits", not "Stream error".
  factory StatusMessage.failure({
    required String title,
    required Object error,
    String detail =
        'Something went wrong reading your wardrobe. It is still on this '
        'device — try again, and if it keeps happening the detail below is '
        'what to report.',
    Widget? action,
  }) => StatusMessage(
    icon: Icons.error_outline,
    title: title,
    detail: detail,
    action: action,
    technical: '$error',
  );

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  /// The underlying error, shown small and last.
  final String? technical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action case final Widget action) ...[
              const SizedBox(height: 16),
              action,
            ],
            if (technical case final String technical) ...[
              const SizedBox(height: 24),
              Text(
                technical,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
