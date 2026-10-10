import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors from the design (Claude Artifact "Jarvis 스피커 앱 디자인", Jarvis speaker app design). Contrast AA or better under white text
class AppColors {
  AppColors._();

  /// The speaker's teal standby LED, darkened (5.9:1 contrast with white text)
  static const accent = Color(0xFF0B6E6D);
  static const accentDark = Color(0xFF084F4E);
  static const accentSoft = Color(0xFFE1F0EF);
  static const accentOnDark = Color(0xFF9BE7C4);
  static const ink = Color(0xFF15201F);
  static const muted = Color(0xFF4B5957);
  static const line = Color(0xFFDCE2E0);
  static const divider = Color(0xFFEEF1F0);
  static const ground = Color(0xFFF2F4F3);
  static const card = Colors.white;

  /// Warning and delete (amber, AA contrast with white text)
  static const warn = Color(0xFF9A4A07);
  static const warnSoft = Color(0xFFFBEBD9);
  static const ok = Color(0xFF1F6B3A);

  // Dark theme
  static const groundDark = Color(0xFF0F1716);
  static const cardDark = Color(0xFF1A2423);
  static const lineDark = Color(0xFF2C3A38);
  static const accentDarkTheme = Color(0xFF5CC8C2);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: AppColors.accent,
          onPrimary: Colors.white,
          primaryContainer: AppColors.accentSoft,
          onPrimaryContainer: AppColors.accent,
          secondary: AppColors.ink,
          onSecondary: Colors.white,
          error: AppColors.warn,
          onError: Colors.white,
          errorContainer: AppColors.warnSoft,
          onErrorContainer: AppColors.warn,
          surface: AppColors.card,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.muted,
          outline: AppColors.line,
          outlineVariant: AppColors.divider,
          surfaceContainerLowest: AppColors.ground,
        ),
        ground: AppColors.ground,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: AppColors.accentDarkTheme,
          onPrimary: AppColors.ink,
          primaryContainer: Color(0xFF173D3B),
          onPrimaryContainer: AppColors.accentOnDark,
          secondary: Colors.white,
          onSecondary: AppColors.ink,
          error: Color(0xFFF2A65A),
          onError: AppColors.ink,
          errorContainer: Color(0xFF3D2A16),
          onErrorContainer: Color(0xFFF7C99A),
          surface: AppColors.cardDark,
          onSurface: Color(0xFFE8EEED),
          onSurfaceVariant: Color(0xFFA9B6B4),
          outline: AppColors.lineDark,
          outlineVariant: Color(0xFF243130),
          surfaceContainerLowest: AppColors.groundDark,
        ),
        ground: AppColors.groundDark,
      );

  static ThemeData _build({required Brightness brightness, required ColorScheme scheme, required Color ground}) {
    final base = ThemeData(brightness: brightness, colorScheme: scheme, useMaterial3: true);
    final text = GoogleFonts.ibmPlexSansKrTextTheme(base.textTheme).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final radius = BorderRadius.circular(14);
    return base.copyWith(
      scaffoldBackgroundColor: ground,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.35),
        titleLarge: text.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
        bodySmall: text.bodySmall?.copyWith(fontSize: 13, height: 1.5, color: scheme.onSurfaceVariant),
        labelLarge: text.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: scheme.outline),
          foregroundColor: scheme.onSurface,
          textStyle: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: text.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.outline)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.error, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: scheme.error, width: 1.5)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outline,
        thumbColor: scheme.surface,
        trackHeight: 6,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
