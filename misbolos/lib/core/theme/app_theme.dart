import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_theme_colors.dart';

class AppTheme {
  AppTheme._();

  static const _radius = 12.0;

  static ThemeData get light => _build(
    brightness: Brightness.light,
    colors: AppThemeColors.light,
    primary: const Color(0xFF1B2A4A),
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    colors: AppThemeColors.dark,
    primary: const Color(0xFF7BA2FF),
  );

  static ThemeData _build({
    required Brightness brightness,
    required AppThemeColors colors,
    required Color primary,
  }) {
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: primary,
      primary: primary,
      surface: colors.surface,
      error: colors.error,
      onPrimary: Colors.white,
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
    );

    final textTheme = Typography.material2021(platform: TargetPlatform.iOS)
        .black
        .apply(
          bodyColor: colors.textPrimary,
          displayColor: colors.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.scaffoldBackground,
      textTheme: textTheme,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          inherit: true,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        shape: Border(
          bottom: BorderSide(color: colors.border, width: 0.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.0 : 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.border, width: 0.6),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: isDark ? 2 : 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.modalBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border, width: 0.6),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: colors.error),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(fontSize: 14, color: colors.textSecondary),
        hintStyle: TextStyle(fontSize: 14, color: colors.textMuted),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: colors.textPrimary),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceElevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.border),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        textStyle: TextStyle(color: colors.textPrimary),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceElevated),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(
            inherit: true,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            inherit: true,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
            inherit: true,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: isDark ? colors.surfaceContainer : colors.infoBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 70,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            inherit: true,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? primary : colors.navInactive,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primary : colors.navInactive,
            size: 24,
          );
        }),
      ),
      dividerTheme: DividerThemeData(color: colors.border, thickness: 0.6),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.surfaceElevated,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceContainer,
        selectedColor: colors.infoBg,
        disabledColor: colors.surfaceContainer,
        labelStyle: TextStyle(fontSize: 13, color: colors.textPrimary),
        secondaryLabelStyle: TextStyle(fontSize: 13, color: colors.textPrimary),
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(colors.inputBackground),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        textStyle: WidgetStatePropertyAll(TextStyle(color: colors.textPrimary)),
        hintStyle: WidgetStatePropertyAll(TextStyle(color: colors.textMuted)),
        side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: TextStyle(
          inherit: true,
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        ),
        subtitleTextStyle: TextStyle(
          inherit: true,
          fontSize: 13,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}
