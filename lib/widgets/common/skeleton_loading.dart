import 'package:flutter/material.dart';

class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const baseColor = Color(0xFFEAEDF2);
    const shimmerColor = Color(0xFFF7F8FA);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [baseColor, shimmerColor, baseColor],
              stops: [
                (_animation.value - 1).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 1).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

class GigCardSkeleton extends StatelessWidget {
  const GigCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SkeletonBox(width: 44, height: 44, borderRadius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 140, height: 14, borderRadius: 7),
                  const SizedBox(height: 6),
                  const SkeletonBox(width: 100, height: 11, borderRadius: 6),
                  const SizedBox(height: 8),
                  Row(
                    children: const [
                      SkeletonBox(width: 80, height: 22, borderRadius: 11),
                      SizedBox(width: 6),
                      SkeletonBox(width: 70, height: 22, borderRadius: 11),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SkeletonBox(height: 100, borderRadius: 16),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 80, borderRadius: 14)),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 80, borderRadius: 14)),
            ],
          ),
          const SizedBox(height: 8),
          const SkeletonBox(height: 80, borderRadius: 14),
          const SizedBox(height: 16),
          ...List.generate(
            4,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: GigCardSkeleton(),
            ),
          ),
        ],
      ),
    );
  }
}

class InvoiceCardSkeleton extends StatelessWidget {
  const InvoiceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SkeletonBox(width: 44, height: 44, borderRadius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 120, height: 14, borderRadius: 7),
                  SizedBox(height: 6),
                  SkeletonBox(width: 90, height: 11, borderRadius: 6),
                ],
              ),
            ),
            const SkeletonBox(width: 70, height: 22, borderRadius: 11),
          ],
        ),
      ),
    );
  }
}

class ClientCardSkeleton extends StatelessWidget {
  const ClientCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SkeletonBox(width: 44, height: 44, borderRadius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 130, height: 14, borderRadius: 7),
                  SizedBox(height: 6),
                  SkeletonBox(width: 80, height: 11, borderRadius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
