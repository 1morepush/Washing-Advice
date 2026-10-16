/// The "Rinse" look: calm and airy, soft blue-white, rounded friendly type, no
/// outlines (soft shadows instead), in three modes — Light, Dark and AMOLED.
///
/// Every colour in the app comes from the palettes below. Widgets read them
/// through three things and never write a hex value of their own:
///
///  * the [ColorScheme], for anything Material already has a role for;
///  * [RinseShape], for radii, the card edge or shadow, the tile "well" and the
///    outline drawn round a garment;
///  * [LaundryStageColors], for Basket, Washing and Drying.
///
/// ## How the tokens map onto Material 3 roles
///
/// | Rinse token            | Material role                                   |
/// |------------------------|--------------------------------------------------|
/// | bg                     | `surface` (scaffold, app bar), `surfaceDim`      |
/// | card                   | `surfaceContainerLowest` and `surfaceContainerLow` (`Card`'s default fill) |
/// | surface2               | `surfaceContainer`, `High` and `Highest` (inputs, segmented buttons, tonal fills) |
/// | well                   | [RinseShape.well] (garment tile background)      |
/// | ink                    | `onSurface`                                      |
/// | muted                  | `onSurfaceVariant`, `outline`, `secondary`       |
/// | line                   | `outlineVariant` (dividers, ghost buttons)       |
/// | line-soft              | [RinseShape.lineSoft] (hairlines inside a card)  |
/// | accent / on-accent     | `primary` / `onPrimary`                          |
/// | accent-soft            | `primaryContainer`, `secondaryContainer`         |
/// | nav icon               | `onPrimaryContainer`, `onSecondaryContainer`     |
/// | warn-bg / warn-ink     | `tertiaryContainer` / `tertiary`, `onTertiaryContainer` |
///
/// `surfaceTint` is transparent everywhere: Rinse separates surfaces with a
/// soft shadow (Light), a lighter fill (Dark) or a hairline (AMOLED), never
/// with Material's elevation tint.
///
/// One deliberate departure from stock Material: confidence has its own colour
/// role ([ConfidenceColors]). The whole system distinguishes what it knows from
/// what it is guessing, and that distinction is worthless if the UI renders both
/// identically.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

/// The typeface, bundled under `assets/fonts` for every platform (nothing is
/// fetched at run time). Weights 400, 600, 700 and 800 are shipped; anything
/// else is drawn from the nearest.
const rinseFontFamily = 'Nunito';

/// The grounds of [AppTheme.amoled]. Black is what the whole mode exists for.
const _black = Color(0xFF000000);

/// One mode's complete set of Rinse tokens.
class _Palette {
  const _Palette({
    required this.brightness,
    required this.bg,
    required this.card,
    required this.surface2,
    required this.well,
    required this.ink,
    required this.muted,
    required this.line,
    required this.lineSoft,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.navIcon,
    required this.basket,
    required this.onBasket,
    required this.wash,
    required this.onWash,
    required this.dry,
    required this.onDry,
    required this.warnBg,
    required this.warnInk,
    required this.garmentEdge,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.cardShadow,
    required this.cardHairline,
  });

  final Brightness brightness;
  final Color bg, card, surface2, well;
  final Color ink, muted, line, lineSoft;
  final Color accent, onAccent, accentSoft, navIcon;
  final Color basket, onBasket, wash, onWash, dry, onDry;
  final Color warnBg, warnInk, garmentEdge;
  final Color error, onError, errorContainer, onErrorContainer;
  final List<BoxShadow> cardShadow;

  /// Whether a card is drawn with a 1px edge (true black only).
  final bool cardHairline;

