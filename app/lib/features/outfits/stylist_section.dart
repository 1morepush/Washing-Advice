/// What a model thinks would look good.
///
/// A section of the Ideas list, under the outfits the app builds itself, and
/// marked as the model's: the two are different in kind and pretending
/// otherwise would be dishonest. The built suggestions are arithmetic — colour
/// distance, wear counts, what has been worn together, each with a reason the
/// app can defend. This is somebody else's taste, and the user is entitled to
/// know which they are looking at before they take the advice. Every card says
/// so, in `outfit_source.dart`.
///
/// So the reason a model gave is shown in full, in its own words, rather than
/// summarised into a tick-list like the built suggestions. A suggestion that
/// hid its reasoning would be asking to be obeyed rather than considered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import 'outfit_controller.dart';
import 'outfit_pieces.dart';
import 'outfit_source.dart';
import 'saved_outfits.dart';
import 'stylist_controller.dart';

/// Whether to also ask what the wardrobe is missing.
///
/// Off by default. Naming clothes somebody does not own is a different thing
/// from naming ones they do, and plenty of people keep a wardrobe app
/// precisely to buy less.
final suggestGapsProvider = StateProvider<bool>((ref) => false);

class StylistSection extends ConsumerStatefulWidget {
  const StylistSection({super.key});

  @override
  ConsumerState<StylistSection> createState() => _StylistSectionState();
}

class _StylistSectionState extends ConsumerState<StylistSection>
    with AutomaticKeepAliveClientMixin {
  /// Kept alive so a note typed here survives the list being scrolled away from
  /// it. The list builds lazily and would otherwise drop the field, and its
  /// text, as soon as it left the screen.
  @override
  bool get wantKeepAlive => true;

  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _ask() => ref
      .read(stylistControllerProvider.notifier)
      .ask(
        ref.read(outfitRequestProvider),
        note: _note.text,
        suggestGaps: ref.read(suggestGapsProvider),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _content();
  }

  Widget _content() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SourceHeader(OutfitSource.stylist),
      switch (ref.watch(stylistControllerProvider)) {
        StylistIdle() => _Intro(note: _note, onAsk: _ask),
        StylistThinking() => const SectionNote(
          icon: Icons.auto_awesome_outlined,
          busy: true,
          title: 'Looking through your wardrobe…',
        ),
        StylistFailed(:final message, :final isRetryable) => SectionNote(
          icon: Icons.error_outline,
          title: 'Could not ask for ideas',
          detail: message,
          action: isRetryable
              ? FilledButton.tonal(
                  onPressed: _ask,
                  child: const Text('Try again'),
                )
              : TextButton(
                  onPressed: ref.read(stylistControllerProvider.notifier).reset,
                  child: const Text('Back'),
                ),
        ),
        final StylistSuggested suggested => _Ideas(
          state: suggested,
          onAskAgain: _ask,
        ),
      },
    ],
  );
}

class _Intro extends ConsumerWidget {
  const _Intro({required this.note, required this.onAsk});

