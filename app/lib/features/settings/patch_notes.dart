/// What changed, and when.
///
/// Bundled with the build rather than fetched, which is the point of it sitting
/// next to "Check for updates": these notes ship *inside* the app, so the
/// newest date here is the date of the app actually running. If it is older
/// than expected, the update has not landed and the button beside it is the
/// fix. Notes fetched from a server would describe a version the phone might
/// not have, which is exactly the confusion this is meant to resolve.
///
/// Every entry is a change set that reached `main`, and the date is the day it
/// did. The version numbers were assigned to that history after the fact rather
/// than being minted at the time — the minor digit steps once per shipped set,
/// so they order correctly and mean something, but they are a label on the past
/// and not a record kept as it happened. Worth knowing before anyone treats
/// them as a build identifier.
///
/// The names are jokes. A release nobody can refer to is a release nobody
/// mentions, and "the Separation Anxiety one" is a great deal easier to say
/// than "0.6.0".
library;

import 'package:flutter/material.dart';

/// One shipped change set.
final class Release {
  const Release({
    required this.version,
    required this.name,
    required this.date,
    required this.headline,
    required this.changes,
  });

  /// e.g. `0.6.0`. Ordered, and a test keeps it that way.
  final String version;

  /// The joke. Laundry, always.
  final String name;

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
    version: '0.12.0',
    name: 'Second Rinse',
    date: DateTime.utc(2026, 8, 15),
    headline: 'Scanning a label again adds to it',
    changes: [
      'Scanning a care label a second time no longer throws away the first '
          'reading. Anything the new photo shows wins; anything it does not '
          'show is kept from before — so photographing the back of a tag weeks '
          'later no longer loses the wash symbols off the front.',
      'It tells you which parts were kept rather than freshly read, and offers '
          'to use only the new scan if the old one had it wrong.',
      'A merged label is only as trusted as the weaker of the two readings, '
          'since some of what it says came from the older one.',
    ],
  ),
  Release(
    version: '0.11.0',
    name: 'The Full Monty',
    date: DateTime.utc(2026, 8, 15),
    headline: 'Photograph the back too',
    changes: [
      'Fixed: long garment names were cut off at the top of their own page. '
          '"Black koi graphic tee" became "Black koi graphic t…", losing the '
          'word that told it apart from every other black tee. The name now '
          'wraps instead, and gets more room when your text size is larger.',
      'Take as many photos of a garment as it needs before it is identified. A '
          'plain navy tee and one with a big print across the back look the '
          'same from the front — to you and to the app — so now you can turn '
          'it around first.',
      'Say what each photo shows: front, back, a detail, a logo, a brand tag. '
          'It guesses front then back then detail, and you can change any of '
          'them with a tap.',
      'The print on the back now feeds into the name and description, so two '
          'similar shirts are easier to tell apart in your wardrobe.',
      'Fixed: a fourth photo used to overwrite the third instead of being '
          'saved beside it.',
    ],
  ),
  Release(
    version: '0.10.0',
    name: 'Both Sides Now',
    date: DateTime.utc(2026, 8, 15),
    headline: 'Care labels with two sides, in any language',
    changes: [
      'Take as many photos of a care label as it needs. Labels are often '
          'printed on both sides, or carry on onto a second tag behind the '
          'first — add each one and they are read together as a single label '
          'instead of one side quietly going missing.',
      'Nothing is read until you say so, so you can turn the label over first. '
          'A shot that came out blurred can be dropped without starting again.',
      'Labels in other languages now work properly. The wash symbols are the '
          'same in every country, so a French or Japanese label reads just as '
          'well as an English one — the app tells you which language it was, '
          'and shows the wording exactly as printed rather than translating it '
          'at you.',
    ],
  ),
  Release(
    version: '0.9.0',
    name: 'Spin Cycle',
    date: DateTime.utc(2026, 8, 14),
    headline: 'Stain advice appears as it is written',
    changes: [
      'Asking what to do about a spill no longer makes you wait for the whole '
          'answer. The first step shows up as soon as it is ready, and the '
          'rest fill in underneath — which matters, because the first step is '
          'the one to do first and stains do not wait.',
      'Every step is still checked against your garment before you see it. '
          'That happens step by step now rather than all at once, so nothing '
          'reaches the screen unchecked.',
      'If the connection drops halfway, it says so instead of showing you half '
          'a treatment as though it were the whole thing.',
    ],
  ),
  Release(
    version: '0.8.0',
    name: 'Basket Case',
    date: DateTime.utc(2026, 8, 14),
    headline: 'Three more ways into the wash',
    changes: [
      'Long press anything in the wardrobe to start picking clothes out, then '
          'tap the rest and send the lot to the basket in one go. A full '
          'basket one garment at a time was never going to happen.',
      'Reporting wear now offers to put the garment in the wash while you are '
          'there. Off unless you tick it — plenty of wear is spotted on a '
          'hanger.',
      'Photograph a pile and the garments it recognizes can go straight to the '
          'basket, so the plan is still there tomorrow when the machine is '
          'free. The ones it could not place are left alone.',
      'A garment with no color recorded now says so where it matters: the '
          'color row offers to set it, and the laundry section admits that '
          '"darks" was an assumption rather than a look at the garment.',
    ],
  ),
  Release(
    version: '0.7.0',
    name: 'Out, Damned Spot II',
    date: DateTime.utc(2026, 8, 13),
    headline: 'Ask what to do about a spill',
    changes: [
      'Pick a garment, say what was spilled on it — and add a photo if you are '
          'not sure what the mark is — and you get an ordered treatment, with '
          'the reason for each step.',
      'The advice is checked against that garment before you see it. A step '
          'the care label forbids is removed and the app says which '
          'instruction it broke, so a wool jumper is never told to take a hot '
          'bleach soak.',
      'When nothing is safe to try at home, it says so rather than inventing '
          'something gentler that will not work.',
      'Finishing a treatment records it in the garment history and puts it '
          'straight in the wash.',
      'The load it ends up in then tells you to check that mark before '
          'anything goes near heat — drying sets whatever did not come out.',
    ],
  ),
  Release(
    version: '0.6.0',
    name: 'Separation Anxiety',
    date: DateTime.utc(2026, 8, 12),
    headline: 'Four piles, and a plan for the dirty one',
    changes: [
      'Every garment is now in one of four piles — clean, to wash, washing or '
          'drying — and there is a Laundry screen to move things between them.',
      'The to-wash pile works out which clothes can go in together and which '
          'cannot, what temperature and cycle each load needs, and tells you '
          'why. Darks with darks, the new red tee on its own.',
      'Starting a load moves it into the machine and records the wash, so your '
          'garment history knows what it was actually washed at.',
    ],
  ),
  Release(
    version: '0.5.0',
    name: 'Color Run',
    date: DateTime.utc(2026, 8, 11),
    headline: 'Set the color yourself',
    changes: [
      'Edit an item and you can now say what color it actually is — pick from '
          'swatches or type a hex code. A camera reads navy as black under '
          'warm indoor light more often than it should, and the color decides '
          'which load the garment goes in.',
      'Name more than one and the first is the one it mostly is, which is what '
          'keeps a white tee with a navy print out of the whites.',
      'The app now writes in American English throughout. The u in colour ran '
          'in the wash.',
    ],
  ),
  Release(
    version: '0.4.0',
    name: 'Out, Damned Spot',
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
    version: '0.3.0',
    name: "Tag, You're It",
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
    version: '0.2.0',
    name: 'Know Your Dial',
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
    version: '0.1.0',
    name: 'First Rinse',
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
          // Wrapped rather than a Row: at a large text scale a version, a name
          // and a date side by side do not fit a narrow phone.
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text(
                '${release.version} · ${release.name}',
                style: theme.textTheme.labelLarge,
              ),
              Text(
                release.formattedDate,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // The name is the memorable part and the headline is the useful one,
          // so both are kept: "the Separation Anxiety one" is how someone
          // refers to a release, and "four piles" is what it did.
          Text(release.headline, style: theme.textTheme.bodyMedium),
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