  ColorScheme get scheme => ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: accentSoft,
    onPrimaryContainer: navIcon,
    secondary: muted,
    onSecondary: card,
    secondaryContainer: accentSoft,
    onSecondaryContainer: navIcon,
    tertiary: warnInk,
    onTertiary: warnBg,
    tertiaryContainer: warnBg,
    onTertiaryContainer: warnInk,
    error: error,
    onError: onError,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    surface: bg,
    onSurface: ink,
    onSurfaceVariant: muted,
    surfaceDim: bg,
    surfaceBright: card,
    surfaceContainerLowest: card,
    surfaceContainerLow: card,
    surfaceContainer: surface2,
    surfaceContainerHigh: surface2,
    surfaceContainerHighest: surface2,
    outline: muted,
    outlineVariant: line,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
    inverseSurface: ink,
    onInverseSurface: bg,
    inversePrimary: brightness == Brightness.light
        ? const Color(0xFF6CB6F5)
        : const Color(0xFF1E73C8),
    surfaceTint: Colors.transparent,
  );

  RinseShape get shape => RinseShape(
    cardRadius: 22,
    tileRadius: 16,
    well: well,
    lineSoft: lineSoft,
    garmentEdge: garmentEdge,
    cardShadow: cardShadow,
    cardEdge: cardHairline ? BorderSide(color: line) : BorderSide.none,
  );

  LaundryStageColors get stages => LaundryStageColors(
    basket: basket,
    onBasket: onBasket,
    wash: wash,
    onWash: onWash,
    dry: dry,
    onDry: onDry,
  );
}

const _lightPalette = _Palette(
  brightness: Brightness.light,
  bg: Color(0xFFEEF4F8),
  card: Color(0xFFFFFFFF),
  surface2: Color(0xFFE2ECF4),
  well: Color(0xFFE5EEF5),
  ink: Color(0xFF0F2236),
  muted: Color(0xFF5A6B7C),
  line: Color(0xFFD3DEE8),
  lineSoft: Color(0xFFE3EAF1),
  accent: Color(0xFF1E73C8),
  onAccent: Color(0xFFFFFFFF),
  accentSoft: Color(0xFFD8E8F8),
  navIcon: Color(0xFF0E4D8C),
  basket: Color(0xFFE3A63F),
  onBasket: Color(0xFF2A1A00),
  wash: Color(0xFF1E73C8),
  onWash: Color(0xFFFFFFFF),
  dry: Color(0xFF3FA58A),
  // The design says white; white on this green is 3.0:1, under the 4.5:1 a
  // label needs. The deep green Dark uses is 6:1 here.
  onDry: Color(0xFF06261C),
  warnBg: Color(0xFFFFF0D3),
  warnInk: Color(0xFF6A4300),
  garmentEdge: Color(0x380F2236),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF93000A),
  cardShadow: [
    BoxShadow(color: Color(0x0F0F2236), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x120F2236), blurRadius: 16, offset: Offset(0, 6)),
  ],
  cardHairline: false,
);

const _darkPalette = _Palette(
  brightness: Brightness.dark,
  bg: Color(0xFF0C1620),
  card: Color(0xFF132230),
  surface2: Color(0xFF1A2D3F),
  well: Color(0xFF182A3B),
  ink: Color(0xFFE5EEF6),
  muted: Color(0xFF93A7BA),
  line: Color(0xFF26394C),
  lineSoft: Color(0xFF1E3043),
  accent: Color(0xFF6CB6F5),
  onAccent: Color(0xFF062238),
  accentSoft: Color(0xFF163552),
  navIcon: Color(0xFF9FD0FA),
  basket: Color(0xFFE9B85E),
  onBasket: Color(0xFF2A1A00),
  wash: Color(0xFF6CB6F5),
  onWash: Color(0xFF062238),
  dry: Color(0xFF6BC7A9),
  onDry: Color(0xFF06261C),
  warnBg: Color(0xFF3A2C10),
  warnInk: Color(0xFFF5D08A),
  garmentEdge: Color(0x47E5EEF6),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF5C1A17),
  onErrorContainer: Color(0xFFFFDAD6),
  cardShadow: [],
  cardHairline: false,
);

