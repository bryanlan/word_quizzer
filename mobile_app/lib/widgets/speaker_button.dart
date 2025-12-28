import 'package:flutter/material.dart';

class SpeakerButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double size;
  final Color backgroundColor;
  final Color iconColor;

  const SpeakerButton({
    super.key,
    required this.onPressed,
    this.size = 40,
    this.backgroundColor = Colors.tealAccent,
    this.iconColor = Colors.black,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: CustomPaint(
              size: Size(size * 0.55, size * 0.55),
              painter: _SpeakerPainter(iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeakerPainter extends CustomPainter {
  final Color color;

  const _SpeakerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final bodyRect = Rect.fromLTWH(w * 0.06, h * 0.32, w * 0.22, h * 0.36);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(w * 0.06)),
      fillPaint,
    );

    final cone = Path()
      ..moveTo(w * 0.28, h * 0.32)
      ..lineTo(w * 0.56, h * 0.18)
      ..lineTo(w * 0.56, h * 0.82)
      ..lineTo(w * 0.28, h * 0.68)
      ..close();
    canvas.drawPath(cone, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 0.08;

    final center = Offset(w * 0.56, h * 0.50);
    final rect1 = Rect.fromCircle(center: center, radius: w * 0.28);
    final rect2 = Rect.fromCircle(center: center, radius: w * 0.42);

    // Only the right side of the circle (sound waves)
    canvas.drawArc(rect1, -0.6, 1.2, false, strokePaint);
    canvas.drawArc(rect2, -0.6, 1.2, false, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _SpeakerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

