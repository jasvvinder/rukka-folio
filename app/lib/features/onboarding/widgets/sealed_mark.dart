// The sealed mark (11 brand guidelines, ADR 2026-09-03d): a book silhouette
// with a strap and a wax seal. Embed the master art per brand rule — this is
// a token-driven placeholder shape (no master SVG asset was handed to this
// lane), never redrawn with ad-hoc hex values (CLAUDE.md § Layout).
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
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide * 0.12),
    );
    canvas.drawRRect(r, Paint()..color = book);
    final strapRect = Rect.fromLTWH(
      size.width * 0.46,
      0,
      size.width * 0.08,
      size.height,
    );
    canvas.drawRect(strapRect, Paint()..color = strap);
    if (sealOpacity > 0) {
      canvas.drawCircle(
        Offset(size.width / 2, size.height * 0.62),
        size.shortestSide * 0.16,
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