const _amoledPalette = _Palette(
  brightness: Brightness.dark,
  bg: _black,
  card: _black,
  surface2: Color(0xFF0B131B),
  well: Color(0xFF0D1620),
  ink: Color(0xFFDCE7F1),
  muted: Color(0xFF8597A9),
  line: Color(0xFF1D2A37),
  lineSoft: Color(0xFF141E28),
  accent: Color(0xFF5FA8EB),
  onAccent: Color(0xFF03121F),
  accentSoft: Color(0xFF0D2133),
  navIcon: Color(0xFF9FCBF5),
  basket: Color(0xFFD8A84E),
  onBasket: Color(0xFF1C1200),
  wash: Color(0xFF5FA8EB),
  onWash: Color(0xFF03121F),
  dry: Color(0xFF5DB89A),
  onDry: Color(0xFF03140E),
  warnBg: Color(0xFF211808),
  warnInk: Color(0xFFEBC77D),
  garmentEdge: Color(0x4DDCE7F1),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF2A0E0C),
  onErrorContainer: Color(0xFFFFB4AB),
  cardShadow: [],
  cardHairline: true,
);

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
    final light = _lightPalette.bg;
    final dark = _darkPalette.bg;
    return switch (this) {
      Appearance.system => (whenLight: light, whenDark: dark),
      Appearance.light => (whenLight: light, whenDark: light),
      Appearance.dark => (whenLight: dark, whenDark: dark),
      Appearance.amoled => (whenLight: _black, whenDark: _black),
    };
  }
}

abstract final class AppTheme {
  static ThemeData light() => _build(_lightPalette);

  static ThemeData dark() => _build(_darkPalette);

  /// Dark, on true black.
  ///
  /// A laundry app is opened in a utility room at night, and on an OLED screen
  /// a black pixel is a pixel that is off. So the scaffold, app bar, bottom bar
  /// and cards are `#000000`, not merely very dark.
  ///
  /// What that gives up is telling surfaces apart by lightness. The hierarchy
  /// moves from fills to edges instead: a card is black with a one-pixel
  /// hairline, a chip likewise. What does need a fill (an input, a segmented
  /// control) gets a near-black one. Text is a soft white, not `#FFFFFF`, which
  /// on black is glare without being easier to read.
  static ThemeData amoled() => _build(_amoledPalette);

  static ThemeData _build(_Palette p) {
    final scheme = p.scheme;
    final shape = p.shape;
    const pill = StadiumBorder();
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(shape.cardRadius),
      side: shape.cardEdge,
    );
    final sheetShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(shape.cardRadius),
      ),
    );
    final hairlineChips = p.cardHairline;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: rinseFontFamily,
      textTheme: _textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      extensions: [shape, p.stages],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          fontFamily: rinseFontFamily,
          color: scheme.onSurface,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.26,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        // The two-layer shadow of the design is drawn by Material as a single
        // soft elevation shadow; it is invisible in Dark and AMOLED, which use
        // a fill and a hairline instead.
        elevation: p.cardShadow.isEmpty ? 0 : 2,
        shadowColor: const Color(0x4D0F2236),
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: cardShape,
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(
          side: hairlineChips ? BorderSide(color: p.line) : BorderSide.none,
        ),
        side: hairlineChips ? BorderSide(color: p.line) : BorderSide.none,
        backgroundColor: p.card,
        selectedColor: p.accent,
        disabledColor: p.surface2,
        checkmarkColor: p.onAccent,
        elevation: 0,
        pressElevation: 0,
        labelStyle: TextStyle(
          fontFamily: rinseFontFamily,
          color: p.ink,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: rinseFontFamily,
          color: p.onAccent,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: pill,
          minimumSize: const Size(64, 48),
          textStyle: _buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: pill,
          elevation: 0,
          backgroundColor: p.card,
          foregroundColor: p.accent,
          minimumSize: const Size(64, 48),
          textStyle: _buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: pill,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: p.line, width: 1.5),
          foregroundColor: p.ink,
          textStyle: _buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: pill,
          minimumSize: const Size(48, 44),
          textStyle: _buttonText,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 3,
        highlightElevation: 4,
        shape: pill,
        extendedTextStyle: _buttonText,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(pill),
          side: WidgetStatePropertyAll(
            hairlineChips ? BorderSide(color: p.line) : BorderSide.none,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? p.accent : p.surface2,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? p.onAccent : p.ink,
          ),
          textStyle: const WidgetStatePropertyAll(_buttonText),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shape.tileRadius),
          borderSide: BorderSide.none,
        ),
        // True black has no lighter fill to lean on, so the field gets an edge.
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shape.tileRadius),
          borderSide: hairlineChips
              ? BorderSide(color: p.line)
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shape.tileRadius),
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: p.muted,
      ),
      dividerTheme: DividerThemeData(color: p.lineSoft, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.cardRadius),
          side: shape.cardEdge,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.card,
        shape: sheetShape,
        showDragHandle: true,
        dragHandleColor: p.line,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.tileRadius),
          side: shape.cardEdge,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shape.tileRadius),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surface2,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.accent,
        unselectedLabelColor: p.muted,
        indicatorColor: p.accent,
        dividerColor: p.lineSoft,
        labelStyle: _buttonText,
        unselectedLabelStyle: _buttonText,
      ),
      // The bar is the card colour with a hairline on top (drawn by the shell,
      // `NavigationBar` has no border of its own). The selected place is a
      // pill, a filled icon in the deep accent and a label in full ink; the
      // others are muted outlines.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: p.accentSoft,
        indicatorShape: pill,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? p.navIcon : p.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: rinseFontFamily,
            fontSize: 12,
            letterSpacing: 0,
            fontWeight: FontWeight.w700,
            color: states.contains(WidgetState.selected) ? p.ink : p.muted,
          ),
        ),
      ),
    );
  }
}

