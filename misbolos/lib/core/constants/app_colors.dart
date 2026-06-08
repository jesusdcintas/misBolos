import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // === LIGHT MODE (Principal) ===
  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFEAEDF2);

  // Textos
  static const Color textPrimary = Color(0xFF0D1B2A);
  static const Color textSecondary = Color(0xFF8C95A6);
  static const Color textMuted = Color(0xFFA8B0BC);
  static const Color textInactive = Color(0xFFB0B8C6);

  // Primario
  static const Color primary = Color(0xFF1B2A4A);
  static const Color primaryLight = Color(0xFFEEF1F7);

  // Semánticos
  static const Color success = Color(0xFF1B8A56);
  static const Color successBg = Color(0xFFE8F6EF);
  static const Color warning = Color(0xFFB7680A);
  static const Color warningBg = Color(0xFFFEF3E2);
  static const Color error = Color(0xFFC0392B);
  static const Color errorBg = Color(0xFFFDEEEE);
  static const Color purple = Color(0xFF5B2C8D);
  static const Color purpleBg = Color(0xFFF3E8FC);
  static const Color fiscal = Color(0xFF0F5C9E);
  static const Color fiscalBg = Color(0xFFE7F1FB);
  static const Color draft = Color(0xFF5F5E5A);
  static const Color draftBg = Color(0xFFF1EFE8);

  // Dividers
  static const Color divider = Color(0xFFEAEDF2);

  // Legacy - mantener compatibilidad
  static const Color accentGreen = success;
  static const Color accentOrange = warning;
  static const Color accentRed = error;
  static const Color accentPurple = purple;

  // === DARK MODE ===
  static const Color darkBackground = Color(0xFF0D1B2A);
  static const Color darkSurface = Color(0xFF1B2A4A);
  static const Color darkCard = Color(0xFF243B55);
  static const Color darkTextPrimary = Color(0xFFF7F8FA);
  static const Color darkTextSecondary = Color(0xFF8C95A6);
  static const Color darkCardBorder = Color(0xFF3D5A80);
}
