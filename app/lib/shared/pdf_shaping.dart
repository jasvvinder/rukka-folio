// Complex-script shaping for `package:pdf` documents (desk 183 c).
//
// pdf 3.13 shapes only Arabic and bidi — no GSUB, no Indic reordering — so a
// Gurmukhi or Devanagari line set as PDF text prints misspelled: a pre-base
// vowel sign (ਿ / ि) lands after its consonant, a conjunct shows its halant,
// a nukta drifts ('ਰਿਕਵਰੀ' → 'ਰਕਿਵਰੀ'). Every line that carries those
// scripts is therefore laid out by the engine's own paragraph (HarfBuzz — the
// same shaping every screen of the app gets), in the app's own faces (Mukta /
// Mukta Mahee, 11 §4.4), and placed on the page as an image at
// [pdfShapingRasterScale] × its point size — print resolution. Latin text,
// which pdf 3.13 sets correctly, stays vector text.
//
// First written for the paper recovery sheet (04 §7.4 🔒, ADR 2026-10-06d),
// moved here unchanged so the S8.2 / S4 report PDF can use it too.
//
// Everything here must run where `dart:ui` can rasterise: the UI isolate in
// the app, `tester.runAsync` in a widget test.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdf/widgets.dart' as pw;

import 'theme.dart' show rkFontFallback;
import 'tokens.dart';

/// Device pixels per point of a shaped line — 4 × 72 = 288 dpi, print
/// resolution for 10 pt text.
const double pdfShapingRasterScale = 4;

/// Whether [text] carries a rune `package:pdf` cannot shape: Devanagari
/// (U+0900–U+097F, U+A8E0–U+A8FF) or Gurmukhi (U+0A00–U+0A7F).
bool needsComplexShaping(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0900 && rune <= 0x097F) ||
        (rune >= 0x0A00 && rune <= 0x0A7F) ||
        (rune >= 0xA8E0 && rune <= 0xA8FF)) {
      return true;
    }
  }
  return false;
}

/// A line shaped by the engine and drawn to an image: [png] at
/// [rasterScale] × the point size, to be placed at [width] × [height] points.
final class ShapedLine {
  /// Wraps the drawn line.
  const ShapedLine({
    required this.png,
    required this.width,
    required this.height,
  });

  /// The drawn paragraph, transparent behind the ink.
  final Uint8List png;

  /// Its size on the page, in points.
  final double width;

  /// Its size on the page, in points.
  final double height;

  /// Device pixels per point of [png].
  static const double rasterScale = pdfShapingRasterScale;
}

/// Lays [text] out with the engine's paragraph — full complex-script shaping
/// — in the app's faces, wrapped at [maxWidth] points, and draws it.
///
/// [align] sets the paragraph's own alignment (a right-aligned cell wraps
/// right-aligned); null leaves the engine's default.
Future<ShapedLine> shapePdfLine(
  String text, {
  required double size,
  required ui.Color color,
  required double maxWidth,
  bool bold = false,
  ui.TextAlign? align,
}) async {
  final weight = bold ? ui.FontWeight.w600 : ui.FontWeight.w400;
  final builder =
      ui.ParagraphBuilder(
          align == null
              ? ui.ParagraphStyle(
                  fontFamily: RkType.family,
                  fontSize: size,
                  fontWeight: weight,
                )
              : ui.ParagraphStyle(
                  fontFamily: RkType.family,
                  fontSize: size,
                  fontWeight: weight,
                  textAlign: align,
                ),
        )
        ..pushStyle(
          ui.TextStyle(
            color: color,
            fontFamily: RkType.family,
            fontFamilyFallback: rkFontFallback,
            fontSize: size,
            fontWeight: weight,
          ),
        )
        ..addText(text);
  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: maxWidth));
  final width = paragraph.longestLine.ceilToDouble().clamp(1.0, maxWidth);
  final height = paragraph.height.ceilToDouble().clamp(1.0, double.infinity);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(pdfShapingRasterScale);
  // A right- or centre-aligned paragraph is laid out across [maxWidth]; the
  // image keeps only the ink, so shift it back to the left edge.
  final shift = align == null || align == ui.TextAlign.start
      ? 0.0
      : -_inkLeft(paragraph);
  canvas.drawParagraph(paragraph, ui.Offset(shift, 0));
  final picture = recorder.endRecording();
  paragraph.dispose();
  final image = await picture.toImage(
    (width * pdfShapingRasterScale).ceil(),
    (height * pdfShapingRasterScale).ceil(),
  );
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return ShapedLine(
      png: data!.buffer.asUint8List(),
      width: width,
      height: height,
    );
  } finally {
    image.dispose();
  }
}