const _buttonText = TextStyle(
  fontFamily: rinseFontFamily,
  fontSize: 15,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
);

/// Nunito, with a clearer hierarchy than stock Material: 26/800 for a screen
/// title ([TextTheme.headlineMedium]), 20/800 for a section ([titleLarge]),
/// 16/700 for a row's name or a value ([titleMedium]), 14/400 body, and a
/// floor of 12 so that nothing has to be set in tiny grey text. Heights and
/// colours come from Material's own defaults.
const _textTheme = TextTheme(
  displayLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
  displayMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.25),
  displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0),
  headlineLarge: TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.32,
  ),
  headlineMedium: TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.26,
  ),
  headlineSmall: TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.1,
  ),
  titleLarge: TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  ),
  titleMedium: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  ),
  titleSmall: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  ),
  bodyLarge: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  ),
  bodyMedium: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  ),
  bodySmall: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
  ),
  labelLarge: TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  ),
  labelMedium: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  ),
  labelSmall: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  ),
);

/// Shape and surface tokens: radii, the card edge or shadow, the tile "well",
/// and the outline drawn round a garment.
@immutable
class RinseShape extends ThemeExtension<RinseShape> {
  const RinseShape({
    required this.cardRadius,
    required this.tileRadius,
    required this.well,
    required this.lineSoft,
    required this.garmentEdge,
    required this.cardShadow,
    required this.cardEdge,
  });

  /// Cards, groups, sheets: 22.
  final double cardRadius;

  /// Tiles, wells, inner panels, inputs: 16. Buttons and chips are pills.
  final double tileRadius;

  /// The background of a garment tile or a hero behind a garment.
  final Color well;

  /// A hairline between rows inside a card.
  final Color lineSoft;

  /// The outline stroked round a garment silhouette so a pale one stays visible
  /// on a pale tile and a black one on a black tile.
  final Color garmentEdge;

  /// The soft two-layer shadow of a card (empty in Dark and AMOLED).
  final List<BoxShadow> cardShadow;

  /// The card's edge: [BorderSide.none] in Light and Dark, a 1px hairline in
  /// AMOLED.
  final BorderSide cardEdge;

  BorderRadius get cardBorderRadius => BorderRadius.circular(cardRadius);

  BorderRadius get tileBorderRadius => BorderRadius.circular(tileRadius);

  /// The shape of a card, for a `Material`, `InkWell` or `Card.shape`.
  RoundedRectangleBorder get cardShape =>
      RoundedRectangleBorder(borderRadius: cardBorderRadius, side: cardEdge);

  /// A card look for a plain `Container`, with the exact two-layer shadow.
  BoxDecoration cardDecoration(Color color) => BoxDecoration(
    color: color,
    borderRadius: cardBorderRadius,
    boxShadow: cardShadow,
    border: cardEdge == BorderSide.none
        ? null
        : Border.fromBorderSide(cardEdge),
  );

