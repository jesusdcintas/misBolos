import 'package:flutter/material.dart';
import '../../core/utils/app_haptics.dart';
import '../../core/constants/app_colors.dart';

class AnimatedFacturableToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const AnimatedFacturableToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<AnimatedFacturableToggle> createState() =>
      _AnimatedFacturableToggleState();
}

class _AnimatedFacturableToggleState extends State<AnimatedFacturableToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(AnimatedFacturableToggle old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    AppHaptics.select();
    widget.onChanged(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final color = ColorTween(
            begin: AppColors.purple,
            end: AppColors.success,
          ).evaluate(_controller)!;

          return Container(
            width: 56,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutBack,
                  left: widget.value ? 28 : 2,
                  top: 2,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        widget.value ? Icons.receipt_outlined : Icons.money_off_outlined,
                        size: 14,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
