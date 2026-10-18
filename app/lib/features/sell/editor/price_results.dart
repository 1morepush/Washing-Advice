/// What a price search found, said by how the search went.
///
/// The server answers with a status even when it finds nothing, because "no
/// key", "no allowance left", "no answer" and "looked and found nothing" are
/// four different things to a person deciding what to ask, and a screen that
/// shows the same empty space for all of them lets them take the wrong one.
/// Each has its own sentence, and each points the same way: the links below,
/// which work whatever the server does.
///
/// Every comparable is a link. A price on a screen is a claim, and the tap
/// that opens the page it came from is how the person checks it. Beside it is
/// what the server could tell of it — sold or not, how it is described, how
/// alike — so that two prices of $30 are not taken for the same evidence when
/// one is something that sold and the other is something that hasn't.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/theme.dart';
import '../../../widgets/notice.dart';
import 'editor_text.dart';
import 'fields.dart';
import 'price_links.dart';

class PriceResults extends StatelessWidget {
  const PriceResults({required this.search, this.failedNew, super.key});

  /// The listing's last search, or null if it has never looked.
  final PriceSearch? search;

  /// The status of a newer search that was not kept, because [search] found
  /// prices and the newer one did not.
  final PriceSearchStatus? failedNew;

  @override
  Widget build(BuildContext context) {
    final found = search;
    if (found == null) {
      return const QuietText(
        'Not looked up yet. Look up prices to see what similar things have '
        'sold and sell for.',
      );
    }

    return switch (found.status) {
      PriceSearchStatus.ok => _Found(search: found, failedNew: failedNew),
      PriceSearchStatus.notConfigured => const Notice(
        icon: Icons.info_outline,
        text:
            "Live price search isn't set up on this server yet. It needs a "
            'free Tavily key on the server (see the README). Meanwhile, check '
            'the links below.',
      ),
      PriceSearchStatus.quotaExceeded => const Notice(
        icon: Icons.hourglass_empty,
        warning: true,
        text:
            'The free price-search allowance is used up for now. Check the '
            'links below, or try again later.',
      ),
      PriceSearchStatus.unavailable => const Notice(
        icon: Icons.cloud_off_outlined,
        warning: true,
        text: "The price search didn't answer. Try again.",
      ),
    };
  }
}

/// A search that ran: when, and what it found.
class _Found extends StatelessWidget {
  const _Found({required this.search, required this.failedNew});

  final PriceSearch search;
  final PriceSearchStatus? failedNew;

  @override
  Widget build(BuildContext context) {
    final checked = search.searchedAt?.toLocal();
    final nothing = search.comparables.isEmpty && search.retail.isEmpty;
    final excluded = excludedPhrase(
      notUsd: search.excluded.notUsd,
      unverifiedPrice: search.excluded.unverifiedPrice,
      notComparable: search.excluded.notComparable,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failedNew != null) ...[
          Notice(
            icon: Icons.cloud_off_outlined,
            warning: true,
            text:
                "The new search didn't answer — showing prices checked "
                '${checked == null ? 'earlier' : MaterialLocalizations.of(context).formatShortDate(checked)}.',
          ),
          const SizedBox(height: 12),
        ],
        QuietText(
          checked == null
              ? 'Prices checked'
              : 'Prices checked ${agoPhrase(checked, DateTime.now())}',
        ),
        const SizedBox(height: 12),
        if (nothing)
          // Looked, and nothing usable came back: not the same as not looking.
          const Notice(
            icon: Icons.search_off_outlined,
            text:
                'The search found nothing usable for these phrases. Try '
                'different words, or check the links below.',
          )
        else ...[
          const SubHeading('On Depop'),
          const SizedBox(height: 8),
          if (search.comparables.isEmpty)
            const QuietText('No usable Depop listings.')
          else
            for (final comparable in search.comparables)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ComparableTile(comparable: comparable),
              ),
          const SizedBox(height: 8),
          const SubHeading('New in shops'),
          const SizedBox(height: 8),
          if (search.retail.isEmpty)
            const QuietText('No usable shop prices.')
          else
            for (final reference in search.retail)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RetailTile(reference: reference),
              ),
        ],
        if (search.excluded.total > 0) ...[
          const SizedBox(height: 4),
          QuietText('Not shown: $excluded'),
        ],
      ],
    );
  }
}

/// A listing on Depop for the same or a similar item.
class _ComparableTile extends ConsumerWidget {
  const _ComparableTile({required this.comparable});

  final SaleComparable comparable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sold = switch (comparable.sold) {
      true => 'Sold',
      false => 'For sale',
      null => 'Status unknown',
    };

    return _LinkTile(
      title: comparable.title,
      cents: comparable.priceCents,
      tags: [
        _Tag(sold, strong: comparable.sold == true),
        _Tag(
          comparable.match == ComparableMatch.same ? 'Same item' : 'Similar',
          strong: comparable.match == ComparableMatch.same,
        ),
        if (comparable.condition case final String condition) _Tag(condition),
      ],
      why: comparable.why,
      onTap: () => openLink(context, ref, comparable.url),
    );
  }
}

/// What the same or a similar item costs new, in a shop.
class _RetailTile extends ConsumerWidget {
  const _RetailTile({required this.reference});

  final RetailReference reference;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _LinkTile(
    title: reference.title,
    cents: reference.priceCents,
    tags: [
      _Tag(
        reference.match == ComparableMatch.same ? 'Same item' : 'Similar',
        strong: reference.match == ComparableMatch.same,
      ),
      if (reference.seller case final String seller) _Tag(seller),
    ],
    onTap: () => openLink(context, ref, reference.url),
  );
}

/// A title, a price and some tags, that opens the page they came from.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.title,
    required this.cents,
    required this.tags,
    required this.onTap,
    this.why,
  });

  final String title;
  final int cents;
  final List<Widget> tags;
  final String? why;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = context.rinse.tileBorderRadius;

    final heading = Text(
      title,
      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    final price = Text(
      formatUsd(cents),
      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    );
    // Beside each other, the title is left with what the price does not take,
    // which at large text is a column a word wide. Then the price goes first,
    // on a line of its own, and the title has the card.
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.3;

    return Semantics(
      link: true,
      hint: 'Opens the page this came from',
      child: Material(
        color: context.rinse.well,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (large) ...[
                  price,
                  const SizedBox(height: 2),
                  heading,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: heading),
                      const SizedBox(width: 12),
                      price,
                    ],
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: tags),
                if (why case final String why) ...[
                  const SizedBox(height: 8),
                  QuietText(why),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A short fact about a comparable, in a pill: Sold, Similar, Used - Good.
///
/// The fact is in its words, and [strong] only decides how loudly: the two
/// that weigh most in a price, a sale and the same product, are filled.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(
          side: strong
              ? BorderSide.none
              : BorderSide(color: scheme.outlineVariant),
        ),
        color: strong ? scheme.primaryContainer : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: strong ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
