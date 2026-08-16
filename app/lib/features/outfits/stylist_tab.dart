/// What a model thinks would look good.
///
/// Its own tab rather than extra cards among the built suggestions, because
/// the two are different in kind and pretending otherwise would be dishonest.
/// The Suggested tab is arithmetic: colour distance, wear counts, what has been
/// worn together, each with a reason the app can defend. This tab is somebody
/// else's taste, and the user is entitled to know which they are looking at
/// before they take the advice.
///
/// So the reason a model gave is shown in full, in its own words, rather than
/// summarised into a tick-list like the built suggestions. A suggestion that
/// hid its reasoning would be asking to be obeyed rather than considered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/status_message.dart';
import '../history/wear_recorder.dart';
import 'outfit_controller.dart';
import 'outfit_pieces.dart';
import 'saved_outfits.dart';
import 'stylist_controller.dart';

/// Whether to also ask what the wardrobe is missing.
///
/// Off by default, and asked for rather than assumed. Naming clothes somebody
/// does not own is a different thing from naming ones they do, and a wardrobe
/// app that volunteered it would be answering a question nobody put — plenty of
/// people keep one of these precisely to buy less. Same shape as
/// `groupDuplicatesProvider`: a display preference, held where the feature is.
final suggestGapsProvider = StateProvider<bool>((ref) => false);

class StylistTab extends ConsumerStatefulWidget {
  const StylistTab({super.key});

  @override
  ConsumerState<StylistTab> createState() => _StylistTabState();
}

class _StylistTabState extends ConsumerState<StylistTab> {
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
  Widget build(BuildContext context) => switch (ref.watch(
    stylistControllerProvider,
  )) {
    StylistIdle() => _Intro(note: _note, onAsk: _ask),
    StylistThinking() => const _Thinking(),
    StylistFailed(:final message, :final isRetryable) => StatusMessage(
      icon: Icons.error_outline,
      title: 'Could not ask for ideas',
      detail: message,
      action: isRetryable
          ? FilledButton.tonal(onPressed: _ask, child: const Text('Try again'))
          : TextButton(
              onPressed: ref.read(stylistControllerProvider.notifier).reset,
              child: const Text('Back'),
            ),
    ),
    final StylistSuggested suggested => _Ideas(
      state: suggested,
      onAskAgain: _ask,
    ),
  };
}

class _Intro extends ConsumerWidget {
  const _Intro({required this.note, required this.onAsk});

  final TextEditingController note;
  final Future<void> Function() onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      children: [
        Icon(
          Icons.auto_awesome_outlined,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Ask for ideas',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          // Saying plainly what happens and what it is worth. The Suggested tab
          // can defend every one of its reasons; this one is taste, and someone
          // deciding whether to take the advice needs to know that up front
          // rather than infer it from a tab name.
          'Sends what your wardrobe is made of — not your photographs — and '
          'asks for outfits. It notices things the app cannot: pattern against '
          'pattern, proportion, how dressy something reads. Treat it as an '
          'opinion.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: note,
          decoration: const InputDecoration(
            labelText: 'Anything to add? (optional)',
            hintText: 'e.g. it will be cold, or I am meeting a client',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          maxLines: 2,
          minLines: 1,
        ),
        const SizedBox(height: 8),
        // Opt-in, and worded as what it does rather than as a feature name.
        // "Also suggest things to buy" would be a different promise: what comes
        // back names a garment and a colour and stops there, with no brand, no
        // shop and no price, because where to get one is not the app's business.
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
          'Uses the occasion and season set on the Suggested tab.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'Looking through your wardrobe…',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class _Ideas extends ConsumerWidget {
  const _Ideas({required this.state, required this.onAskAgain});

  final StylistSuggested state;
  final Future<void> Function() onAskAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (state.outfits.isEmpty && state.pieces.isEmpty) {
      return StatusMessage(
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
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
        // The same choice as on the intro, offered again where it can actually
        // be changed. Without it the first answer decides the rest of the
        // session: the intro is not reachable once ideas are on screen, so
        // somebody who asked without this on had no way back to it, and
        // somebody who asked with it on had no way to stick to their wardrobe.
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
/// Below the outfits and visibly apart from them, because they are a different
/// kind of answer and the difference matters: everything above this can be
/// worn today, and nothing here can. A card that looked like the others would
/// be offering somebody clothes they do not own, which is the exact failure
/// [StyleVetting] exists to prevent on the other side.
///
/// No Save and no "Wearing this". Both resolve to real garments, and a piece
/// with no id has none — a button that appeared to work and then quietly did
/// nothing would be worse than its absence.
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
      // Outlined rather than filled, so it reads as a note beside the outfits
      // rather than as one more thing to wear.
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(piece.description, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // Named, not just counted. "Goes with 2 items" would make somebody
            // ask which two, and the pairing is the whole reason this is advice
            // rather than a shopping list.
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutfitPieces(items: outfit.items),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // In the model's own words, unabridged. Summarising it into the
            // tick-list the built suggestions use would throw away the only
            // thing this tab has that the other one does not.
            Text(
              outfit.rationale,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
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
                TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(wearRecorderProvider)
                        .recordOutfit(
                          outfit.itemIds.toList(),
                          occasion: occasion.name,
                        );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Recorded. These now count as worn together.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.checkroom_outlined, size: 18),
                  label: const Text('Wearing this'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
