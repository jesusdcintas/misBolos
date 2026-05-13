import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
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

  Color get _backgroundColor {
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

  Color get _textColor {
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

  @override
  Widget build(BuildContext context) {
    final shouldPulse = status == GigStatus.confirmado ||
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
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: large ? 13 : 11,
          fontWeight: FontWeight.w600,
          color: _textColor,
        ),
      ),
    );
    return PulsingBadge(active: shouldPulse, child: badge);
  }
}
