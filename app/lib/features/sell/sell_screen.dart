/// The Sell tab: the person's listings, as drafts, listed and sold.
///
/// Three sections in the order a listing lives them — being written, up for
/// sale, done — and a section with nothing in it is left out rather than shown
/// empty. The tab is a place to look at where things stand, so every card says
/// what the listing is asking and what Depop's fee leaves of it, and a listing
/// that has sat for a fortnight says so without being opened. Starting one is
/// the floating button, as adding a garment is on the Wardrobe, and it is
/// always there: the list is no reason to hide the way to make another.
///
/// Nothing here decides anything about a listing. The sums are the core's and
/// the actions are the controller's; this lays out what they say.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/status_message.dart';
import 'list/listing_card.dart';
import 'list/listing_clock.dart';
import 'list/listing_groups.dart';
import 'list/listing_money.dart';
import 'list/new_listing_sheet.dart';
import 'list/sell_empty_state.dart';

/// How far the list ends above the bottom edge, so that its last card can be
/// scrolled clear of the floating button.
///
/// The Wardrobe's figure, for the same reason: the button is 56 high and sits
/// 16 above the bottom of the body, and the rest is breathing room so the last
/// card is fully visible and not merely uncovered. Where the phone has taken
/// the bottom edge for itself — a home indicator — the Scaffold already lifts
/// the button, and the list's padding is added to that.
const double _floatingButtonClearance = 56 + 16 + 24;

class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Made here and not where it is declared: a listener built lazily is not
    // built until something asks for it, and nothing but `dispose` would.
    _lifecycle = AppLifecycleListener(onResume: _readTheClockAgain);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// A phone left with the app open for a few days comes back to a list that
  /// was drawn before them. How long ago a listing went up, and whether it is
  /// time to refresh, are read from the clock when the list is drawn, so it is
  /// drawn again when the app is.
  void _readTheClockAgain() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final listings = ref.watch(listingsProvider);
    final now = ref.watch(listingClockProvider)();

    return Scaffold(
      appBar: AppBar(title: const Text('Sell')),
      // Only once there is a list to add to. The empty state offers the same
      // two ways to start in its own buttons, and a floating one over them at
      // 320 wide covers the second.
      floatingActionButton: (listings.valueOrNull?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              // Its own tag: the Wardrobe's button is on the screen next door,
              // and two heroes sharing a tag collide when a screen is pushed
              // over both.
              heroTag: 'new-listing',
              onPressed: () => chooseHowToStartListing(context),
              icon: const Icon(Icons.add),
              label: const Text('New listing'),
            )
          : null,
      body: listings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // Shown, not swallowed: a Sell tab that read as empty because the
        // database would not open would invite somebody to start their listings
        // again.
        error: (error, _) => StatusMessage.failure(
          title: 'Could not load your listings',
          detail:
              'Something went wrong reading your listings. They are still on '
              'this device — try again, and if it keeps happening the detail '
              'below is what to report.',
          error: error,
        ),
        data: (all) => all.isEmpty
            ? const SellEmptyState()
            : _Listings(groups: ListingGroups.of(all), now: now),
      ),
    );
  }
}

class _Listings extends StatelessWidget {
  const _Listings({required this.groups, required this.now});

  final ListingGroups groups;
  final DateTime now;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: _floatingButtonClearance),
    children: [
      if (groups.drafts.isNotEmpty) ..._section('Drafts', groups.drafts),
      if (groups.listed.isNotEmpty) ..._section('Listed', groups.listed),
      if (groups.sold.isNotEmpty)
        ..._section('Sold', groups.sold, summary: groups.soldTotals.summary),
      const _FeeNote(),
    ],
  );

  List<Widget> _section(
    String title,
    List<Listing> listings, {
    String? summary,
  }) => [
    SectionLabel(title),
    if (summary != null) _Summary(summary),
    for (final listing in listings)
      Padding(
        // Keyed by the listing, so a card that moves between sections when its
        // status changes is the same card and not a neighbour's.
        key: ValueKey(listing.id.value),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ListingCard(listing: listing, now: now),
      ),
  ];
}

/// The line at the top of Sold: how many, and what they left.
class _Summary extends StatelessWidget {
  const _Summary(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Where "you get" comes from, and when it was last checked.
class _FeeNote extends StatelessWidget {
  const _FeeNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Text(
        feeNote(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
