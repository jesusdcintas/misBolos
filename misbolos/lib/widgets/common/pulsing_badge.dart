import 'package:flutter/material.dart';

class PulsingBadge extends StatefulWidget {
  final Widget child;
  final bool active;

  const PulsingBadge({
    super.key,
    required this.child,
    this.active = false,
  });

  @override
  State<PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<PulsingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.active) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _controller.repeat(reverse: true);
      });
    }
  }

  @override
  void didUpdateWidget(PulsingBadge old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && old.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || MediaQuery.of(context).disableAnimations) {
      return widget.child;
    }
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
