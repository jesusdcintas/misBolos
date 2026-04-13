import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/app_haptics.dart';

class CobradoConfettiButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final Color color;

  const CobradoConfettiButton({
    super.key,
    required this.onPressed,
    this.label = 'Marcar como cobrado ✓',
    this.icon = Icons.check_circle,
    this.color = AppColors.primary,
  });

  @override
  State<CobradoConfettiButton> createState() => _CobradoConfettiButtonState();
}

class _CobradoConfettiButtonState extends State<CobradoConfettiButton> {
  late ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  void _handleCobrar() async {
    AppHaptics.heavy();
    widget.onPressed();
    _confetti.play();
    await Future.delayed(const Duration(milliseconds: 100));
    AppHaptics.medium();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        ConfettiWidget(
          confettiController: _confetti,
          blastDirectionality: BlastDirectionality.explosive,
          numberOfParticles: 20,
          maxBlastForce: 20,
          minBlastForce: 5,
          emissionFrequency: 0.05,
          gravity: 0.3,
          colors: [
            widget.color,
            widget.color.withValues(alpha: 0.7),
            AppColors.primary,
            AppColors.successBg,
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _handleCobrar,
            icon: Icon(widget.icon, size: 18),
            label: Text(widget.label),
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}