  /// The fallback for a context with no Rinse theme (a bare `MaterialApp`).
  static final RinseShape light = _lightPalette.shape;

  @override
  RinseShape copyWith({
    double? cardRadius,
    double? tileRadius,
    Color? well,
    Color? lineSoft,
    Color? garmentEdge,
    List<BoxShadow>? cardShadow,
    BorderSide? cardEdge,
  }) => RinseShape(
    cardRadius: cardRadius ?? this.cardRadius,
    tileRadius: tileRadius ?? this.tileRadius,
    well: well ?? this.well,
    lineSoft: lineSoft ?? this.lineSoft,
    garmentEdge: garmentEdge ?? this.garmentEdge,
    cardShadow: cardShadow ?? this.cardShadow,
    cardEdge: cardEdge ?? this.cardEdge,
  );

  @override
  RinseShape lerp(RinseShape? other, double t) {
    if (other == null) return this;
    return RinseShape(
      cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
      tileRadius: tileRadius + (other.tileRadius - tileRadius) * t,
      well: Color.lerp(well, other.well, t)!,
      lineSoft: Color.lerp(lineSoft, other.lineSoft, t)!,
      garmentEdge: Color.lerp(garmentEdge, other.garmentEdge, t)!,
      cardShadow: BoxShadow.lerpList(cardShadow, other.cardShadow, t)!,
      cardEdge: BorderSide.lerp(cardEdge, other.cardEdge, t),
    );
  }
}

/// Basket, Washing and Drying, each with the colour to draw text and icons on
/// it. Used by the Laundry tabs, the load cards and anything that says which
/// stage a garment is in.
@immutable
class LaundryStageColors extends ThemeExtension<LaundryStageColors> {
  const LaundryStageColors({
    required this.basket,
    required this.onBasket,
    required this.wash,
    required this.onWash,
    required this.dry,
    required this.onDry,
  });

  final Color basket, onBasket, wash, onWash, dry, onDry;

  /// The fallback for a context with no Rinse theme.
  static final LaundryStageColors light = _lightPalette.stages;

  /// The stage colour for a lifecycle state, or null for one that is not a
  /// laundry stage (clean, worn and so on).
  Color? colorOf(LifecycleState state) => switch (state) {
    LifecycleState.inLaundry => basket,
    LifecycleState.beingWashed => wash,
    LifecycleState.beingDried => dry,
    _ => null,
  };

  /// What to draw on [colorOf].
  Color? onColorOf(LifecycleState state) => switch (state) {
    LifecycleState.inLaundry => onBasket,
    LifecycleState.beingWashed => onWash,
    LifecycleState.beingDried => onDry,
    _ => null,
  };

  @override
  LaundryStageColors copyWith({
    Color? basket,
    Color? onBasket,
    Color? wash,
    Color? onWash,
    Color? dry,
    Color? onDry,
  }) => LaundryStageColors(
    basket: basket ?? this.basket,
    onBasket: onBasket ?? this.onBasket,
    wash: wash ?? this.wash,
    onWash: onWash ?? this.onWash,
    dry: dry ?? this.dry,
    onDry: onDry ?? this.onDry,
  );

  @override
  LaundryStageColors lerp(LaundryStageColors? other, double t) {
    if (other == null) return this;
    return LaundryStageColors(
      basket: Color.lerp(basket, other.basket, t)!,
      onBasket: Color.lerp(onBasket, other.onBasket, t)!,
      wash: Color.lerp(wash, other.wash, t)!,
      onWash: Color.lerp(onWash, other.onWash, t)!,
      dry: Color.lerp(dry, other.dry, t)!,
      onDry: Color.lerp(onDry, other.onDry, t)!,
    );
  }
}

/// Reading the Rinse tokens from a context. Falls back to Light's when the
/// theme has none, so a widget under a bare `MaterialApp` still builds.
extension RinseContext on BuildContext {
  RinseShape get rinse =>
      Theme.of(this).extension<RinseShape>() ?? RinseShape.light;

  LaundryStageColors get stageColors =>
      Theme.of(this).extension<LaundryStageColors>() ??
      LaundryStageColors.light;
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
