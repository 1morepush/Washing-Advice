/// Material 3 theming: light, dark, and dark on true black.
///
/// The palette is drawn from the subject: a wardrobe app is about fabric and
/// water, so it leans on a deep indigo with warm neutral surfaces rather than
/// the default purple.
///
/// One deliberate departure from stock Material: confidence has its own colour
/// role. The whole system distinguishes what it knows from what it is guessing,
/// and that distinction is worthless if the UI renders both identically.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

const _seed = Color(0xFF3F5B8C);

// The grounds of `AppTheme.amoled`. Black is the one the whole theme exists for;
// the four above it are for the few things that still need a fill. They climb
// evenly, about seven levels a step, and are tinted toward the seed's blue the
// way Dark's own surfaces are, so they sit with the indigo instead of reading as
// a neutral grey.
const _black = Color(0xFF000000);
const _amoledLow = Color(0xFF0C0E12);
const _amoledContainer = Color(0xFF13161B);
const _amoledHigh = Color(0xFF1A1D23);
const _amoledHighest = Color(0xFF22252C);

/// The font to render with, or null to let the platform decide.
///
/// Android and iOS have Roboto and SF Pro, which look right on their own
/// platforms and cost nothing to use. Web has neither: CanvasKit draws text
/// itself and, with no font asset, fetches Roboto from a CDN on first paint —
/// a network dependency the app does not otherwise have, and one that fails
/// outright in a sandboxed container. So the bundled font is used there and
/// only there.
String? get _fontFamily => kIsWeb ? 'Liberation Sans' : null;

/// How the app is dressed: what the person chose, as opposed to what the phone
/// says.
///
/// [system] is the default, and is what the app did before there was a choice,
/// so nobody's phone changes until they ask it to.
enum Appearance {
  /// Light or dark, as the phone is set.
  system,
  light,
  dark,

  /// Dark, on true black. See [AppTheme.amoled].
  amoled;

  /// What `MaterialApp` is told to follow.
  ///
  /// AMOLED asks for dark exactly as [dark] does. It is a different dark theme
  /// rather than a mode of the framework's own, which is what [darkTheme] is
  /// for.
  ThemeMode get themeMode => switch (this) {
    Appearance.system => ThemeMode.system,
    Appearance.light => ThemeMode.light,
    Appearance.dark || Appearance.amoled => ThemeMode.dark,
  };

  /// The theme `MaterialApp` uses whenever dark is in force.
  ///
  /// Not just `AppTheme.dark()` at each call site: [system] still needs the
  /// ordinary dark for a phone that is in dark mode, and only [amoled] swaps it.
  /// Two app roots that each remembered that would eventually disagree.
  ThemeData get darkTheme =>
      this == Appearance.amoled ? AppTheme.amoled() : AppTheme.dark();

  /// The surface this choice lays under a phone in light mode and under a phone
  /// in dark mode: the same colour for both, unless the phone decides.
  ///
  /// Its one consumer is the browser's own chrome, which the browser draws and
  /// which cannot read a theme — see `browser_chrome.dart`. It is here, and not
  /// there, so that it can be tested, and so the colours are read off the
  /// schemes the app paints with instead of being a second copy of them.
  ({Color whenLight, Color whenDark}) get surfaces {
    final light = AppTheme._scheme(Brightness.light).surface;
    final dark = AppTheme._scheme(Brightness.dark).surface;
    return switch (this) {
      Appearance.system => (whenLight: light, whenDark: dark),
      Appearance.light => (whenLight: light, whenDark: light),
      Appearance.dark => (whenLight: dark, whenDark: dark),
      Appearance.amoled => (whenLight: _black, whenDark: _black),
    };
  }
}

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  /// Dark, on true black.
  ///
  /// A laundry app is opened in a utility room at night, and on an OLED screen
  /// a black pixel is a pixel that is off. Dark's blue-grey ground is, on that
  /// screen, a lit rectangle the size of the phone; this one lets the room stay
  /// dark and draws almost nothing to do it. So the scaffold, the app bar and
  /// the cards are `#000000`, not merely very dark.
  ///
  /// What that gives up is the habit of telling surfaces apart by lightness —
  /// there is no ground darker than black to lift one from. The hierarchy moves
  /// from fills to edges instead. A card is black with the same hairline Dark
  /// gives it, rather than a lighter panel, and the app bar does not tint when a
  /// list scrolls under it, since the tint would paint a blue-grey band across a
  /// bar that is meant to be black. What does need a fill — an input, a chip, a
  /// sheet, a dialog, a box that sums something up — gets a near-black one, just
  /// far enough above the ground to read as a surface and not so far that it
  /// becomes a large grey area.
  ///
  /// Everything else is Dark's: the same seed, the same accents, and the same
  /// text. That is the seed's soft white and not `#FFFFFF`, which on black is
  /// glare without being any easier to read.
  static ThemeData amoled() => _build(Brightness.dark, trueBlack: true);

  static ColorScheme _scheme(Brightness brightness, {bool trueBlack = false}) {
    assert(!trueBlack || brightness == Brightness.dark);

    final seeded = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    if (!trueBlack) return seeded;

    return seeded.copyWith(
      surface: _black,
      surfaceDim: _black,
      surfaceContainerLowest: _black,
      surfaceContainerLow: _amoledLow,
      surfaceContainer: _amoledContainer,
      surfaceContainerHigh: _amoledHigh,
      surfaceContainerHighest: _amoledHighest,
    );
  }

  static ThemeData _build(Brightness brightness, {bool trueBlack = false}) {
    final scheme = _scheme(brightness, trueBlack: trueBlack);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: _fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        // Once a list scrolls under the bar, Material lays this tint over it in
        // proportion to `scrolledUnderElevation`. In light and dark that is the
        // cue that something is passing beneath; over black it is a blue-grey
        // band. With the tint gone the elevation has nothing left to draw — the
        // bar's shadow is transparent — so it can stay as it is.
        surfaceTintColor: trueBlack ? Colors.transparent : scheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        // Left to Material for light and dark. Its own fill is the low
        // container, which on true black is a grey panel behind everything on
        // a card, when the edge below is meant to be what says where it ends.
        color: trueBlack ? scheme.surface : null,
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
      // The app navigates with a drawer today. A bottom bar would be given the
      // `surfaceContainer` fill, which here is a grey strip across the bottom
      // of an otherwise black screen.
      navigationBarTheme: trueBlack
          ? NavigationBarThemeData(backgroundColor: scheme.surface)
          : null,
    );
  }
}

/// Whether a scheme's ground is black itself, as [AppTheme.amoled]'s is.
///
/// For the few colours chosen as a fraction laid over the ground, whose result
/// depends on how much ground there is to climb from — see
/// `ItemThumbnail._backdropFor`.
extension TrueBlack on ColorScheme {
  bool get hasTrueBlackGround => surface == _black;
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
