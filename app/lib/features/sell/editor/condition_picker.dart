/// Depop's five condition labels, as chips, with what each one means.
///
/// Depop asks for a condition as a pick from five fixed words, and the words
/// are not self-explanatory: "Like new" and "Used - Excellent" are a judgement
/// apart, and a seller who guesses will guess generously. So each word carries
/// the meaning Depop gives it, under the chips for the one that is picked and
/// in a sheet for all five.
///
/// For a listing made from a garment the wardrobe has an opinion — the wear
/// that has been reported on it, and how often it has been worn — and the core
/// turns that into a suggestion with its reasons. It is shown as a sentence
/// for the person to check against the thing in their hands. It is never
/// applied by itself: grading something is the seller's word, and a condition
/// filled in silently is a promise made to a buyer on nobody's say-so.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'edit_session.dart';
import 'fields.dart';

/// The core's suggestion as the sentence under the chips:
/// `Suggested: Used - Excellent — worn 4 times, no wear reported`.
///
/// The reasons are the core's sentences, joined and run on from the label, so
/// the first loses its capital and each loses its full stop.
String suggestionLine(ConditionSuggestion suggestion) {
  final reasons = [
    for (final reason in suggestion.reasons)
      reason.trim().replaceFirst(RegExp(r'\.+$'), ''),
  ].where((reason) => reason.isNotEmpty).toList();
  if (reasons.isEmpty) return 'Suggested: ${suggestion.condition.label}';

  final first = reasons.first;
  reasons[0] = '${first[0].toLowerCase()}${first.substring(1)}';
  return 'Suggested: ${suggestion.condition.label} — ${reasons.join('; ')}';
}

class ConditionPicker extends StatelessWidget {
  const ConditionPicker({
    required this.listing,
    required this.session,
    this.garment,
    super.key,
  });

  final Listing listing;
  final ListingEditSession session;

  /// The garment this was made from, when it was made from one.
  final WardrobeItem? garment;

  void _pick(DepopCondition condition, bool picked) => session.edit(
    (listing) => picked
        ? listing.copyWith(condition: condition)
        : listing.copyWith(clearCondition: true),
  );

  @override
  Widget build(BuildContext context) {
    final picked = listing.condition;
    final suggestion = garment == null ? null : suggestCondition(garment!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SubHeading('Condition'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final condition in DepopCondition.values)
              ChoiceChip(
                label: Text(condition.label),
                tooltip: condition.meaning,
                selected: picked == condition,
                onSelected: (on) => _pick(condition, on),
              ),
          ],
        ),
        const SizedBox(height: 8),
        QuietText(
          picked == null
              ? 'Pick the one that fits. It goes in the description.'
              : '${picked.label}: ${picked.meaning}.',
        ),
        if (suggestion != null) ...[
          const SizedBox(height: 4),
          QuietText(suggestionLine(suggestion)),
          if (picked != suggestion.condition)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: inlineTextButton,
                onPressed: () => _pick(suggestion.condition, true),
                child: Text('Use ${suggestion.condition.label}'),
              ),
            ),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            style: inlineTextButton,
            onPressed: () => _showMeanings(context),
            child: const Text('What do these mean?'),
          ),
        ),
      ],
    );
  }

  Future<void> _showMeanings(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    "Depop's conditions",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                for (final condition in DepopCondition.values)
                  ListTile(
                    title: Text(condition.label),
                    subtitle: Text(condition.meaning),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
}
