import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme_colors.dart';
import '../../models/gig.dart';
import 'pulsing_badge.dart';

class StatusBadge extends StatelessWidget {
  final GigStatus status;
  final bool? facturable;
  final bool large;

  const StatusBadge({
    super.key,
    required this.status,
    this.facturable,
    this.large = false,
  });

  Color _lightBackgroundColor() {
    switch (status) {
      case GigStatus.confirmado:
        return AppColors.primaryLight; // #EEF1F7
      case GigStatus.facturado:
        return AppColors.warningBg; // #FEF3E2
      case GigStatus.confirmadoB:
      case GigStatus.realizadoB:
      case GigStatus.cobradoB:
        return AppColors.purpleBg; // #F3E8FC
      case GigStatus.cobrado:
        return AppColors.successBg; // #E8F6EF
      case GigStatus.cancelado:
        return AppColors.errorBg; // #FDEEEE
    }
  }

  Color _lightTextColor() {
    switch (status) {
      case GigStatus.confirmado:
        return AppColors.primary; // #1B2A4A
      case GigStatus.facturado:
        return AppColors.warning; // #B7680A
      case GigStatus.confirmadoB:
      case GigStatus.realizadoB:
      case GigStatus.cobradoB:
        return AppColors.purple; // #5B2C8D
      case GigStatus.cobrado:
        return AppColors.success; // #1B8A56
      case GigStatus.cancelado:
        return AppColors.error; // #C0392B
    }
  }

  Color _darkBackgroundColor(BuildContext context) {
    final colors = context.colors;
    switch (status) {
      case GigStatus.confirmado:
        return colors.infoBg.withValues(alpha: 0.45);
      case GigStatus.facturado:
        return colors.warningBg.withValues(alpha: 0.55);
      case GigStatus.confirmadoB:
      case GigStatus.realizadoB:
      case GigStatus.cobradoB:
        return colors.surfaceElevated;
      case GigStatus.cobrado:
        return colors.successBg.withValues(alpha: 0.6);
      case GigStatus.cancelado:
        return colors.errorBg.withValues(alpha: 0.6);
    }
  }

  Color _darkTextColor(BuildContext context) {
    final colors = context.colors;
    switch (status) {
      case GigStatus.confirmado:
        return colors.info;
      case GigStatus.facturado:
        return colors.warning;
      case GigStatus.confirmadoB:
      case GigStatus.realizadoB:
      case GigStatus.cobradoB:
        return colors.textSecondary;
      case GigStatus.cobrado:
        return colors.success;
      case GigStatus.cancelado:
        return colors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shouldPulse =
        status == GigStatus.confirmado ||
        status == GigStatus.facturado ||
        status == GigStatus.confirmadoB ||
        status == GigStatus.realizadoB;
    final label = status.label;
    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: isDark ? _darkBackgroundColor(context) : _lightBackgroundColor(),
        borderRadius: BorderRadius.circular(20),
        border: isDark
            ? Border.all(color: context.colors.border.withValues(alpha: 0.6))
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: large ? 13 : 11,
          fontWeight: FontWeight.w600,
          color: isDark ? _darkTextColor(context) : _lightTextColor(),
        ),
      ),
    );
    return PulsingBadge(active: shouldPulse, child: badge);
  }
}