/// The left edge of the leftmost line of [paragraph].
double _inkLeft(ui.Paragraph paragraph) {
  final lines = paragraph.computeLineMetrics();
  if (lines.isEmpty) return 0;
  var left = double.infinity;
  for (final line in lines) {
    if (line.left < left) left = line.left;
  }
  return left.isFinite ? left : 0;
}

typedef _LineKey = (
  String text,
  double size,
  bool bold,
  int argb,
  double maxWidth,
  ui.TextAlign? align,
);

/// Shapes lines for one document, once each.
///
/// A page builder of `package:pdf` is synchronous and shaping is not, so a
/// document is built in two steps: every builder asks [line] for its text —
/// the first time, that queues the shaping and answers null (draw nothing
/// yet) — then [settle] waits for the queue, and the second build gets the
/// shaped images. A string asked for again with the same style is shaped
/// once and embedded once: the same [pw.MemoryImage] is handed back, and
/// `package:pdf` writes one image object per provider.
///
/// Queuing a line only records it; [settle] draws the queue at most
/// [maxConcurrent] lines at a time. A year-long Punjabi day book asks for
/// thousands of lines in one pass, and starting every rasterisation at once
/// held every in-flight picture and bitmap at the same moment (REP183C review
/// finding 1: ~600 MB for 3,000 rows in the drawing phase alone).
final class PdfLineShaper {
  /// An empty shaper; one per document.
  PdfLineShaper({this.maxConcurrent = 4})
    : assert(maxConcurrent > 0, 'at least one line must be drawn at a time');

  /// How many lines [settle] draws at once.
  final int maxConcurrent;

  final Map<_LineKey, Future<ShapedLine> Function()> _pending = {};
  final Map<_LineKey, ({pw.MemoryImage image, ShapedLine line})> _done = {};

  /// Every text this shaper has drawn — for a test to see which route a
  /// line took.
  Set<String> get shapedTexts => {for (final key in _done.keys) key.$1};

  /// How many lines were rasterised — repeated strings count once.
  int get shapeCount => _done.length;

  /// The shaped [text] as a widget, or null when it is still queued (or
  /// needs no shaping: see [needsComplexShaping]).
  pw.Widget? line(
    String text, {
    required double size,
    required ui.Color color,
    required double maxWidth,
    bool bold = false,
    ui.TextAlign? align,
  }) {
    if (!needsComplexShaping(text)) return null;
    final key = (text, size, bold, color.toARGB32(), maxWidth, align);
    final done = _done[key];
    if (done != null) {
      return pw.Image(
        done.image,
        width: done.line.width,
        height: done.line.height,
      );
    }
    _pending.putIfAbsent(
      key,
      () =>
          () => shapePdfLine(
            text,
            size: size,
            color: color,
            maxWidth: maxWidth,
            bold: bold,
            align: align,
          ),
    );
    return null;
  }

  /// Whether a [line] call has been queued and not yet shaped.
  bool get hasPending => _pending.isNotEmpty;

  /// The most lines that were ever being drawn at once — for a test to see
  /// that [maxConcurrent] holds.
  int get peakInFlight => _peakInFlight;
  int _peakInFlight = 0;

  /// Shapes everything queued since the last call, [maxConcurrent] at a time.
  Future<void> settle() async {
    while (_pending.isNotEmpty) {
      final queue = _pending.entries.toList();
      _pending.clear();
      var next = 0;
      var inFlight = 0;
      Future<void> worker() async {
        while (next < queue.length) {
          final entry = queue[next++];
          inFlight++;
          if (inFlight > _peakInFlight) _peakInFlight = inFlight;
          try {
            final shaped = await entry.value();
            _done[entry.key] = (
              image: pw.MemoryImage(shaped.png),
              line: shaped,
            );
          } finally {
            inFlight--;
          }
        }
      }

      await Future.wait([
        for (var i = 0; i < maxConcurrent && i < queue.length; i++) worker(),
      ]);
    }
  }
}