  final TextEditingController note;
  final Future<void> Function() onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          // Saying plainly what happens and what it is worth. The outfits above
          // can defend every one of their reasons; this is taste, and someone
          // deciding whether to take the advice needs to know that up front
          // rather than infer it from a heading.
          'Sends what your wardrobe is made of — not your photographs — and '
          'asks for outfits. It notices things the app cannot: pattern against '
          'pattern, proportion, how dressy something reads. Treat it as an '
          'opinion.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: note,
          decoration: const InputDecoration(
            labelText: 'Anything to add? (optional)',
            hintText: 'e.g. it will be cold, or I am meeting a client',
          ),
          textInputAction: TextInputAction.done,
          maxLines: 2,
          minLines: 1,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: ref.watch(suggestGapsProvider),
          onChanged: (on) =>
              ref.read(suggestGapsProvider.notifier).state = on ?? false,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Also say what I am missing'),
          subtitle: Text(
            'Names pieces you do not own that would go with your clothes.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: onAsk,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Ask for ideas'),
        ),
        const SizedBox(height: 8),
        Text(
          'Uses the occasion and season chosen on this tab.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Ideas extends ConsumerWidget {
  const _Ideas({required this.state, required this.onAskAgain});

  final StylistSuggested state;
  final Future<void> Function() onAskAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (state.outfits.isEmpty && state.pieces.isEmpty) {
      return SectionNote(
        icon: Icons.auto_awesome_outlined,
        title: 'Nothing usable came back',
        // Named rather than shrugged at. "Suggested something that is not
        // available to wear" is the difference between a thin wardrobe and a
        // model that forgot half of it is in the machine, and the second is
        // worth asking again about.
        detail: state.setAside.isEmpty
            ? 'No outfits were proposed. Trying again usually helps.'
            : 'Every idea was set aside: '
                  '${state.setAside.join('; ').toLowerCase()}.',
        action: FilledButton.tonal(
          onPressed: onAskAgain,
          child: const Text('Ask again'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final outfit in state.outfits)
          _IdeaCard(outfit: outfit, occasion: state.occasion),
        if (state.pieces.isNotEmpty) _Missing(pieces: state.pieces),
        if (state.setAside.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Some ideas were set aside: '
            '${state.setAside.join('; ').toLowerCase()}.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Offered again here because the intro is unreachable once ideas are
        // on screen, which would let the first ask decide the whole session.
        CheckboxListTile(
          value: ref.watch(suggestGapsProvider),
          onChanged: (on) =>
              ref.read(suggestGapsProvider.notifier).state = on ?? false,
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'Also say what I am missing',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Center(
          child: TextButton.icon(
            onPressed: onAskAgain,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Ask again'),
          ),
        ),
      ],
    );
  }
}

/// Pieces the wardrobe does not have.
///
/// Visibly apart from the outfits above, because everything there can be worn
/// today and nothing here can. No Save and no "Wearing this" either: both
/// resolve to real garments, and a piece with no id has none.
class _Missing extends StatelessWidget {
  const _Missing({required this.pieces});

  final List<SuggestedPiece> pieces;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.search_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'What you are missing',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Not in your wardrobe. Described rather than shopped for — no brand, '
          'no shop, no price.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final piece in pieces) _MissingCard(piece: piece),
      ],
    );
  }
}

class _MissingCard extends StatelessWidget {
  const _MissingCard({required this.piece});

  final SuggestedPiece piece;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      // A quieter surface than the outfits, so it reads as a note rather than
      // as one more thing to wear.
      color: theme.colorScheme.surfaceContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              piece.description,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            // Named rather than counted: "goes with 2 items" leaves somebody
            // asking which two.
            Text(
              'Goes with your '
              '${piece.pairsWith.map((item) => item.displayName).join(', ')}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              piece.rationale,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeaCard extends ConsumerWidget {
  const _IdeaCard({required this.outfit, required this.occasion});

  final StyledOutfit outfit;
  final Occasion occasion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return OutfitCard(
      source: OutfitSource.stylist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutfitPieces(items: outfit.items),
          const SizedBox(height: 14),
          Divider(height: 1, color: context.rinse.lineSoft),
          const SizedBox(height: 14),
          // In the model's own words, unabridged. Summarising it into the
          // tick-list the built suggestions use would throw away the only
          // thing this tab has that the other one does not.
          Text(outfit.rationale, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final name = await askForOutfitName(
                      context,
                      title: 'Save this outfit',
                    );
                    if (name == null || !context.mounted) return;

                    final saved = await ref
                        .read(outfitControllerProvider)
                        .saveStyled(outfit, name: name, occasion: occasion);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Saved as ${saved.name}.')),
                    );
                  },
                  icon: const Icon(Icons.bookmark_border, size: 18),
                  label: const Text('Save'),
                ),
                // The same loop the built suggestions close. A styled outfit
                // that gets worn teaches the co-wear graph a pairing the
                // builder did not know, so taking the model's advice makes the
                // arithmetic on the other tab better too.
                FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(outfitControllerProvider)
                        .wearItems(outfit.itemIds, occasion: occasion.name);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Recorded as worn together, and put in the basket.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.checkroom_outlined, size: 18),
                  label: const Text('Wearing this'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
