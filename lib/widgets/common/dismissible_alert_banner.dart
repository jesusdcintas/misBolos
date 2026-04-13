import 'package:flutter/material.dart';
import '../../core/utils/app_haptics.dart';

class DismissibleAlertBanner extends StatefulWidget {
  final Widget child;

  const DismissibleAlertBanner({super.key, required this.child});

  @override
  State<DismissibleAlertBanner> createState() => _DismissibleAlertBannerState();
}

class _DismissibleAlertBannerState extends State<DismissibleAlertBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    AppHaptics.light();
    await _controller.reverse();
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.velocity.pixelsPerSecond.dy < -300) {
          _dismiss();
        }
      },
      child: FadeTransition(
        opacity: _controller,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(_controller),
          child: widget.child,
        ),
      ),
    );
  }
}
