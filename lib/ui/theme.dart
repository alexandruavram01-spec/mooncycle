import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/enums.dart';

/// The app has two looks. "Dawn" is hers: warm cream and rose. "Night" is the
/// partner's: deep navy with a moon-gold accent. The moon ties them together.
///
/// Each phase keeps its own hue in both, so the ring, the calendar and the
/// partner's moons read at a glance.
class MoonColors {
  static const seed = Color(0xFFD9566F);

  static const menstrual = Color(0xFFD9566F);
  static const follicular = Color(0xFF6FBFA0);
  static const ovulatory = Color(0xFFEDAE49);
  static const luteal = Color(0xFF9C8AD6);

  // Dawn
  static const dawn = Color(0xFFFFF7F2);
  static const dawnCard = Color(0xFFFFFFFF);
  static const dawnLine = Color(0xFFF3DDD6);
  static const dawnInk = Color(0xFF3B2A33);
  // Dark enough to read easily on the light background.
  static const dawnMuted = Color(0xFF654D57);
  static const dawnTint = Color(0xFFFDE9E4);
  static const dawnTintInk = Color(0xFF6B2238);

  // Night
  static const night = Color(0xFF12132A);
  static const nightCard = Color(0xFF1C1E3F);
  static const nightLine = Color(0xFF2C2F5C);
  static const nightInk = Color(0xFFF2F0FA);
  static const nightMuted = Color(0xFFA6A3C8);
  static const nightTint = Color(0xFF2A2460);

  // The moon
  static const moonGold = Color(0xFFF2C66D);
  static const moonPale = Color(0xFFE9D9B0);
  static const moonDim = Color(0xFF5A5890);
  static const moonInk = Color(0xFF4A3410);

  static Color forPhase(CyclePhase phase) => switch (phase) {
        CyclePhase.menstrual => menstrual,
        CyclePhase.follicular => follicular,
        CyclePhase.ovulatory => ovulatory,
        CyclePhase.luteal => luteal,
      };
}

/// Hers.
final ThemeData dawnTheme = _build(
  ColorScheme.fromSeed(
    seedColor: MoonColors.seed,
    brightness: Brightness.light,
  ).copyWith(
    primary: MoonColors.menstrual,
    onPrimary: Colors.white,
    primaryContainer: MoonColors.dawnTint,
    onPrimaryContainer: MoonColors.dawnTintInk,
    // Selected chips. Stronger than the card tint so a selection is obvious.
    secondaryContainer: const Color(0xFFF6C4CF),
    onSecondaryContainer: MoonColors.dawnTintInk,
    surface: MoonColors.dawn,
    onSurface: MoonColors.dawnInk,
    onSurfaceVariant: MoonColors.dawnMuted,
    surfaceContainerHighest: MoonColors.dawnLine,
    outlineVariant: MoonColors.dawnLine,
  ),
  card: MoonColors.dawnCard,
  line: MoonColors.dawnLine,
);

/// The partner's.
final ThemeData nightTheme = _build(
  ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C63C7),
    brightness: Brightness.dark,
  ).copyWith(
    primary: MoonColors.moonGold,
    onPrimary: MoonColors.moonInk,
    primaryContainer: MoonColors.nightTint,
    onPrimaryContainer: MoonColors.nightInk,
    // Selected chips. Lighter than the card so a selection is obvious.
    secondaryContainer: const Color(0xFF4A4596),
    onSecondaryContainer: MoonColors.nightInk,
    surface: MoonColors.night,
    onSurface: MoonColors.nightInk,
    onSurfaceVariant: MoonColors.nightMuted,
    surfaceContainerHighest: MoonColors.nightLine,
    outlineVariant: MoonColors.nightLine,
  ),
  card: MoonColors.nightCard,
  line: MoonColors.nightLine,
);

/// Kept for callers that still pick by brightness.
ThemeData buildTheme(Brightness brightness) =>
    brightness == Brightness.dark ? nightTheme : dawnTheme;

/// The app's type: Nunito, round and easy to read, for all text; Fredoka,
/// rounder and more playful, for headings and titles. Chosen 29 Oct 2026.
/// The MoonCycle wordmark keeps Gelasio (lib/ui/widgets/wordmark.dart).
TextTheme _type(Brightness brightness) {
  final base = GoogleFonts.nunitoTextTheme(
    ThemeData(brightness: brightness, useMaterial3: true).textTheme,
  );
  TextStyle? heading(TextStyle? style) =>
      style == null ? null : GoogleFonts.fredoka(textStyle: style);
  return base.copyWith(
    displayLarge: heading(base.displayLarge),
    displayMedium: heading(base.displayMedium),
    displaySmall: heading(base.displaySmall),
    headlineLarge: heading(base.headlineLarge),
    headlineMedium: heading(base.headlineMedium),
    headlineSmall: heading(base.headlineSmall),
    titleLarge: heading(base.titleLarge),
  );
}

/// The heading font for places that set their own size, such as the quiz.
TextStyle headingFont({double? fontSize, double? height, Color? color}) =>
    GoogleFonts.fredoka(
      fontSize: fontSize,
      height: height,
      color: color,
      fontWeight: FontWeight.w500,
    );

ThemeData _build(
  ColorScheme scheme, {
  required Color card,
  required Color line,
}) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: _type(scheme.brightness),
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: line),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      side: BorderSide(color: line),
      backgroundColor: card,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 4),
    ),
  );
}
