/// Showing how sure the app is.
///
/// The system spends a great deal of effort tracking whether a fact came from a
/// care label, a rule, a vision model or a fallback, and all of that is wasted
/// if the screen renders a guess and a certainty identically. A user who cannot
/// tell the two apart has no reason to trust either.
///
/// The chip is deliberately quiet at high confidence — no colour, no icon
/// beyond the text it qualifies — because the normal case should look like
/// ordinary content. It gets loud only when it is asking for attention.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../core/theme.dart';

/// A small badge stating a confidence band and where the belief came from.
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({
    required this.confidence,
    required this.source,
    this.compact = false,
    super.key,
  });

  /// Builds a chip for any [Confident] value.
  ConfidenceChip.of(Confident<Object> value, {bool compact = false, Key? key})
    : this(
        confidence: value.confidence,
        source: value.source,
        compact: compact,
        key: key,
      );

  final double confidence;
  final Provenance source;

  /// Drops the provenance and shows only the band — for list rows, where the
  /// full explanation would be noise.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final band = ConfidenceThresholds.bandFor(confidence);

    // High confidence in a list is the overwhelmingly common case, and a badge
    // on every row would train people to ignore all of them.
    if (compact && band == ConfidenceBand.high) return const SizedBox.shrink();

    final text = compact
        ? confidenceLabel(band)
        : '${confidenceLabel(band)} · ${provenanceLabel(source)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.confidenceContainer(band),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onConfidenceContainer(band),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Where a belief came from, said in a way a user can act on.
///
/// Not the enum name: "aiInference" tells a developer something and tells
/// everyone else nothing. The phrasing is about *evidence* — a label is a
/// manufacturer's instruction, a photo is the app's guess — because that is
/// what decides whether someone should go and check.
String provenanceLabel(Provenance source) => switch (source) {
  Provenance.fallbackDefault => 'assumed',
  Provenance.aiInference => 'from a photo',
  Provenance.careRule => 'from the fabric',
  Provenance.tagScan => 'from the care label',
  Provenance.userEdited => 'you set this',
};
