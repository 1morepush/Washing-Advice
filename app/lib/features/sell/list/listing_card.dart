/// One listing on the Sell tab: what it is, what it is asking and what is left.
///
/// A card opens the listing, and says everything a seller scanning the tab
/// wants without opening it. The figure that matters is the second one — what
/// Depop's fee leaves — so the asking price never appears without it. A listing
/// that has sat long enough to refresh says so on the card itself, in a panel of
/// its own, because advice somebody has to open the listing to find is advice
/// that is not given.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/notice.dart';
import '../../../widgets/rinse_kit.dart';
import 'listing_money.dart';
import 'listing_thumb.dart';
import 'listing_when.dart';

class ListingCard extends StatelessWidget {
  const ListingCard({required this.listing, required this.now, super.key});

  final Listing listing;

  /// The moment the card is read against, for how long ago and for the nudge.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = listing.title.trim();

    return RinseCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/listing/${listing.id.value}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListingThumb(listing: listing),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Said in words and in the quiet colour, not left blank: a
                    // draft that was started and never named is still a draft
                    // somebody has to find.
                    Text(
                      title.isEmpty ? 'Untitled draft' : title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: title.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._details(context),
                  ],
                ),
              ),
            ],
          ),
          if (listing.listedFor(now) case final Duration listed
              when listing.needsRefresh(now)) ...[
            const SizedBox(height: 12),
            // Amber, as advice is, and not the error colour: nothing is wrong
            // with a listing that has been up a fortnight. It is a prompt to
            // try the two things that work.
            Notice(
              icon: Icons.autorenew,
              warning: true,
              text:
                  'Listed ${weeksLabel(listed)} — refresh it: drop the price a '
                  'little or relist it so it shows as new.',
            ),
          ],
        ],
      ),
    );
  }

  /// The lines under the title, by where the listing has got to.
  List<Widget> _details(BuildContext context) {
    final theme = Theme.of(context);

    Widget money(String text) => Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    Widget quiet(String text) => Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    final asking = listing.priceCents;
    final sold = listing.soldPriceCents;

    return switch (listing.status) {
      ListingStatus.draft => [
        asking == null ? quiet('No price yet') : money(askingLine(asking)),
      ],
      ListingStatus.listed => [
        asking == null ? quiet('No price yet') : money(askingLine(asking)),
        if (listing.listedAt case final DateTime at)
          quiet('Listed ${timeAgo(now.difference(at))}'),
      ],
      ListingStatus.sold => [
        sold == null ? quiet('No sale price recorded') : money(soldLine(sold)),
        if (listing.soldAt case final DateTime at)
          quiet('Sold ${shortDate(at)}'),
      ],
    };
  }
}
