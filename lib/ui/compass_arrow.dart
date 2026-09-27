import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../destination/bearing_engine.dart';

class CompassArrow extends StatefulWidget {
  const CompassArrow({
    super.key,
    required this.relativeAngle,
    required this.size,
  });

  final double? relativeAngle;
  final double size;

  @override
  State<CompassArrow> createState() => _CompassArrowState();
}

class _CompassArrowState extends State<CompassArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController.unbounded(
    vsync: this,
  );
  bool _hasAngle = false;

  @override
  void initState() {
    super.initState();
    _updateAngle();
  }

  @override
  void didUpdateWidget(covariant CompassArrow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativeAngle != widget.relativeAngle) _updateAngle();
  }

  void _updateAngle() {
    final angle = widget.relativeAngle;
    if (angle == null) {
      _rotation.stop();
      _hasAngle = false;
      return;
    }
    if (!_hasAngle) {
      _rotation.value = BearingEngine.normalize(angle);
      _hasAngle = true;
      return;
    }
    final turn = BearingEngine.shortestDelta(_rotation.value, angle);
    if (turn.abs() < 0.15) return;
    _rotation.animateTo(
      _rotation.value + turn,
      duration: Duration(
        milliseconds: (90 + turn.abs() * 1.7).clamp(90, 260).round(),
      ),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF10294A),
        border: Border.all(color: const Color(0xFF416081), width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(widget.size * 0.15),
        child: AnimatedBuilder(
          animation: _rotation,
          builder: (_, _) => Transform.rotate(
            angle: _rotation.value * math.pi / 180,
            child: CustomPaint(
              painter: _ArrowPainter(enabled: widget.relativeAngle != null),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.enabled});
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final shaft = Path()
      ..moveTo(center.dx, size.height * 0.10)
      ..lineTo(size.width * 0.83, size.height * 0.77)
      ..lineTo(center.dx, size.height * 0.61)
      ..lineTo(size.width * 0.17, size.height * 0.77)
      ..close();
    final paint = Paint()
      ..color = enabled ? const Color(0xFF63DCF4) : const Color(0xFF6D8198)
      ..style = PaintingStyle.fill;
    canvas.drawShadow(shaft, const Color(0xFF4CBFD9), enabled ? 13 : 0, false);
    canvas.drawPath(shaft, paint);
    canvas.drawLine(
      Offset(center.dx, size.height * 0.15),
      Offset(center.dx, size.height * 0.56),
      Paint()
        ..color = enabled ? const Color(0xFFD9FBFF) : const Color(0xFFA6B7C6)
        ..strokeWidth = size.width * 0.055
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      enabled != oldDelegate.enabled;
}
