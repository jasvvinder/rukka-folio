// The huge QR of S9.2 (07 §12 🔒). The widget paints a matrix; it never
// encodes one — [QrModules] is the seam, so a test can hand in a known square
// and the screen stays a screen.
//
// The payload itself comes from `core_crypto`'s [QrPayload] (04 §6.1); nothing
// here reads a key or a fingerprint.
import 'package:flutter/material.dart';
// ⚠️ WIRE — `qr` resolves today only as a transitive dependency of `pdf`'s
// `barcode`. It belongs in `app/pubspec.yaml` as a direct dependency; that
// file is the shell lane's (lane report M7-U4b `open`).
import 'package:qr/qr.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// A square of QR modules: [size] per side, [isDark] per cell.
abstract class QrModules {
  /// Encodes [payload] at error-correction level M — the level the ceremony
  /// payload's ~130 base64url characters fit comfortably, and enough to
  /// survive a phone screen photographed off a video call (04 §6.4 remote).
  factory QrModules.of(String payload) = _EncodedQrModules;

  /// Modules per side (21 for version 1, rising with the payload).
  int get size;

  /// True where the module is dark.
  bool isDark(int row, int col);
}

final class _EncodedQrModules implements QrModules {
  _EncodedQrModules(String payload)
    : _image = QrImage(
        QrCode.fromData(
          data: payload,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        ),
      );

  final QrImage _image;

  @override
  int get size => _image.moduleCount;

  @override
  bool isDark(int row, int col) => _image.isDark(row, col);
}

/// A fixed square for tests and previews — a checkerboard of [size] modules.
final class FakeQrModules implements QrModules {
  /// Creates a [size]×[size] checkerboard.
  const FakeQrModules({this.size = 25});

  @override
  final int size;

  @override
  bool isDark(int row, int col) => (row + col).isEven;
}

/// The QR itself: ink modules on paper, with the four-module quiet zone the
/// format requires, sized to the width it is given.
///
/// Ink and paper come from the theme, so the square inverts correctly in dark
/// mode (07 §1 rule 10) and never carries a hex literal.
class RkQrView extends StatelessWidget {
  /// Draws [modules]; [semanticsLabel] is what a screen reader hears — the
  /// square can never be read aloud, so the label points at the digits below.
  const RkQrView({
    super.key,
    required this.modules,
    required this.semanticsLabel,
  });

  /// The matrix to paint.
  final QrModules modules;

  /// Spoken description.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Paper under the square in both themes: a QR is only scannable
            // with light modules light and dark modules dark.
            color: scheme.surface,
            borderRadius: BorderRadius.circular(RkRadius.md),
            border: Border.all(color: status.hairline),
          ),
          child: CustomPaint(
            painter: _QrPainter(
              modules: modules,
              ink: scheme.onSurface,
              paper: scheme.surface,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter({
    required this.modules,
    required this.ink,
    required this.paper,
  });

  final QrModules modules;
  final Color ink;
  final Color paper;

  /// The format's mandatory margin, in modules.
  static const _quietZone = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    if (side <= 0) return;
    final count = modules.size + _quietZone * 2;
    final cell = side / count;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = paper,
    );
    final fill = Paint()..color = ink;
    for (var row = 0; row < modules.size; row++) {
      for (var col = 0; col < modules.size; col++) {
        if (!modules.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (col + _quietZone) * cell,
            (row + _quietZone) * cell,
            // A hair of overlap; without it the printer-thin seams between
            // modules make the square harder to read at small sizes.
            cell + 0.5,
            cell + 0.5,
          ),
          fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) =>
      old.modules != modules || old.ink != ink || old.paper != paper;
}
