import 'package:flutter/material.dart';

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final Color scaffoldBackground;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceElevated;
  final Color cardBackground;
  final Color inputBackground;
  final Color modalBackground;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color navInactive;
  final Color success;
  final Color successBg;
  final Color warning;
  final Color warningBg;
  final Color error;
  final Color errorBg;
  final Color info;
  final Color infoBg;

  const AppThemeColors({
    required this.scaffoldBackground,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceElevated,
    required this.cardBackground,
    required this.inputBackground,
    required this.modalBackground,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.navInactive,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.error,
    required this.errorBg,
    required this.info,
    required this.infoBg,
  });

  static const light = AppThemeColors(
    scaffoldBackground: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceContainer: Color(0xFFEEF1F7),
    surfaceElevated: Color(0xFFFFFFFF),
    cardBackground: Color(0xFFFFFFFF),
    inputBackground: Color(0xFFF7F8FA),
    modalBackground: Color(0xFFFFFFFF),
    border: Color(0xFFEAEDF2),
    textPrimary: Color(0xFF0D1B2A),
    textSecondary: Color(0xFF8C95A6),
    textMuted: Color(0xFFA8B0BC),
    navInactive: Color(0xFFB0B8C6),
    success: Color(0xFF1B8A56),
    successBg: Color(0xFFE8F6EF),
    warning: Color(0xFFB7680A),
    warningBg: Color(0xFFFEF3E2),
    error: Color(0xFFC0392B),
    errorBg: Color(0xFFFDEEEE),
    info: Color(0xFF1B2A4A),
    infoBg: Color(0xFFEEF1F7),
  );

  static const dark = AppThemeColors(
    scaffoldBackground: Color(0xFF0B1220),
    surface: Color(0xFF111827),
    surfaceContainer: Color(0xFF1E293B),
    surfaceElevated: Color(0xFF243247),
    cardBackground: Color(0xFF243247),
    inputBackground: Color(0xFF1E293B),
    modalBackground: Color(0xFF111827),
    border: Color(0xFF314158),
    textPrimary: Color(0xFFE5E7EB),
    textSecondary: Color(0xFF9CA3AF),
    textMuted: Color(0xFF94A3B8),
    navInactive: Color(0xFF94A3B8),
    success: Color(0xFF4DBA7B),
    successBg: Color(0xFF123126),
    warning: Color(0xFFF0B35A),
    warningBg: Color(0xFF3D2C12),
    error: Color(0xFFF87171),
    errorBg: Color(0xFF3F1A1A),
    info: Color(0xFF7BA2FF),
    infoBg: Color(0xFF1B2A4A),
  );

  @override
  AppThemeColors copyWith({
    Color? scaffoldBackground,
    Color? surface,
    Color? surfaceContainer,
    Color? surfaceElevated,
    Color? cardBackground,
    Color? inputBackground,
    Color? modalBackground,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? navInactive,
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
    Color? error,
    Color? errorBg,
    Color? info,
    Color? infoBg,
  }) {
    return AppThemeColors(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      surface: surface ?? this.surface,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      cardBackground: cardBackground ?? this.cardBackground,
      inputBackground: inputBackground ?? this.inputBackground,
      modalBackground: modalBackground ?? this.modalBackground,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      navInactive: navInactive ?? this.navInactive,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      error: error ?? this.error,
      errorBg: errorBg ?? this.errorBg,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      scaffoldBackground: Color.lerp(scaffoldBackground, other.scaffoldBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceContainer: Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      modalBackground: Color.lerp(modalBackground, other.modalBackground, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      navInactive: Color.lerp(navInactive, other.navInactive, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      error: Color.lerp(error, other.error, t)!,
      errorBg: Color.lerp(errorBg, other.errorBg, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
    );
  }
}

extension AppThemeColorsX on BuildContext {
  AppThemeColors get colors => Theme.of(this).extension<AppThemeColors>()!;
}
