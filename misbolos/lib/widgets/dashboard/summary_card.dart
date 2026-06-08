import 'package:flutter/material.dart';
import '../../core/theme/app_theme_colors.dart';
import '../common/animated_counter.dart';

class SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onInfoTap;
  final bool showChevron;
  final Color? backgroundColor;
  final double? numericValue;

  const SummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    this.subtitle,
    this.onTap,
    this.onInfoTap,
    this.showChevron = false,
    this.backgroundColor,
    this.numericValue,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final card = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onInfoTap != null)
                GestureDetector(
                  onTap: onInfoTap,
                  child: Icon(
                    Icons.info_outline,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                )
              else if (showChevron)
                Text(
                  '›',
                  style: TextStyle(
                    fontSize: 16,
                    color: colors.border,
                    fontWeight: FontWeight.w300,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (numericValue != null)
            AnimatedCounter(
              value: numericValue!,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            subtitle!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      );
    }
    return card;
  }
}
