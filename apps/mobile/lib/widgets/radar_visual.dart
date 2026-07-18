import 'dart:math' as math;

import 'package:flutter/material.dart';

class RadarVisual extends StatefulWidget {
  const RadarVisual({
    super.key,
    this.size = 280,
    this.glowColor = const Color(0xFF4FC3F7),
  });

  final double size;
  final Color glowColor;

  @override
  State<RadarVisual> createState() => _RadarVisualState();
}

class _RadarVisualState extends State<RadarVisual> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _RadarPainter(
              sweep: _controller.value * math.pi * 2,
              glowColor: widget.glowColor,
            ),
          ),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.sweep, required this.glowColor});

  final double sweep;
  final Color glowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final backgroundPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: 0.22),
          const Color(0xFF0B1020),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, backgroundPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = glowColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;

    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ringPaint);
    }

    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), axisPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), axisPaint);

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          glowColor.withValues(alpha: 0),
          glowColor.withValues(alpha: 0.45),
        ],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.92),
      sweep - 0.18,
      0.26,
      true,
      sweepPaint,
    );

    final sweepLinePaint = Paint()
      ..color = glowColor.withValues(alpha: 0.9)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(
        center.dx + math.cos(sweep) * radius * 0.92,
        center.dy + math.sin(sweep) * radius * 0.92,
      ),
      sweepLinePaint,
    );

    final blipPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    final blips = <Offset>[
      Offset(center.dx - radius * 0.25, center.dy - radius * 0.22),
      Offset(center.dx + radius * 0.15, center.dy - radius * 0.12),
      Offset(center.dx + radius * 0.28, center.dy + radius * 0.18),
    ];
    for (final blip in blips) {
      canvas.drawCircle(blip, 3.5, blipPaint);
      canvas.drawCircle(blip, 9, blipPaint..color = glowColor.withValues(alpha: 0.12));
      blipPaint.color = Colors.white.withValues(alpha: 0.9);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.sweep != sweep || oldDelegate.glowColor != glowColor;
  }
}

