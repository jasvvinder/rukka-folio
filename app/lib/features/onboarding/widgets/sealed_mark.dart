// The sealed mark (11 brand guidelines, ADR 2026-09-03d): a book silhouette
// with a strap and a wax seal, painted from the geometry of record —
// `docs/brand/icons/master/mark-sealed.svg` (88-unit box: book 12..76 r5, two
// entry rules at x54, strap x28 w14 y14..74 at .93, seal at (28,56) r10) — in
// the mark tokens, never ad-hoc hex values (CLAUDE.md § Layout). The canvas
// frames embed exactly this SVG at the size each one draws — c3 S15 face
// states 60 px, c3 *PIN instead* 48 px, c1 S15.3 52 px — so the size is the
// caller's (s15_lock_screen.dart `_LockPage`).
import 'package:flutter/material.dart';

import '../../../shared/tokens.dart';

/// Draws the sealed→open mark. [sealOpacity] is 1 for fully sealed, 0 for
/// fully open (the seal has broken); callers animate it for the unlock
/// moment and otherwise hold it at 1 or 0 (ADR 2026-09-03d rule 3).
class SealedMark extends StatelessWidget {
  const SealedMark({super.key, this.sealOpacity = 1, this.size = 96});

  final double sealOpacity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final book = dark ? RkMarkDark.book : RkMarkLight.book;
    final strap = dark ? RkMarkDark.strap : RkMarkLight.strap;
    final seal = dark ? RkMarkDark.seal : RkMarkLight.seal;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(
          book: book,
          strap: strap,
          seal: seal,
          sealOpacity: sealOpacity,
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({
    required this.book,
    required this.strap,
    required this.seal,
    required this.sealOpacity,
  });

  final Color book;
  final Color strap;
  final Color seal;
  final double sealOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    // Master art units (mark-sealed.svg viewBox 0 0 88 88).
    final u = size.shortestSide / 88;
    Rect r(double x, double y, double w, double h) =>
        Rect.fromLTWH(x * u, y * u, w * u, h * u);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r(12, 12, 64, 64), Radius.circular(5 * u)),
      Paint()..color = book,
    );
    final rule = Radius.circular(2.25 * u);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r(54, 33, 16, 4.5), rule),
      Paint()..color = strap,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r(54, 46.5, 16, 4.5), rule),
      Paint()..color = strap.withValues(alpha: 0.55),
    );
    canvas.drawRect(
      r(28, 14, 14, 60),
      Paint()..color = strap.withValues(alpha: 0.93),
    );
    if (sealOpacity > 0) {
      canvas.drawCircle(
        Offset(28 * u, 56 * u),
        10 * u,
        Paint()..color = seal.withValues(alpha: sealOpacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.book != book ||
      oldDelegate.strap != strap ||
      oldDelegate.seal != seal ||
      oldDelegate.sealOpacity != sealOpacity;
}
