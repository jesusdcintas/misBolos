import 'package:flutter/material.dart';

class DJRefreshIndicator extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const DJRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      displacement: 60,
      child: child,
    );
  }
}

class EQBars extends StatefulWidget {
  final double progress;

  const EQBars({super.key, this.progress = 1.0});

  @override
  State<EQBars> createState() => _EQBarsState();
}

class _EQBarsState extends State<EQBars> with TickerProviderStateMixin {
  late List<AnimationController> _bars;

  @override
  void initState() {
    super.initState();
    _bars = List.generate(
      5,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300 + i * 80),
      )..repeat(reverse: true),
    );
  }

  @override
  void dispose() {
    for (final bar in _bars) {
      bar.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(5, (i) {
        final heights = [16.0, 24.0, 32.0, 24.0, 16.0];
        return AnimatedBuilder(
          animation: _bars[i],
          builder: (context, child) {
            return Container(
              width: 4,
              height: heights[i] * _bars[i].value * widget.progress,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1B8A56),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        );
      }),
    );
  }
}
