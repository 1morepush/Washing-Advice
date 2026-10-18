/// The price: the heart of what the Sell tab is for.
///
/// Four things happen here, in the order a person does them.
///
/// 1. **Look up** what the same or similar things sell for on Depop and cost
///    new in shops. The two phrases that are searched are in boxes first,
///    because the reading of a photograph is a guess at the brand and a typo
///    is cheaper to fix before a search than after it.
/// 2. **Check** what was found, by following any of it, and by the three
///    searches that are offered whatever the server does.
/// 3. **Add** what the person saw for themselves, which the search could not.
/// 4. **Choose**: the core suggests a price and gives every reason, and the
///    person types the one they will ask, with what is left after Depop's fees
///    under it.
///
/// Looking up prices calls out to a server that may be asleep, may have no
/// key, or may have used the month's free searches, and none of those is an
/// error. They come back as a status, are stored with the listing, and each
/// has a sentence of its own (see `price_results.dart`). What *is* an error is
/// not reaching the server at all, and that is said here, under the button, in
/// the words the connection gave.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/providers.dart';
import '../../../data/api/ai_gateway.dart';
import '../../../widgets/notice.dart';
import 'edit_session.dart';
import 'fields.dart';
import 'price_links.dart';
import 'price_results.dart';
import 'price_suggestion.dart';
import 'typed_prices.dart';

class PriceSection extends ConsumerStatefulWidget {
  const PriceSection({required this.listing, required this.session, super.key});

  final Listing listing;
  final ListingEditSession session;

  @override
  ConsumerState<PriceSection> createState() => _PriceSectionState();
}

class _PriceSectionState extends ConsumerState<PriceSection> {
  bool _looking = false;

  /// Whether the look-up has been going long enough to explain.
  ///
  /// A free-tier server stops itself when idle and takes tens of seconds to
  /// come back. That is normal, but a spinner cannot say so, and a wait with no
  /// reason given reads as a hang.
  bool _waking = false;
  Timer? _wakingTimer;

  /// Why the last look-up got nowhere, when it did not reach the server.
  String? _problem;

  /// What the last look-up came back with, when the prices from an earlier one
  /// were kept in its place.
  PriceSearchStatus? _failedNew;

  @override
  void dispose() {
    _wakingTimer?.cancel();
    super.dispose();
  }

  Future<void> _lookUp() async {
    setState(() {
      _looking = true;
      _waking = false;
      _problem = null;
      _failedNew = null;
    });
    _wakingTimer?.cancel();
    _wakingTimer = Timer(wakingAfter, () {
      if (mounted) setState(() => _waking = true);
    });

    try {
      final lookup = await widget.session.lookUpPrices();
      if (mounted) setState(() => _failedNew = lookup.failedWith);
    } on ScanFailure catch (failure) {
      if (mounted) setState(() => _problem = failure.message);
    } finally {
      _wakingTimer?.cancel();
      if (mounted) {
        setState(() {
          _looking = false;
          _waking = false;
        });
      }
    }
  }

  /// Writes one of the two phrases, keeping the other as it stands.
  ///
  /// Once either has been written, both are the person's: they stop following
  /// the title and the rest of the listing, which they do until then.
  Listing _withPhrase(Listing listing, {String? depop, String? retail}) {
    final current = listing.editedQueries ?? listing.searchQueries;
    return listing.copyWith(
      editedQueries: SearchQueries(
        depop: depop ?? current?.depop ?? '',
        retail: retail ?? current?.retail ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final session = widget.session;

    final itemId = listing.itemId;
    final garment = itemId == null
        ? null
        : ref.watch(itemProvider(itemId)).valueOrNull;
    final suggestion = suggestionFor(listing, paidCents: paidCentsOf(garment));

    // What the boxes show is what is searched, so these are read off the same
    // value they are: the person's own phrases first, else the ones the
    // listing would use.
    final phrases = listing.editedQueries ?? listing.searchQueries;
    final hasTitle = listing.title.trim().length >= SearchQueries.minLength;
    final hasPhrases = phrases != null && phrases.isSearchable;
    final why = !hasTitle
        ? 'Add a title first. The search uses it.'
        : !hasPhrases
        ? 'Each search phrase needs at least ${SearchQueries.minLength} '
              'letters.'
        : null;

    const rule = Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Divider(height: 1),
    );

    return EditorSection(
      title: 'Price',
      intro:
          'Look up what similar things sell for, check it, then choose what '
          'to ask.',
      children: [
        EditorTextField(
          key: const ValueKey('search-depop'),
          value: phrases?.depop ?? '',
          label: 'Search Depop for',
          minLines: 1,
          maxLines: 3,
          inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
          textInputAction: TextInputAction.next,
          onChanged: (text) =>
              session.edit((listing) => _withPhrase(listing, depop: text)),
        ),
        const SizedBox(height: 16),
        EditorTextField(
          key: const ValueKey('search-shops'),
          value: phrases?.retail ?? '',
          label: 'Search shops for',
          helper: 'Brand, model and color, to find what it costs new.',
          minLines: 1,
          maxLines: 3,
          inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
          textInputAction: TextInputAction.done,
          onChanged: (text) =>
              session.edit((listing) => _withPhrase(listing, retail: text)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: why == null && !_looking ? _lookUp : null,
            icon: _looking
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_looking ? 'Looking up prices…' : 'Look up prices'),
          ),
        ),
        if (why != null) ...[const SizedBox(height: 8), QuietText(why)],
        if (_looking && _waking) ...[
          const SizedBox(height: 8),
          const QuietText(
            'The server sleeps when it is not in use, so the first look-up '
            'in a while takes longer while it wakes up.',
          ),
        ],
        if (_problem case final String problem) ...[
          const SizedBox(height: 12),
          Notice(icon: Icons.cloud_off_outlined, warning: true, text: problem),
        ],
        const SizedBox(height: 16),
        PriceResults(search: listing.priceSearch, failedNew: _failedNew),
        rule,
        CheckItYourself(
          query: (phrases?.depop.trim().isNotEmpty ?? false)
              ? phrases!.depop
              : listing.title,
        ),
        rule,
        TypedPrices(listing: listing, session: session),
        rule,
        SuggestionBlock(
          suggestion: suggestion,
          price: listing.priceCents,
          onUse: () => session.edit(
            (listing) =>
                listing.copyWith(priceCents: suggestion.listPriceCents),
          ),
        ),
        const SizedBox(height: 16),
        YourPrice(listing: listing, session: session, suggestion: suggestion),
      ],
    );
  }
}
