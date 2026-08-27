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
/// did. The numbers up to 0.7.0 were assigned to that history after the fact;
/// from 0.8.0 they have been minted as each set shipped, which is why the
/// dates from there on are the real ones. Not a build identifier either way.
///
/// ## Which digit moves
///
/// Decided by what the *user* gets, not by how much code changed. A one-line
/// fix and a rewritten subsystem are the same size to somebody holding a
/// phone; what differs is whether the app can now do something it could not
/// do before.
///
/// * **Minor — 0.13.0.** A new capability. The app does something it could not
///   do at all before: a new screen, a new action, a new question it can
///   answer. However small the diff.
/// * **Patch — 0.12.1.** The app finally does what it already claimed to. A
///   repair to shipped behaviour, with no new capability. Named like any other
///   release, because a fix worth shipping is worth being able to refer to.
/// * **No entry at all.** Nothing a user could notice — a refactor, a test, a
///   server change that leaves every answer identical. A notes screen that
///   listed those would bury the entries that matter.
///
/// Two rules settle the awkward cases:
///
/// * A fix that travels *with* a feature rides along in that feature's minor
///   release rather than earning a patch of its own — 0.11.0 carries two.
///   Only a repair shipping on its own becomes a patch.
/// * A patch never rewrites the release it repairs. 0.12.0 shipped and was
///   found wanting the same day; folding the fixes back into its bullets would
///   quietly change what that release *was*. These notes are a record of what
///   reached `main`, not a tidy summary of it.
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
    version: '0.19.0',
    name: 'Close Crop',
    date: DateTime.utc(2026, 8, 21),
    headline: 'Frame a photo on the garment before it is read',
    changes: [
      'Tap any photo while you are adding a garment and drag the corners in '
          'so the garment fills the frame. Works when adding one garment or a '
          'whole pile.',
      'This is the fix for a bad cutout rather than a tidier picture. The '
          'background is worked out from the colours at the edges of the '
          'photo, so a shot with half a patterned duvet in it gives the app '
          'the wrong idea about what the background even is. Crop that away '
          'and it is being asked a much easier question.',
      'It also helps the app identify the garment, for the plainer reason '
          'that half a bedroom in shot is half a bedroom it has to ignore.',
      'Nothing is cropped unless you drag something, and Reset puts the frame '
          'back. A cropped photo is still a photo of the same size on your '
          'phone bill — it is saved as a JPEG rather than being blown up into '
          'something several times larger.',
    ],
  ),
  Release(
    version: '0.18.1',
    name: 'Button Up',
    date: DateTime.utc(2026, 8, 17),
    headline: 'The add buttons say what they do',
    changes: [
      'Fixed: the new "add several garments" button showed up blank in the '
          'corner of the wardrobe, under a second round button that was not '
          'much clearer. Neither said what it did without holding it down.',
      'There is one add button now. Tap it and it asks whether you are adding '
          'one garment or a pile, in words, with a line about what each is '
          'for. Both flows are unchanged.',
    ],
  ),
  Release(
    version: '0.18.0',
    name: 'Whole Load',
    date: DateTime.utc(2026, 8, 16),
    headline: 'Photograph a whole pile, then submit it in one go',
    changes: [
      'New on the wardrobe: Add several garments. Photograph one, tap "Next '
          'garment", photograph the next, and keep going through the pile. '
          'Nothing is sent while you work, so there is no waiting between '
          'garments.',
      'Submit the lot and put the phone down. It works through them one at a '
          'time and tells you how far it has got — "9 of 40" — rather than '
          'spinning at you.',
      'Photograph each garment\'s care label along with it and both are read '
          'together, so a whole wardrobe arrives with real washing '
          'instructions rather than guesses.',
      'You still see everything before it is saved, but once for the whole '
          'batch instead of once per garment. All ticked to start with: untick '
          'anything you do not want, fix a name that came out wrong, then save '
          'them all.',
      'One garment failing does not lose the rest. The ones that could not be '
          'read are listed by number so you know exactly which few to do '
          'again.',
    ],
  ),
  Release(
    version: '0.17.0',
    name: 'One Trip',
    date: DateTime.utc(2026, 8, 16),
    headline: 'Photograph the care label with the garment',
    changes: [
      'Photograph the care label while you are adding a garment and mark it '
          '"Care label" — it is read in the same pass. No more saving the '
          'garment, opening it again, and starting a second scanner for a tag '
          'sewn into the thing you were already holding.',
      'What the label says wins over what the fabric suggested, so the '
          'washing comes from the manufacturer rather than a guess. The '
          'review screen says which of the two you are looking at.',
      'A label that comes out blurred no longer costs you the garment. It is '
          'identified and saved as usual, the screen says the label could not '
          'be read, and you can scan it again whenever you like.',
      'Scanning a label on its own from the item screen still works exactly '
          'as before.',
    ],
  ),
  Release(
    version: '0.16.0',
    name: 'Something Blue',
    date: DateTime.utc(2026, 8, 16),
    headline: 'It can tell you what you are missing',
    changes: [
      'Tick "Also say what I am missing" before asking the Stylist for ideas, '
          'and it will name pieces you do not own that would go with the '
          'clothes you do — the dark blue jeans your light graphic tee has '
          'been asking for.',
      'Every suggestion says which of your clothes it goes with, by name, and '
          'why. A piece with nothing of yours to wear it with is dropped, '
          'because that is a shopping list rather than advice.',
      'It will not suggest something already hanging up. If it names a colour '
          'you have in that garment already, the suggestion is dropped before '
          'you see it.',
      'No brands, no shops, no prices, and no links. It describes the garment '
          'and stops there — where to find one, or whether to bother, is not '
          'the app\'s business.',
      'Off unless you ask. The Stylist works exactly as it did if you leave '
          'the box alone.',
    ],
  ),
  Release(
    version: '0.15.0',
    name: 'Wear and Tear',
    date: DateTime.utc(2026, 8, 16),
    headline: 'Photograph a garment to check it for wear',
    changes: [
      'New under the three dots on any garment: Check for wear. Photograph '
          'the places things actually wear — cuffs, elbows, underarms, the '
          'seat — and it tells you what it can see.',
      'Nothing is recorded until you say so. Each thing it finds is a '
          'separate question with its own yes and no, and it tells you where '
          'to look so you can check it against the garment in your hand.',
      'When accepting something would change how the garment is washed, it '
          'says so before you tap, not after.',
      '"Nothing to report" is the usual answer and it says that plainly. If '
          'it saw something it was not sure enough about, it tells you that '
          'too rather than pretending it saw nothing.',
      'Reporting wear by hand still works exactly as before. This is the '
          'quick way, not the replacement.',
    ],
  ),
  Release(
    version: '0.14.0',
    name: 'Second Opinion',
    date: DateTime.utc(2026, 8, 16),
    headline: 'Ask for outfit ideas',
    changes: [
      'A new Stylist tab on Outfits. It reads what your wardrobe is made of '
          'and suggests things to wear, noticing what the app never could: '
          'pattern against pattern, proportion, how dressy something reads.',
      'It tells you why, in its own words, so you can disagree with it. This '
          'is taste rather than arithmetic, and the Suggested tab beside it '
          'still works the way it always did.',
      'Add a note first if today is unusual — "it will be cold", "I am '
          'meeting a client".',
      'It only ever suggests clothes you own and could actually put on this '
          'morning. Anything it names that is in the wash, or that it made '
          'up, is dropped before you see it, and the tab says how many.',
      'Nothing happens until you ask. Your photographs are never sent — only '
          'the facts already on each garment.',
    ],
  ),
  Release(
    version: '0.13.0',
    name: 'Sock Drawer',
    date: DateTime.utc(2026, 8, 16),
    headline: 'Identical garments share a row',
    changes: [
      'Six identical socks are one row now, not six — they were crowding out '
          'the garment you were actually looking for. Tap to open the group '
          'up, tap again for one of them.',
      'The count still says six, because six is what you own. Picking a group '
          'picks every copy, so sending them to the wash does not leave five '
          'in the drawer.',
      'Only garments the app is genuinely sure are the same get collapsed: '
          'same type, brand, size, fabric and colour. Two things it knows '
          'little about are not thereby the same thing.',
      'Not what you want? Turn it off under the three dots in the wardrobe.',
    ],
  ),
  Release(
    version: '0.12.1',
    name: 'Spot Clean',
    date: DateTime.utc(2026, 8, 15),
    headline: 'Two fixes from the first day of Second Rinse',
    changes: [
      'Fixed: tidying a cutout saved correctly, but the garment page kept '
          'showing the old picture until you restarted the app. The edit was '
          'never lost — only the picture was stale.',
      'Take a garment back out of any laundry pile. Something dropped in the '
          'basket by mistake had no way out at all, and a jumper that came out '
          'of the dryer still damp can now go back in the basket.',
    ],
  ),
  Release(
    version: '0.12.0',
    name: 'Second Rinse',
    date: DateTime.utc(2026, 8, 15),
    headline: 'Scanning a label again adds to it',
    changes: [
      'When you tidy a cutout by hand, you can now hand it back to the app to '
          'finish the edges. It can only take more away, never put back what '
          'you removed, and if its answer would wipe out most of the garment '
          'it is refused and your own tidying is kept.',
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
