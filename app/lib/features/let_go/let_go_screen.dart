/// The garments that have not been worn in a year, with a way to sell each.
///
/// A list of offers. Every row says plainly how long it has been, and then
/// gives three ways to answer: start a listing, say "Keep" and hear no more of
/// it for six months, or open the garment to look. Nothing here is the right
/// answer — the words never say "you should" — because a year of not wearing
/// a jumper bought by someone you love is a fact about the jumper and not a
/// verdict on it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/item_thumbnail.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/state_view.dart';
import '../../widgets/status_message.dart';
import '../sell/list/listing_when.dart';
import '../sell/listing_controller.dart';
import '../sell/start/start_listing.dart';
import 'let_go_providers.dart';

class LetGoScreen extends ConsumerWidget {
  const LetGoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidates = ref.watch(letGoProvider);

    return Scaffold(
      appBar: AppBar(
        leading: backLeading(context, '/sell'),
        title: const AppBarTitle('Not worn in a year'),
      ),
      body: candidates.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StatusMessage.failure(
          title: 'Could not load your wardrobe',
          error: error,
        ),
        data: (list) => list.isEmpty
            ? const EmptyView(
                icon: Icons.checkroom_outlined,
                title: 'Nothing to suggest',
                message:
                    'Everything you own has been worn in the last year, or '
                    'is the kind of piece that is kept for an occasion. This '
                    'fills in by itself if that changes.',
              )
            : _List(candidates: list),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.candidates});

  final List<LetGoCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            '${letGoHeadline(candidates.length)}, longest first. If you '
            'are ready to part with any, start a listing. If not, say Keep and '
            'it will not be suggested again for six months.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final candidate in candidates)
          Padding(
            // Keyed by the garment, so a card that stays keeps its place when
            // its neighbour is kept and leaves.
            key: ValueKey(candidate.item.id.value),
            padding: const EdgeInsets.only(bottom: 12),
            child: _Offer(candidate: candidate),
          ),
      ],
    );
  }
}

class _Offer extends ConsumerWidget {
  const _Offer({required this.candidate});

  final LetGoCandidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final item = candidate.item;
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    void open() => context.push('/item/${item.id.value}');

    return RinseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: open,
            borderRadius: context.rinse.tileBorderRadius,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ItemThumbnail(item: item, size: 72),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(item.type.value.label, style: quiet),
                      const SizedBox(height: 2),
                      Text(
                        candidate.neverWorn
                            ? 'Never worn. Added ${shortDate(candidate.since)}'
                            : 'Last worn ${shortDate(candidate.since)}',
                        style: quiet,
                      ),
                      Text('(${_howLong(candidate.idle)})', style: quiet),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => unawaited(
                  startListingForGarment(
                    context,
                    ref.read(listingControllerProvider),
                    item.id,
                  ),
                ),
                icon: const Icon(Icons.sell_outlined, size: 18),
                label: const Text('Sell this'),
              ),
              OutlinedButton(
                onPressed: () => _keep(context, ref),
                child: const Text('Keep'),
              ),
              TextButton(onPressed: open, child: const Text('Open')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _keep(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final keeps = ref.read(letGoKeepsProvider.notifier);
    final id = candidate.item.id;
    await keeps.keep(id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Kept. ${candidate.item.displayName} will not be suggested for '
            'six months.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(keeps.forget(id)),
          ),
        ),
      );
  }

  /// `1 year 4 months`, rounded down to whole months; a garment over a year
  /// idle is never shown as "0 months".
  static String _howLong(Duration idle) {
    final months = idle.inDays ~/ 30;
    final years = months ~/ 12;
    final rest = months % 12;
    final parts = [
      if (years > 0) '$years ${years == 1 ? 'year' : 'years'}',
      if (rest > 0) '$rest ${rest == 1 ? 'month' : 'months'}',
    ];
    return parts.isEmpty ? 'over a year' : '${parts.join(' ')} ago';
  }
}
