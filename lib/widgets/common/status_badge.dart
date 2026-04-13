import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/gig.dart';
import 'pulsing_badge.dart';

class StatusBadge extends StatelessWidget {
  final GigStatus status;
  final bool large;

  const StatusBadge({super.key, required this.status, this.large = false});

  Color get _backgroundColor {
    switch (status) {
      case GigStatus.pendiente:
        return AppColors.primaryLight; // #EEF1F7
      case GigStatus.facturaGenerada:
        return AppColors.primaryLight;
      case GigStatus.facturaEnviada:
        return AppColors.warningBg; // #FEF3E2
      case GigStatus.pagado:
        return AppColors.successBg; // #E8F6EF
      case GigStatus.cancelado:
        return AppColors.errorBg; // #FDEEEE
      case GigStatus.cobradoEnB:
        return AppColors.purpleBg; // #F3E8FC
    }
  }

  Color get _textColor {
    switch (status) {
      case GigStatus.pendiente:
        return AppColors.primary; // #1B2A4A
      case GigStatus.facturaGenerada:
        return AppColors.primary;
      case GigStatus.facturaEnviada:
        return AppColors.warning; // #B7680A
      case GigStatus.pagado:
        return AppColors.success; // #1B8A56
      case GigStatus.cancelado:
        return AppColors.error; // #C0392B
      case GigStatus.cobradoEnB:
        return AppColors.purple; // #5B2C8D
    }
  }

  @override
  Widget build(BuildContext context) {
    final shouldPulse = status == GigStatus.pendiente || status == GigStatus.facturaEnviada;
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
        status.label,
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
