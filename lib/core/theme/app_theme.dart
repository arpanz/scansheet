import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

extension AppThemeData on ThemeData {
  Color get themeAccent => colorScheme.primary;
  Color get themeAccentContainer => colorScheme.primaryContainer;
}

extension AppThemeContext on BuildContext {
  Color get themeBg => Theme.of(this).scaffoldBackgroundColor;
  Color get themeSurface => Theme.of(this).colorScheme.surface;
  Color get themeCard => Theme.of(this).colorScheme.surfaceContainer;
  Color get themeBorder => Theme.of(this).colorScheme.outlineVariant;
  Color get themeAccent => Theme.of(this).themeAccent;
  Color get themeAccentContainer => Theme.of(this).themeAccentContainer;
  Color get themeTextPrimary => Theme.of(this).colorScheme.onSurface;
  Color get themeTextSecondary => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get themeError => Theme.of(this).colorScheme.error;
  Color get themeSuccess => const Color(0xFF16A34A);
  Color get themeWarm => const Color(0xFFF59E0B);
  Color get themeSurfaceHighlight =>
      Theme.of(this).colorScheme.surfaceContainerHighest;
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

  // ── Dark Palette ──
  static const Color _bgDark = Color(0xFF08080B);
  static const Color _surfaceDark = Color(0xFF121215);
  static const Color _cardDark = Color(0xFF1A1A1F);
  static const Color _borderDark = Color(0xFF2A2A32);
  static const Color _accentDark = Color(0xFF22C55E);
  static const Color _accentMutedDark = Color(0x1A22C55E);
  static const Color _textPrimaryDark = Color(0xFFEDEDF0);
  static const Color _textSecondaryDark = Color(0xFF8B8B92);

  // ── Light Palette ──
  static const Color _bgLight = Color(0xFFF8F8FB);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _cardLight = Color(0xFFF3F3F7);
  static const Color _borderLight = Color(0xFFE4E4EB);
  static const Color _accentLight = Color(0xFF16A34A);
  static const Color _accentMutedLight = Color(0x1A16A34A);
  static const Color _textPrimaryLight = Color(0xFF18181B);
  static const Color _textSecondaryLight = Color(0xFF71717A);

  static const Color _errorColor = Color(0xFFEF4444);

  // ── Radius scale ──
  static const double _rSm = 10;
  static const double _rMd = 14;
  static const double _rLg = 18;
  static const double _rXl = 24;

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: _textPrimaryDark,
      displayColor: _textPrimaryDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bgDark,
      primaryColor: _accentDark,
      colorScheme: const ColorScheme.dark(
        primary: _accentDark,
        primaryContainer: _accentMutedDark,
        secondary: _accentDark,
        surface: _surfaceDark,
        surfaceContainer: _cardDark,
        surfaceContainerHighest: Color(0xFF222229),
        error: _errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: _textPrimaryDark,
        onSurfaceVariant: _textSecondaryDark,
        outlineVariant: _borderDark,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _bgDark,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: _accentDark.withValues(alpha: 0.04),
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _textPrimaryDark,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: _textPrimaryDark),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceDark,
        indicatorColor: _accentMutedDark,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _accentDark, size: 22);
          }
          return const IconThemeData(color: _textSecondaryDark, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? _accentDark
              : _textSecondaryDark;
          return GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.1,
          );
        }),
        elevation: 0,
        height: 64,
      ),
      elevatedButtonTheme: _elevatedBtn(_accentDark),
      filledButtonTheme: _filledBtn(_accentDark),
      outlinedButtonTheme: _outlinedBtn(_accentDark),
      inputDecorationTheme: _inputDeco(
        _cardDark,
        _borderDark,
        _accentDark,
        _textSecondaryDark,
      ),
      dividerTheme: const DividerThemeData(
        color: _borderDark,
        space: 1,
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _cardDark,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_rXl)),
        ),
      ),
      snackBarTheme: _snackBar(const Color(0xFF1C1C22), _textPrimaryDark),
      dialogTheme: DialogThemeData(
        backgroundColor: _cardDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rLg),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _cardDark,
        labelStyle: TextStyle(
          color: _textPrimaryDark,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rSm),
          side: BorderSide(color: _borderDark),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: _textPrimaryLight,
      displayColor: _textPrimaryLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _bgLight,
      primaryColor: _accentLight,
      colorScheme: const ColorScheme.light(
        primary: _accentLight,
        primaryContainer: _accentMutedLight,
        secondary: _accentLight,
        surface: _surfaceLight,
        surfaceContainer: _cardLight,
        surfaceContainerHighest: Color(0xFFECECF1),
        error: _errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: _textPrimaryLight,
        onSurfaceVariant: _textSecondaryLight,
        outlineVariant: _borderLight,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _bgLight,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: _accentLight.withValues(alpha: 0.04),
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: _textPrimaryLight,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(color: _textPrimaryLight),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceLight,
        indicatorColor: _accentMutedLight,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _accentLight, size: 22);
          }
          return const IconThemeData(color: _textSecondaryLight, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? _accentLight
              : _textSecondaryLight;
          return GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: color,
            letterSpacing: 0.1,
          );
        }),
        elevation: 0,
        height: 64,
      ),
      elevatedButtonTheme: _elevatedBtn(_accentLight),
      filledButtonTheme: _filledBtn(_accentLight),
      outlinedButtonTheme: _outlinedBtn(_accentLight),
      inputDecorationTheme: _inputDeco(
        _cardLight,
        _borderLight,
        _accentLight,
        _textSecondaryLight,
      ),
      dividerTheme: const DividerThemeData(
        color: _borderLight,
        space: 1,
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(_rXl)),
        ),
      ),
      snackBarTheme: _snackBar(const Color(0xFF18181B), Colors.white),
      dialogTheme: DialogThemeData(
        backgroundColor: _surfaceLight,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rLg),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _cardLight,
        labelStyle: TextStyle(
          color: _textPrimaryLight,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_rSm),
          side: BorderSide(color: _borderLight),
        ),
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedBtn(Color accent) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_rMd),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: -0.1,
          ),
        ),
      );

  static FilledButtonThemeData _filledBtn(Color accent) =>
      FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_rMd),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: -0.1,
          ),
        ),
      );

  static OutlinedButtonThemeData _outlinedBtn(Color accent) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_rMd),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: -0.1,
          ),
        ),
      );

  static InputDecorationTheme _inputDeco(
    Color card,
    Color border,
    Color accent,
    Color hint,
  ) => InputDecorationTheme(
      filled: true,
      fillColor: card,
      hintStyle: TextStyle(color: hint, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_rMd),
        borderSide: BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_rMd),
        borderSide: BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_rMd),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

  static SnackBarThemeData _snackBar(Color bg, Color text) => SnackBarThemeData(
    backgroundColor: bg,
    contentTextStyle: GoogleFonts.inter(
      color: text,
      fontSize: 13.5,
      fontWeight: FontWeight.w500,
    ),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_rMd)),
    behavior: SnackBarBehavior.floating,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    elevation: 0,
  );
}
