import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// STATIC COLOR CONSTANTS  (dark theme — backward compatible)
// ─────────────────────────────────────────────────────────────────────────────
class AppColors {
  // Dark
  static const Color background    = Color(0xFF0D1117);
  static const Color cardDark      = Color(0xFF161B22);
  static const Color accent        = Color(0xFF58A6FF);
  static const Color success       = Color(0xFF2EA043);
  static const Color danger        = Color(0xFFDA3633);
  static const Color textWhite     = Color(0xFFF0F6FC);
  static const Color textGrey      = Color(0xFF8B949E);

  // Light
  static const Color backgroundLight = Color(0xFFF6F8FA);
  static const Color cardLight        = Color(0xFFFFFFFF);
  static const Color accentLight      = Color(0xFF0969DA);
  static const Color successLight     = Color(0xFF1A7F37);
  static const Color dangerLight      = Color(0xFFCF222E);
  static const Color textDark         = Color(0xFF1F2328);
  static const Color textGreyLight    = Color(0xFF656D76);
  static const Color borderLight      = Color(0xFFD0D7DE);
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTEXT-AWARE COLOR SCHEME
// Usage: final c = AppColorScheme.of(context);  then c.background, c.card …
// ─────────────────────────────────────────────────────────────────────────────
class AppColorScheme {
  final Color background;
  final Color card;
  final Color accent;
  final Color success;
  final Color danger;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final bool isDark;

  const AppColorScheme._({
    required this.background,
    required this.card,
    required this.accent,
    required this.success,
    required this.danger,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.isDark,
  });

  static AppColorScheme of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  static const AppColorScheme dark = AppColorScheme._(
    background:    AppColors.background,
    card:          AppColors.cardDark,
    accent:        AppColors.accent,
    success:       AppColors.success,
    danger:        AppColors.danger,
    textPrimary:   AppColors.textWhite,
    textSecondary: AppColors.textGrey,
    border:        Color(0xFF30363D),
    isDark:        true,
  );

  static const AppColorScheme light = AppColorScheme._(
    background:    AppColors.backgroundLight,
    card:          AppColors.cardLight,
    accent:        AppColors.accentLight,
    success:       AppColors.successLight,
    danger:        AppColors.dangerLight,
    textPrimary:   AppColors.textDark,
    textSecondary: AppColors.textGreyLight,
    border:        AppColors.borderLight,
    isDark:        false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// APP THEME  —  full ThemeData for dark and light
// ─────────────────────────────────────────────────────────────────────────────
class AppTheme {
  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    bg:         AppColors.background,
    card:       AppColors.cardDark,
    accent:     AppColors.accent,
    success:    AppColors.success,
    danger:     AppColors.danger,
    textPri:    AppColors.textWhite,
    textSec:    AppColors.textGrey,
    border:     const Color(0xFF30363D),
    inputFill:  AppColors.cardDark,
    hint:       Colors.white30,
  );

  static ThemeData get light => _build(
    brightness: Brightness.light,
    bg:         AppColors.backgroundLight,
    card:       AppColors.cardLight,
    accent:     AppColors.accentLight,
    success:    AppColors.successLight,
    danger:     AppColors.dangerLight,
    textPri:    AppColors.textDark,
    textSec:    AppColors.textGreyLight,
    border:     AppColors.borderLight,
    inputFill:  AppColors.cardLight,
    hint:       const Color(0xFFADB5BD),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color card,
    required Color accent,
    required Color success,
    required Color danger,
    required Color textPri,
    required Color textSec,
    required Color border,
    required Color inputFill,
    required Color hint,
  }) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness:       brightness,
        primary:          accent,
        onPrimary:        isDark ? Colors.black : Colors.white,
        secondary:        success,
        onSecondary:      Colors.white,
        error:            danger,
        onError:          Colors.white,
        surface:          card,
        onSurface:        textPri,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPri,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: textPri,
          fontWeight: FontWeight.bold,
          fontSize: 18,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: textPri),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bg,
        indicatorColor: card,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            color: selected ? accent : textSec,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border.withOpacity(0.5)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border.withOpacity(0.5),
        thickness: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent.withOpacity(0.4)
              : Colors.grey.withOpacity(0.2),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor:   accent,
        inactiveTrackColor: card,
        thumbColor:         isDark ? Colors.white : accent,
        overlayColor:       accent.withOpacity(0.2),
        trackHeight:        4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled:          true,
        fillColor:       inputFill,
        hintStyle:       TextStyle(color: hint),
        labelStyle:      TextStyle(color: textSec),
        contentPadding:  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: danger, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: isDark ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      listTileTheme: ListTileThemeData(
        textColor:  textPri,
        iconColor:  textSec,
        tileColor:  Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: card,
        contentTextStyle: TextStyle(color: textPri),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          color: textPri,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
        contentTextStyle: TextStyle(color: textSec, fontSize: 14),
      ),
    );
  }
}