import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

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
    final bgColor = facturable ? AppColors.successBg : AppColors.purpleBg;
    final textColor = facturable ? AppColors.success : AppColors.purple;
    final label = facturable ? 'Facturable' : 'En B';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 8,
        vertical: large ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
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
