// The Face ID glyph the canvas draws (c3 S15 *waiting for Face ID* / *Face not
// recognised*, c1 S15.3 *Face ID* button): four rounded corner brackets round
// a face. Material has no such icon — its face icons draw a whole head — so
// the canvas's 24-unit stroke art is painted here, in the colour it is given
// (a token from the caller, never a literal).
import 'package:flutter/widgets.dart';

/// Paints the glyph at [size] in [color]. [compact] is the button form (dot
/// eyes, no nose, a heavier stroke, as the 19 px glyph in c1 S15.3); the
/// default is the large form of c3 S15 (line eyes, a nose, a lighter stroke).
class FaceIdGlyph extends StatelessWidget {
  const FaceIdGlyph({
    super.key,
    required this.size,
    required this.color,
    this.compact = false,
    this.semanticLabel,
  });

  final double size;
  final Color color;
  final bool compact;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _FaceIdPainter(color: color, compact: compact),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: glyph);
    return Semantics(label: semanticLabel, image: true, child: glyph);
  }
}

class _FaceIdPainter extends CustomPainter {
  const _FaceIdPainter({required this.color, required this.compact});

  final Color color;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    // The canvas art's own units: viewBox 0 0 24 24.
    canvas.scale(size.shortestSide / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 1.8 : 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const r = Radius.circular(2);
    final brackets = Path()
      // M4 8V6a2 2 0 0 1 2-2h2
      ..moveTo(4, 8)
      ..lineTo(4, 6)
      ..arcToPoint(const Offset(6, 4), radius: r)
      ..lineTo(8, 4)
      // M16 4h2a2 2 0 0 1 2 2v2
      ..moveTo(16, 4)
      ..lineTo(18, 4)
      ..arcToPoint(const Offset(20, 6), radius: r)
      ..lineTo(20, 8)
      // M20 16v2a2 2 0 0 1-2 2h-2
      ..moveTo(20, 16)
      ..lineTo(20, 18)
      ..arcToPoint(const Offset(18, 20), radius: r)
      ..lineTo(16, 20)
      // M8 20H6a2 2 0 0 1-2-2v-2
      ..moveTo(8, 20)
      ..lineTo(6, 20)
      ..arcToPoint(const Offset(4, 18), radius: r)
      ..lineTo(4, 16);
    canvas.drawPath(brackets, stroke);

    if (compact) {
      // M9 10h.01M15 10h.01 — round-capped dots.
      final dot = Paint()..color = color;
      canvas
        ..drawCircle(const Offset(9, 10), stroke.strokeWidth / 2, dot)
        ..drawCircle(const Offset(15, 10), stroke.strokeWidth / 2, dot);
      // M9 15c.8.7 1.9 1 3 1s2.2-.3 3-1
      final smile = Path()
        ..moveTo(9, 15)
        ..cubicTo(9.8, 15.7, 10.9, 16, 12, 16)
        ..cubicTo(13.1, 16, 14.2, 15.7, 15, 15);
      canvas.drawPath(smile, stroke);
      return;
    }
    // M9 10v1.5 · M15 10v1.5 · M12 10v3.5 · M9.5 16a4 4 0 0 0 5 0
    final face = Path()
      ..moveTo(9, 10)
      ..lineTo(9, 11.5)
      ..moveTo(15, 10)
      ..lineTo(15, 11.5)
      ..moveTo(12, 10)
      ..lineTo(12, 13.5)
      ..moveTo(9.5, 16)
      ..arcToPoint(
        const Offset(14.5, 16),
        radius: const Radius.circular(4),
        clockwise: false,
      );
    canvas.drawPath(face, stroke);
  }

  @override
  bool shouldRepaint(covariant _FaceIdPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.compact != compact;
}
