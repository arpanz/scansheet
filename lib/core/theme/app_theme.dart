import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

export 'tokens.dart';

extension AppThemeData on ThemeData {
  Color get themeAccent => colorScheme.primary;
  Color get themeAccentContainer => colorScheme.primaryContainer;
}

/// Legacy accessors kept so older screens keep compiling while they are
/// rebuilt. New code should use `context.ss` from tokens.dart.
extension AppThemeContext on BuildContext {
  Color get themeBg => ss.paper;
  Color get themeSurface => ss.surface;
  Color get themeCard => ss.surface;
  Color get themeBorder => ss.line;
  Color get themeAccent => ss.emerald;
  Color get themeAccentContainer => ss.emeraldTint;
  Color get themeTextPrimary => ss.ink;
  Color get themeTextSecondary => ss.muted;
  Color get themeError => ss.error;
  Color get themeSuccess => ss.emerald;
  Color get themeWarm => ss.amber;
  Color get themeSurfaceHighlight => ss.chip;
  Color get themeDetectionBorder => SsColors.brandLime;
  Color get themeSheetsBlue => const Color(0xFF1B5FCC);
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  ThemeProvider({required ThemeMode initialThemeMode})
    : _themeMode = initialThemeMode;

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final key = mode == ThemeMode.light
        ? 'light'
        : mode == ThemeMode.system
        ? 'system'
        : 'dark';
    await prefs.setString('theme_mode', key);
  }

  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setTheme(ThemeMode.dark);
    } else {
      setTheme(ThemeMode.light);
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme => _build(SsColors.light, Brightness.light);
  static ThemeData get darkTheme => _build(SsColors.dark, Brightness.dark);

  static ThemeData _build(SsColors c, Brightness brightness) {
    final base = ThemeData(useMaterial3: true, brightness: brightness);
    final textTheme = GoogleFonts.geistTextTheme(
      base.textTheme,
    ).apply(bodyColor: c.ink, displayColor: c.ink);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.emerald,
      onPrimary: brightness == Brightness.light ? Colors.white : c.onInk,
      primaryContainer: c.emeraldTint,
      onPrimaryContainer: c.emeraldDeep,
      secondary: c.ink,
      onSecondary: c.onInk,
      tertiary: c.lime,
      onTertiary: SsColors.brandInk,
      error: c.error,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surface,
      surfaceContainerHighest: c.chip,
      outline: c.strongBorder,
      outlineVariant: c.line,
      inverseSurface: c.ink,
      onInverseSurface: c.onInk,
      shadow: Colors.black,
    );

    final btnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(SsRadius.lg - 2),
    );
    final btnText = SsText.sans(size: 16, weight: FontWeight.w600);

    return base.copyWith(
      scaffoldBackgroundColor: c.paper,
      canvasColor: c.paper,
      colorScheme: scheme,
      textTheme: textTheme,
      extensions: [c],
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: SsText.sans(
          size: 17,
          weight: FontWeight.w600,
          spacing: -0.2,
          color: c.ink,
        ),
        iconTheme: IconThemeData(color: c.ink),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.onInk,
          minimumSize: const Size(64, 56),
          shape: btnShape,
          textStyle: btnText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.ink,
          foregroundColor: c.onInk,
          minimumSize: const Size(64, 52),
          shape: btnShape,
          textStyle: btnText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.surface,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: c.strongBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SsRadius.md),
          ),
          textStyle: SsText.label(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.emerald,
          textStyle: SsText.sans(size: 14, weight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: SsText.sans(color: c.muted),
        labelStyle: SsText.sans(size: 13, color: c.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SsRadius.md),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SsRadius.md),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SsRadius.md),
          borderSide: BorderSide(color: c.ink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SsRadius.md),
          borderSide: BorderSide(color: c.error),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.lineSoft, space: 1, thickness: 1),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? c.emerald
              : (brightness == Brightness.light
                    ? const Color(0xFFC9CFC6)
                    : const Color(0xFF3A4540)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        thumbIcon: const WidgetStatePropertyAll(null),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.emerald : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.emerald,
        linearTrackColor: c.track,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SsRadius.xxl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SsRadius.xl),
        ),
        titleTextStyle: SsText.section(color: c.ink),
        contentTextStyle: SsText.body(color: c.ink2),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SsColors.brandInk,
        contentTextStyle: SsText.sans(
          size: 14,
          weight: FontWeight.w500,
          color: Colors.white,
        ),
        actionTextColor: SsColors.brandLime,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SsRadius.md),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.ink,
        labelStyle: SsText.sans(
          size: 14,
          weight: FontWeight.w500,
          color: c.ink,
        ),
        side: BorderSide(color: c.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SsRadius.sm),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.ink,
        textColor: c.ink,
        titleTextStyle: SsText.label(color: c.ink),
        subtitleTextStyle: SsText.caption(color: c.muted),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
