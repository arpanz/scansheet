import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ScanSheet design tokens. Source of truth: docs/design/mocks/Foundations.dc.html
/// and docs/REDESIGN_PLAN.md. Lime is a signal for scan moments only — never
/// use it as a text color on light backgrounds.
class SsColors extends ThemeExtension<SsColors> {
  final Color paper; // scaffold background
  final Color surface; // cards, sheets
  final Color ink; // primary text, primary button
  final Color onInk; // text on primary button
  final Color ink2; // secondary text
  final Color muted; // tertiary text, captions
  final Color line; // card borders
  final Color lineSoft; // dividers inside cards
  final Color chip; // neutral tag/icon tile fill
  final Color strongBorder; // secondary button border
  final Color track; // segmented control / switch off track
  final Color emerald; // links, synced, accents
  final Color emeraldTint; // emerald icon tile
  final Color emeraldDeep; // text on emerald tint
  final Color lime; // scan signal
  final Color limeRow; // freshly scanned row / list tag
  final Color hero; // in-progress card background
  final Color heroLine;
  final Color heroMuted;
  final Color amber;
  final Color amberText;
  final Color error;
  final Color scanButton; // centre nav button fill
  final Color scanButtonIcon;
  final Color avatar;
  final Color onAvatar;

  const SsColors({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.onInk,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.lineSoft,
    required this.chip,
    required this.strongBorder,
    required this.track,
    required this.emerald,
    required this.emeraldTint,
    required this.emeraldDeep,
    required this.lime,
    required this.limeRow,
    required this.hero,
    required this.heroLine,
    required this.heroMuted,
    required this.amber,
    required this.amberText,
    required this.error,
    required this.scanButton,
    required this.scanButtonIcon,
    required this.avatar,
    required this.onAvatar,
  });

  // Fixed brand values shared by both modes and by the always-dark camera UI.
  static const Color brandLime = Color(0xFFD4F56A);
  static const Color brandInk = Color(0xFF0B1210);
  static const Color night = Color(0xFF0B0F0D);
  static const Color nightSurface = Color(0xFF141A17);
  static const Color nightRaised = Color(0xFF18201C);
  static const Color nightLine = Color(0xFF2C3631);
  static const Color nightMuted = Color(0xFFAEB8B2);
  static const Color nightText = Color(0xFFC9D2CC);
  static const Color live = Color(0xFF9BC31F);

  static const light = SsColors(
    paper: Color(0xFFF5F6F2),
    surface: Color(0xFFFFFFFF),
    ink: Color(0xFF0B1210),
    onInk: Color(0xFFFFFFFF),
    ink2: Color(0xFF4A5550),
    muted: Color(0xFF5F6964),
    line: Color(0xFFE3E6E0),
    lineSoft: Color(0xFFEEF0EB),
    chip: Color(0xFFF0F2EE),
    strongBorder: Color(0xFFD3D8D1),
    track: Color(0xFFE9ECE6),
    emerald: Color(0xFF0B7D45),
    emeraldTint: Color(0xFFE3F4EA),
    emeraldDeep: Color(0xFF075E33),
    lime: brandLime,
    limeRow: Color(0xFFEEF9C8),
    hero: Color(0xFF0B1210),
    heroLine: Color(0x00000000),
    heroMuted: Color(0xFFAEB8B2),
    amber: Color(0xFFD97706),
    amberText: Color(0xFFA15C07),
    error: Color(0xFFB42318),
    scanButton: Color(0xFF0B1210),
    scanButtonIcon: brandLime,
    avatar: Color(0xFF0B1210),
    onAvatar: brandLime,
  );

  static const dark = SsColors(
    paper: Color(0xFF0E1311),
    surface: Color(0xFF161C19),
    ink: Color(0xFFEEF2EF),
    onInk: Color(0xFF0B1210),
    ink2: Color(0xFFC3CCC7),
    muted: Color(0xFF9AA5A0),
    line: Color(0xFF252D29),
    lineSoft: Color(0xFF252D29),
    chip: Color(0x0FFFFFFF),
    strongBorder: Color(0xFF34403A),
    track: Color(0x14FFFFFF),
    emerald: Color(0xFF4FC48A),
    emeraldTint: Color(0x244FC48A),
    emeraldDeep: Color(0xFF4FC48A),
    lime: brandLime,
    limeRow: Color(0x1FD4F56A),
    hero: Color(0xFF182019),
    heroLine: Color(0xFF2A3530),
    heroMuted: Color(0xFF9AA5A0),
    amber: Color(0xFFF2B45A),
    amberText: Color(0xFFF2B45A),
    error: Color(0xFFF97066),
    scanButton: brandLime,
    scanButtonIcon: brandInk,
    avatar: brandLime,
    onAvatar: brandInk,
  );

  @override
  SsColors copyWith() => this;

  @override
  SsColors lerp(ThemeExtension<SsColors>? other, double t) =>
      t < 0.5 || other is! SsColors ? this : other;
}

/// Radius scale: 10 · 14 · 18 · 24 · 28.
class SsRadius {
  SsRadius._();
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 28;
}

/// Type ramp. Geist for UI, Geist Mono for codes, counts and cells.
class SsText {
  SsText._();

  static TextStyle sans({
    double size = 15,
    FontWeight weight = FontWeight.w400,
    double? spacing,
    double? height,
    Color? color,
  }) => GoogleFonts.geist(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    height: height,
    color: color,
  );

  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    double? spacing,
    double? height,
    Color? color,
  }) => GoogleFonts.geistMono(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    height: height,
    color: color,
  );

  static TextStyle display({Color? color}) => sans(
    size: 44,
    weight: FontWeight.w600,
    spacing: -1.6,
    height: 1.02,
    color: color,
  );
  static TextStyle title({Color? color}) =>
      sans(
    size: 30,
    weight: FontWeight.w600,
    spacing: -0.9,
    height: 1.1,
    color: color,
  );
  static TextStyle heading({Color? color}) =>
      sans(
    size: 24,
    weight: FontWeight.w600,
    spacing: -0.6,
    height: 1.15,
    color: color,
  );
  static TextStyle section({Color? color}) =>
      sans(size: 17, weight: FontWeight.w600, spacing: -0.2, color: color);
  static TextStyle label({Color? color}) =>
      sans(size: 15, weight: FontWeight.w600, color: color);
  static TextStyle body({Color? color}) =>
      sans(size: 15, height: 1.45, color: color);
  static TextStyle caption({Color? color}) => sans(size: 12, color: color);
  static TextStyle eyebrow({Color? color}) =>
      mono(size: 12, weight: FontWeight.w500, spacing: 1, color: color);
}

extension SsThemeContext on BuildContext {
  SsColors get ss => Theme.of(this).extension<SsColors>() ?? SsColors.light;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
