/// What changed, and when.
///
/// Bundled with the build rather than fetched, which is the point of it sitting
/// next to "Check for updates": these notes ship *inside* the app, so the
/// newest date here is the date of the app actually running. If it is older
/// than expected, the update has not landed and the button beside it is the
/// fix. Notes fetched from a server would describe a version the phone might
/// not have, which is exactly the confusion this is meant to resolve.
///
/// Dated rather than numbered because this project has no release numbering to
/// be honest about — every entry below is a change set that reached `main`, and
/// the date is the day it did.
library;

import 'package:flutter/material.dart';

/// One shipped change set.
final class Release {
  const Release({
    required this.date,
    required this.headline,
    required this.changes,
  });

  final DateTime date;

  /// One line naming the change, for people who will not read the bullets.
  final String headline;

  /// What changed, in the words of someone using the app rather than writing
  /// it — "the app no longer forgets" beats "fixed provider invalidation".
  final List<String> changes;

  /// e.g. `11 August 2026`.
  String get formattedDate =>
      '${date.day} ${_months[date.month - 1]} '
      '${date.year}';
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Newest first. A test enforces the ordering, because an entry appended to
/// the bottom out of habit would be silently buried.
final patchNotes = <Release>[
  Release(
    date: DateTime.utc(2026, 8, 11),
    headline: 'Set the color yourself',
    changes: [
      'Edit an item and you can now say what color it actually is — pick from '
          'swatches or type a hex code. A camera reads navy as black under '
          'warm indoor light more often than it should, and the color decides '
          'which load the garment goes in.',
      'Name more than one and the first is the one it mostly is, which is what '
          'keeps a white tee with a navy print out of the whites.',
      'The app now writes in American English throughout.',
    ],
  ),
  Release(
    date: DateTime.utc(2026, 8, 11),
    headline: 'Two ways to fix a bad cutout',
    changes: [
      'If the background removal took part of the garment with it, you can '
          'now tidy it with your finger. Remove rubs out what it left behind; '
          'Restore paints the garment back.',
      'If the photo itself was the problem, New photo takes another and works '
          'out what the garment is again. Anything you set by hand is kept, '
          'and your old photo is not thrown away.',
      'A scanned label that says "wash cold" now reads "Machine wash cold, up '
          'to 30°C" instead of dropping the word.',
      'Long fabric lists, care summaries and buttons no longer run off the '
          'edge of a narrow phone or at large text sizes.',
      'When something genuinely fails, screens say what could not be done '
          'instead of showing a raw error.',
    ],
  ),
  Release(
    date: DateTime.utc(2026, 8, 10),
    headline: 'Care labels are read in full',
    changes: [
      'Scanning a label now applies its dry-cleaning symbol, its warnings '
          '(including "do not iron the print") and the fabric printed on it — '
          'not just washing and drying.',
      'The scan reaches the item screen straight away instead of showing the '
          'old values until the app was reopened.',
      'The label photo is kept, so the instructions can be re-read without '
          'digging the garment back out.',
      'The prompt to scan a label goes away once a label has been scanned.',
    ],
  ),
  Release(
    date: DateTime.utc(2026, 8, 8),
    headline: 'Your own machines, and getting updates',
    changes: [
      'Name your washer and dryer by brand and model, and the app names the '
          'program actually printed on your dial.',
      'Check for updates, in Settings, gets past a home-screen app that is '
          'showing an old version.',
      'The white strip above the app on iPhone is gone.',
    ],
  ),
  Release(
    date: DateTime.utc(2026, 8, 7),
    headline: 'First version',
    changes: [
      'Photograph a garment to add it, photograph a pile to get a wash plan, '
          'and scan care labels to be sure rather than to guess.',
      'Outfits, packing lists, and what your wardrobe is actually costing you '
          'per wear.',
    ],
  ),
];

/// The notes, with everything but the newest entry folded away.
class PatchNotes extends StatelessWidget {
  const PatchNotes({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final [latest, ...earlier] = patchNotes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What\'s new', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'These notes come with the app, so this is the version you are '
          'running. If the newest date looks old, the update has not arrived '
          'yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _Entry(release: latest),
        if (earlier.isNotEmpty)
          Theme(
            // The default divider draws a line above and below every expansion
            // tile, which reads as a section break in the middle of one.
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              title: Text('Earlier changes', style: theme.textTheme.bodyMedium),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final release in earlier) _Entry(release: release),
              ],
            ),
          ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wrapped rather than a Row: at a large text scale a headline and a
          // date side by side do not fit a narrow phone.
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(release.headline, style: theme.textTheme.labelLarge),
              Text(
                release.formattedDate,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final change in release.changes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: theme.textTheme.bodySmall),
                  // Unflexed, this is the classic overflow: a long sentence in
                  // a Row beside a bullet that has already taken its width.
                  Expanded(
                    child: Text(
                      change,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
