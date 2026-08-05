/// Material 3 theming, light and dark.
///
/// The palette is drawn from the subject: a wardrobe app is about fabric and
/// water, so it leans on a deep indigo with warm neutral surfaces rather than
/// the default purple.
///
/// One deliberate departure from stock Material: confidence has its own colour
/// role. The whole system distinguishes what it knows from what it is guessing,
/// and that distinction is worthless if the UI renders both identically.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

const _seed = Color(0xFF3F5B8C);

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    );
  }
}

/// Colours for how sure the system is about something.
///
/// Extending the theme rather than scattering `Colors.orange` through widgets:
/// a user who cannot tell a fact from a guess has no reason to trust either,
/// so this needs to be applied consistently and be adjustable in one place.
extension ConfidenceColors on ColorScheme {
  /// The colour for a belief in [band].
  Color confidenceColor(ConfidenceBand band) => switch (band) {
    // Deliberately *not* the primary colour. High confidence is the normal
    // case and should look like ordinary content, not like an alert.
    ConfidenceBand.high => onSurfaceVariant,
    ConfidenceBand.medium => tertiary,
    ConfidenceBand.low => error,
  };

  /// A background for a confidence chip.
  Color confidenceContainer(ConfidenceBand band) => switch (band) {
    ConfidenceBand.high => surfaceContainerHighest,
    ConfidenceBand.medium => tertiaryContainer,
    ConfidenceBand.low => errorContainer,
  };

  Color onConfidenceContainer(ConfidenceBand band) => switch (band) {
    ConfidenceBand.high => onSurfaceVariant,
    ConfidenceBand.medium => onTertiaryContainer,
    ConfidenceBand.low => onErrorContainer,
  };
}

/// What a confidence band means, in words a user can act on.
///
/// Lives here beside the colours so the two never drift apart — a chip that is
/// amber but says "certain" is worse than no chip at all.
String confidenceLabel(ConfidenceBand band) => switch (band) {
  ConfidenceBand.high => 'Confident',
  ConfidenceBand.medium => 'Please check',
  ConfidenceBand.low => 'Unsure',
};
