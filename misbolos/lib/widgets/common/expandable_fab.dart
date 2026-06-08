import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/app_haptics.dart';

class ExpandableFAB extends StatefulWidget {
  final List<FABAction> actions;

  const ExpandableFAB({super.key, required this.actions});

  @override
  State<ExpandableFAB> createState() => _ExpandableFABState();
}

class FABAction {
  final IconData icon;
  final String label;
  final Color color;
  final void Function(BuildContext context) onTap;

  const FABAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _ExpandableFABState extends State<ExpandableFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _isOpen = !_isOpen);
    if (_isOpen) {
      _controller.forward();
      AppHaptics.medium();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ...widget.actions.asMap().entries.map((entry) {
          final delay = entry.key * 0.15;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final rawProgress = ((_controller.value - delay) / (1 - delay)).clamp(0.0, 1.0);
              final progress = Curves.easeOutBack.transform(rawProgress);
              return Transform.scale(
                scale: progress,
                child: Opacity(
                  opacity: progress.clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [
                              BoxShadow(color: Colors.black12, blurRadius: 8),
                            ],
                          ),
                          child: Text(
                            entry.value.label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FloatingActionButton.small(
                          heroTag: entry.value.label,
                          backgroundColor: entry.value.color,
                          onPressed: () {
                            _toggle();
                            entry.value.onTap(context);
                          },
                          child: Icon(entry.value.icon,
                              color: Colors.white, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }).toList().reversed,
        FloatingActionButton(
          onPressed: _toggle,
          backgroundColor: AppColors.primary,
          child: AnimatedRotation(
            turns: _isOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
