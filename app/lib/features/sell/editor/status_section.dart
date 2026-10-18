/// Where the listing has got to, and what to do next.
///
/// Depop cannot be told anything: it has no API, so the app does not post a
/// listing and does not learn that one sold. The person is the only one who
/// knows, and these buttons are how they say so. Each is a step they have
/// really taken, in the order they take them — open Depop and post it, come
/// back and say so, say when it sells and for how much, take the garment out
/// of the wardrobe — and the app keeps count: how long it has been up, whether
/// it is time to refresh it, what was made.
///
/// **Draft** is the listing before it is on Depop. **Listed** is up for sale.
/// **Sold** is finished, and shows what it fetched and what was left of that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../widgets/notice.dart';
import '../list/listing_when.dart';
import 'edit_session.dart';
import 'editor_text.dart';
import 'fields.dart';
import 'garment_sale.dart';
import 'price_links.dart';
import 'sold_price_dialog.dart';

/// Where Open Depop goes.
final Uri depopHome = Uri.parse('https://www.depop.com/');

class StatusSection extends ConsumerStatefulWidget {
  const StatusSection({
    required this.listing,
    required this.session,
    super.key,
  });

  final Listing listing;
  final ListingEditSession session;

  @override
  ConsumerState<StatusSection> createState() => _StatusSectionState();
}

class _StatusSectionState extends ConsumerState<StatusSection> {
  /// Whether a change of status is being made, so that a double tap does not
  /// make it twice.
  bool _changing = false;

  Future<void> _change(Future<void> Function() change) async {
    // Whatever is being typed is stored, not left in a box with the keyboard
    // up: the buttons below are the end of editing.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _changing = true);
    try {
      await change();
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _askWhatItSoldFor() async {
    final answer = await showSoldPriceDialog(
      context,
      asking: widget.listing.priceCents,
    );
    if (answer == null || !mounted) return;
    await _change(() => widget.session.markSold(priceCents: answer.cents));
  }

  Future<void> _backToDraft({required bool confirm}) async {
    if (confirm) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (_) => const _ConfirmBackToDraft(),
      );
      if (sure != true || !mounted) return;
    }
    await _change(widget.session.backToDraft);
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;

    return EditorSection(
      title: 'Status',
      children: switch (listing.status) {
        ListingStatus.draft => _draft(),
        ListingStatus.listed => _listed(context, listing),
        ListingStatus.sold => _finished(context, listing),
      },
    );
  }

  List<Widget> _draft() => [
    const _Stage('Draft', line: 'Not on Depop yet.'),
    const SizedBox(height: 4),
    const QuietText(
      'Paste the description into Depop, add the photos, and post it. Then '
      'come back and say so here.',
    ),
    const SizedBox(height: 16),
    _wide(
      OutlinedButton.icon(
        onPressed: () => openLink(context, ref, depopHome),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Open Depop'),
      ),
    ),
    const SizedBox(height: 12),
    _wide(
      FilledButton(
        onPressed: _changing ? null : () => _change(widget.session.markListed),
        child: const Text("I've posted it"),
      ),
    ),
  ];

  List<Widget> _listed(BuildContext context, Listing listing) {
    final now = DateTime.now();
    final onSale = listing.listedFor(now);

    return [
      _Stage(
        onSale == null ? 'Listed' : listedPhrase(onSale),
        line: 'Up on Depop, not sold yet.',
      ),
      if (listing.needsRefresh(now) && onSale != null) ...[
        const SizedBox(height: 12),
        Notice(
          icon: Icons.refresh,
          warning: true,
          text:
              "It's been up for ${onSale.inDays} days. Refreshing or "
              'relisting it on Depop puts it back in front of buyers.',
        ),
        const SizedBox(height: 12),
        _wide(
          FilledButton.tonal(
            onPressed: _changing
                ? null
                : () => _change(widget.session.markListed),
            child: const Text("I've refreshed it on Depop"),
          ),
        ),
      ],
      const SizedBox(height: 16),
      _wide(
        FilledButton(
          onPressed: _changing ? null : _askWhatItSoldFor,
          child: const Text('It sold'),
        ),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          style: inlineTextButton,
          onPressed: _changing ? null : () => _backToDraft(confirm: false),
          child: const Text('Back to draft'),
        ),
      ),
    ];
  }

  List<Widget> _finished(BuildContext context, Listing listing) {
    final theme = Theme.of(context);
    const fees = DepopFees.us;
    final price = listing.soldPriceCents;
    final soldAt = listing.soldAt?.toLocal();
    final took = listing.listedFor(DateTime.now());

    return [
      _Stage(
        price == null ? 'Sold' : 'Sold for ${formatUsd(price)}',
        line: price == null ? "The price wasn't recorded." : null,
      ),
      if (price != null) ...[
        const SizedBox(height: 8),
        Text(
          "You got ${formatUsd(fees.netCents(price))} after Depop's fees "
          '(${fees.label})',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
      if (soldAt != null) ...[
        const SizedBox(height: 4),
        QuietText(
          'Sold ${shortDate(soldAt)}'
          '${took == null ? '' : ' · listed for ${_days(took)}'}',
        ),
      ],
      GarmentSale(listing: listing, session: widget.session),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          style: inlineTextButton,
          onPressed: _changing ? null : () => _backToDraft(confirm: true),
          child: const Text('Back to draft'),
        ),
      ),
    ];
  }

  /// A button across the whole card: the one thing to do next.
  static Widget _wide(Widget button) =>
      SizedBox(width: double.infinity, child: button);

  /// `under a day`, `1 day`, `16 days`.
  static String _days(Duration duration) {
    final days = duration.inDays;
    if (days < 1) return 'under a day';
    return days == 1 ? '1 day' : '$days days';
  }
}

/// The stage a listing is at, as a heading with a line under it.
class _Stage extends StatelessWidget {
  const _Stage(this.stage, {this.line});

  final String stage;
  final String? line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stage,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (line case final String line) ...[
          const SizedBox(height: 2),
          Text(line, style: theme.textTheme.bodyLarge),
        ],
      ],
    );
  }
}

/// Asks before a sale is forgotten.
class _ConfirmBackToDraft extends StatelessWidget {
  const _ConfirmBackToDraft();

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Back to draft?'),
    content: const Text(
      'This forgets the sale and when the listing was posted. If you already '
      'marked the garment as sold in your wardrobe, that stays as it is.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text('Back to draft'),
      ),
    ],
  );
}
