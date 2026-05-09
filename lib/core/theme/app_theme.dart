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
  Color get themeSuccess => const Color(0xFF30D158);
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

  // Dark Palette
  static const Color _bgDark = Color(0xFF0D0D0F);
  static const Color _surfaceDark = Color(0xFF1A1A1E); // +13 steps from bg
  static const Color _cardDark = Color(0xFF26262B); // +12 steps from surface
  static const Color _borderDark = Color(0xFF3C3C42); // visible at ~2.5:1 on bg
  static const Color _accentDark = Color(
    0xFF4F8EF7,
  ); // lighter blue — readable on dark
  static const Color _accentMutedDark = Color(0x2E4F8EF7);
  static const Color _textPrimaryDark = Color(0xFFE8E8EA);
  static const Color _textSecondaryDark = Color(0xFF8E8E93);

  // Light Palette
  static const Color _bgLight = Color(0xFFF2F2F7);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _cardLight = Color(0xFFF7F7F9);
  static const Color _borderLight = Color(0xFFDDDDE2);
  static const Color _accentLight = Color(0xFF1D4ED8);
  static const Color _accentMutedLight = Color(0x221D4ED8);
  static const Color _textPrimaryLight = Color(0xFF1C1C1E);
  static const Color _textSecondaryLight = Color(0xFF8E8E93);

  static const Color _errorColor = Color(0xFFFF453A);

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: _textPrimaryDark, displayColor: _textPrimaryDark);

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
        scrolledUnderElevation: 1,
        surfaceTintColor: _accentDark.withValues(alpha: 0.05),
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: _textPrimaryDark,
          letterSpacing: -0.4,
        ),
        iconTheme: const IconThemeData(color: _textPrimaryDark),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceDark,
        indicatorColor: _accentMutedDark,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _accentDark);
          }
          return const IconThemeData(color: _textSecondaryDark);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? _accentDark
              : _textSecondaryDark;
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          );
        }),
        elevation: 0,
        height: 60,
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
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: _snackBar(_cardDark, _textPrimaryDark),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(
      base.textTheme,
    ).apply(bodyColor: _textPrimaryLight, displayColor: _textPrimaryLight);

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
        scrolledUnderElevation: 1,
        surfaceTintColor: _accentLight.withValues(alpha: 0.05),
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: _textPrimaryLight,
          letterSpacing: -0.4,
        ),
        iconTheme: const IconThemeData(color: _textPrimaryLight),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surfaceLight,
        indicatorColor: _accentMutedLight,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _accentLight);
          }
          return const IconThemeData(color: _textSecondaryLight);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final color = states.contains(WidgetState.selected)
              ? _accentLight
              : _textSecondaryLight;
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          );
        }),
        elevation: 0,
        height: 60,
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
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _surfaceLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: _snackBar(const Color(0xFF1C1C1E), Colors.white),
    );
  }

  static ElevatedButtonThemeData _elevatedBtn(Color accent) =>
      ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
        ),
      );

  static FilledButtonThemeData _filledBtn(Color accent) =>
      FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
        ),
      );

  static OutlinedButtonThemeData _outlinedBtn(Color accent) =>
      OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.1,
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
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: border, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: border, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: accent, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );

  static SnackBarThemeData _snackBar(Color bg, Color text) => SnackBarThemeData(
    backgroundColor: bg,
    contentTextStyle: GoogleFonts.inter(color: text, fontSize: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    behavior: SnackBarBehavior.floating,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    elevation: 4,
  );
}
