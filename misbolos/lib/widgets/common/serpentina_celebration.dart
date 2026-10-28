import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/app_haptics.dart';

Future<void> showCobradoSerpentina(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Celebración de cobro',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, __) {
      return const _CobradoSerpentinaOverlay();
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(fade),
          child: child,
        ),
      );
    },
  );
}

class _CobradoSerpentinaOverlay extends StatefulWidget {
  const _CobradoSerpentinaOverlay();

  @override
  State<_CobradoSerpentinaOverlay> createState() =>
      _CobradoSerpentinaOverlayState();
}

class _CobradoSerpentinaOverlayState extends State<_CobradoSerpentinaOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_StreamerSpec> _streamers;
  late final List<_SparkSpec> _sparks;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    AppHaptics.medium();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    _streamers = _buildStreamers();
    _sparks = _buildSparks();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _autoCloseTimer ??= Timer(const Duration(milliseconds: 250), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<_StreamerSpec> _buildStreamers() {
    final random = math.Random();
    final colors = <Color>[
      AppColors.success,
      AppColors.warning,
      AppColors.primary,
      AppColors.fiscal,
      AppColors.purple,
      const Color(0xFFF1C40F),
    ];

    return List.generate(14, (index) {
      final color = colors[index % colors.length];
      return _StreamerSpec(
        anchorFactor: 0.08 + random.nextDouble() * 0.84,
        delay: random.nextDouble() * 0.35,
        amplitude: 18 + random.nextDouble() * 22,
        drift: -22 + random.nextDouble() * 44,
        waves: 2.5 + random.nextDouble() * 2.5,
        phase: random.nextDouble() * math.pi * 2,
        thickness: 5.5 + random.nextDouble() * 2.5,
        lengthFactor: 0.78 + random.nextDouble() * 0.22,
        color: color,
      );
    });
  }

  List<_SparkSpec> _buildSparks() {
    final random = math.Random();
    return List.generate(18, (index) {
      return _SparkSpec(
        startXFactor: 0.18 + random.nextDouble() * 0.64,
        startYFactor: 0.16 + random.nextDouble() * 0.24,
        radius: 1.5 + random.nextDouble() * 2.5,
        delay: random.nextDouble() * 0.25,
        travelXFactor: -0.08 + random.nextDouble() * 0.16,
        travelYFactor: 0.08 + random.nextDouble() * 0.12,
        color: index.isEven ? AppColors.success : AppColors.warning,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: SizedBox.expand(
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _SerpentinaPainter(
                        progress: _controller.value,
                        streamers: _streamers,
                        sparks: _sparks,
                      ),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.center,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final pulse = Curves.easeOutBack.transform(
                      math.min(_controller.value * 1.3, 1.0),
                    );
                    return Transform.scale(
                      scale: 0.92 + pulse * 0.08,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.18),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.celebration,
                              color: AppColors.success,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '¡Cobrado!',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreamerSpec {
  final double anchorFactor;
  final double delay;
  final double amplitude;
  final double drift;
  final double waves;
  final double phase;
  final double thickness;
  final double lengthFactor;
  final Color color;

  const _StreamerSpec({
    required this.anchorFactor,
    required this.delay,
    required this.amplitude,
    required this.drift,
    required this.waves,
    required this.phase,
    required this.thickness,
    required this.lengthFactor,
    required this.color,
  });
}

class _SparkSpec {
  final double startXFactor;
  final double startYFactor;
  final double radius;
  final double delay;
  final double travelXFactor;
  final double travelYFactor;
  final Color color;

  const _SparkSpec({
    required this.startXFactor,
    required this.startYFactor,
    required this.radius,
    required this.delay,
    required this.travelXFactor,
    required this.travelYFactor,
    required this.color,
  });
}

class _SerpentinaPainter extends CustomPainter {
  final double progress;
  final List<_StreamerSpec> streamers;
  final List<_SparkSpec> sparks;

  _SerpentinaPainter({
    required this.progress,
    required this.streamers,
    required this.sparks,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ribbonPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final sparkPaint = Paint()..style = PaintingStyle.fill;

    for (final streamer in streamers) {
      final localProgress = ((progress - streamer.delay) / 0.85).clamp(
        0.0,
        1.0,
      );
      if (localProgress <= 0) continue;
      final eased = Curves.easeOutCubic.transform(localProgress);
      final startY = -40.0;
      final endY = size.height * (0.16 + 0.72 * eased * streamer.lengthFactor);
      final anchorX = size.width * streamer.anchorFactor;
      final path = Path();
      final segments = 18;
      for (var i = 0; i <= segments; i++) {
        final t = i / segments;
        final y = _lerpDouble(startY, endY, t);
        final wave =
            math.sin((t * math.pi * 2 * streamer.waves) + streamer.phase) *
            streamer.amplitude *
            (0.35 + eased * 0.75);
        final drift = streamer.drift * t * (0.25 + eased * 0.75);
        final x = anchorX + wave + drift;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      ribbonPaint
        ..color = streamer.color.withValues(alpha: 0.82 * (1 - eased * 0.35))
        ..strokeWidth = streamer.thickness * (0.7 + eased * 0.7);
      canvas.drawPath(path, ribbonPaint);
    }

    for (final spark in sparks) {
      final localProgress = ((progress - spark.delay) / 0.6).clamp(0.0, 1.0);
      if (localProgress <= 0) continue;
      final eased = Curves.easeOut.transform(localProgress);
      final dx =
          size.width * spark.startXFactor +
          size.width * spark.travelXFactor * eased;
      final dy =
          size.height * spark.startYFactor +
          size.height * spark.travelYFactor * eased;
      final opacity = (1 - eased).clamp(0.0, 1.0);
      sparkPaint.color = spark.color.withValues(alpha: opacity);
      canvas.drawCircle(Offset(dx, dy), spark.radius * (1 + eased), sparkPaint);
    }
  }

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(covariant _SerpentinaPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.streamers != streamers ||
        oldDelegate.sparks != sparks;
  }
}
