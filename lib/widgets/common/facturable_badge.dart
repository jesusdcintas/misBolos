import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_theme_colors.dart';

class FacturableBadge extends StatelessWidget {
  final bool facturable;
  final bool large;

  const FacturableBadge({
    super.key,
    required this.facturable,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = context.colors;
    final bgColor = isDark
        ? facturable
              ? colors.successBg.withValues(alpha: 0.6)
              : colors.surfaceElevated
        : facturable
        ? AppColors.successBg
        : AppColors.purpleBg;
    final textColor = isDark
        ? facturable
              ? colors.success
              : colors.textSecondary
        : facturable
        ? AppColors.success
        : AppColors.purple;
    final label = facturable ? 'Facturable' : 'En B';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 8,
        vertical: large ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: isDark
            ? Border.all(color: colors.border.withValues(alpha: 0.6))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            facturable ? Icons.receipt_outlined : Icons.money_off_outlined,
            size: large ? 16 : 12,
            color: textColor,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: large ? 13 : 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}
