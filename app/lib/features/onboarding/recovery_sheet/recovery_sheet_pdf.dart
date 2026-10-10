// The paper recovery sheet (04 §7.4 🔒; ADR 2026-10-06d ruling 3 🔒): one A4
// page — the QR `base64url(version ‖ user_id ‖ RK)`, the typed fallback
// (Crockford Base32 in groups of 4, the 2-char checksum as the last group),
// and the instructions in English plus the user's language, framed as a
// document to keep with the Aadhaar and LIC papers.
//
// Built with `package:pdf` and the app's embedded faces exactly as the S8.2
// export builds its pages (`features/reports/export/pdf_report.dart`:
// [ReportFonts], A4, light-palette ink from tokens — paper is paper whatever
// the app theme). The document carries a title and nothing else: no name, no
// user id in the metadata (CLAUDE.md rule 4). The user id is inside the QR
// and the code because 04 §7.4 puts it there.
//
// **The user's language is shaped by Flutter, not by `package:pdf`.** pdf
// 3.13 shapes only Arabic and bidi — no GSUB, no Indic reordering — so a
// Gurmukhi or Devanagari line set as PDF text prints misspelled: a pre-base
// vowel sign (ਿ / ि) lands after its consonant, a conjunct shows its halant,
// a nukta drifts ('ਰਿਕਵਰੀ' → 'ਰਕਿਵਰੀ'). 04 §7.4 🔒 asks for instructions
// in the user's language, which a misspelling is not. So every line of the
// second language is laid out by the engine's own paragraph (HarfBuzz —
// the same shaping every screen of the app gets), in the app's own faces
// (Mukta / Mukta Mahee, 11 §4.4), and placed on the page as an image at
// [ShapedLine.rasterScale] × its point size — print resolution. English, which
// pdf 3.13 sets correctly, stays text. The shaping itself lives in
// `shared/pdf_shaping.dart`, shared with the report PDF (desk 183 c).
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Locale;

import 'package:core_crypto/core_crypto.dart'
    show CryptoSuite, RecoveryKey, recoverySheetQr, recoverySheetTyped;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/pdf_shaping.dart' show ShapedLine, shapePdfLine;
import '../../../shared/tokens.dart';
import '../../reports/export/pdf_report.dart' show ReportFonts;

export '../../../shared/pdf_shaping.dart' show ShapedLine;

/// What the page prints: the QR text and the typed code's groups. Both carry
/// RK (04 §7.4's spec-mandated exception to "no key in a String"); build the
/// page and drop the value.
final class RecoverySheetContent {
  /// Wraps the two encodings.
  const RecoverySheetContent({required this.qr, required this.groups});

  /// `base64url(version ‖ user_id ‖ RK)`.
  final String qr;

  /// The typed fallback in groups of 4; the last group is the 2-char
  /// checksum.
  final List<String> groups;
}

/// The page's content for [userId]'s [rk] — `core_crypto`'s own encoders,
/// nothing re-implemented here. Does not dispose [rk].
RecoverySheetContent recoverySheetContentOf(
  CryptoSuite suite,
  String userId,
  RecoveryKey rk,
) => RecoverySheetContent(
  qr: recoverySheetQr(userId, rk),
  groups: recoverySheetTyped(suite, userId, rk).split('-'),
);

/// The instruction block of the page in one language, in reading order:
/// heading, then the numbered steps, then the warning.
List<String> recoverySheetInstructions(AppLocalizations l) => [
  l.onboardingRecoverySheetPdfHowTitle,
  l.onboardingRecoverySheetPdfHow1,
  l.onboardingRecoverySheetPdfHow2,
  l.onboardingRecoverySheetPdfHow3,
  l.onboardingRecoverySheetPdfWarning,
];

/// Every string the page prints in [l] — what a font-coverage check reads.
List<String> recoverySheetPageStrings(AppLocalizations l) => [
  l.onboardingRecoverySheetPdfTitle,
  l.onboardingRecoverySheetPdfKeep,
  l.onboardingRecoverySheetPdfScan,
  l.onboardingRecoverySheetPdfType,
  ...recoverySheetInstructions(l),
];

/// Lays [text] out with the engine's paragraph — full complex-script shaping
/// — in the app's faces, wrapped at [maxWidth] points, and draws it. The
/// sheet's own name for [shapePdfLine] (`shared/pdf_shaping.dart`), where the
/// helper now lives so the report PDF shares it; the sheet's lines are drawn
/// exactly as before.
///
/// Must run where `dart:ui` can rasterise (the UI isolate; a widget test's
/// `runAsync`).
Future<ShapedLine> shapeRecoverySheetLine(
  String text, {
  required double size,
  required ui.Color color,
  bool bold = false,
  double maxWidth = _contentWidth,
}) => shapePdfLine(
  text,
  size: size,
  color: color,
  bold: bold,
  maxWidth: maxWidth,
);

/// Renders the one-page sheet. [local] is the user's language; null or
/// English prints the instructions once. The second language is shaped by
/// [shapeRecoverySheetLine], so this must run where `dart:ui` can rasterise.
Future<Uint8List> recoverySheetPdf(
  RecoverySheetContent content, {
  required AppLocalizations en,
  AppLocalizations? local,
  required ReportFonts fonts,
}) async {
  final second = local == null || local.localeName == en.localeName
      ? null
      : local;
  final doc = pw.Document(title: en.onboardingRecoverySheetPdfTitle);
  final ink = PdfColor.fromInt(RkColorsLight.text.toARGB32());
  final muted = PdfColor.fromInt(RkColorsLight.textMuted.toARGB32());
  final hairline = PdfColor.fromInt(RkColorsLight.hairline.toARGB32());

  pw.Widget heading(String s) => pw.Text(
    s,
    style: pw.TextStyle(fontSize: _bodySize + 2, color: ink, font: fonts.bold),
  );
  pw.Widget body(String s, {PdfColor? color}) => pw.Text(
    s,
    style: pw.TextStyle(fontSize: _bodySize, color: color ?? ink),
  );

  // The second language, shaped before the page is laid out (the page
  // builder is synchronous). Same sizes and inks as the English lines.
  Future<pw.Widget> shaped(
    String s, {
    double size = _bodySize,
    ui.Color? color,
    bool bold = false,
  }) async {
    final line = await shapeRecoverySheetLine(
      s,
      size: size,
      color: color ?? RkColorsLight.text,
      bold: bold,
    );
    return pw.Image(
      pw.MemoryImage(line.png),
      width: line.width,
      height: line.height,
    );
  }

  final List<String> secondSteps = second == null
      ? const []
      : recoverySheetInstructions(second);
  final secondTitle = second == null
      ? null
      : await shaped(
          second.onboardingRecoverySheetPdfTitle,
          color: RkColorsLight.textMuted,
        );
  final secondKeep = second == null
      ? null
      : await shaped(second.onboardingRecoverySheetPdfKeep);
  final secondScan = second == null
      ? null
      : await shaped(second.onboardingRecoverySheetPdfScan);
  final secondType = second == null
      ? null
      : await shaped(
          second.onboardingRecoverySheetPdfType,
          color: RkColorsLight.textMuted,
        );
  final secondInstructions = <pw.Widget>[
    for (var i = 0; i < secondSteps.length; i++)
      await shaped(
        i == 0
            ? secondSteps[i]
            : i == secondSteps.length - 1
            ? secondSteps[i]
            : '$i.  ${secondSteps[i]}',
        size: i == 0 ? _bodySize + 2 : _bodySize,
        bold: i == 0,
        color: i == secondSteps.length - 1 ? RkColorsLight.textMuted : null,
      ),
  ];

  pw.Widget instructions(List<String> lines) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      heading(lines.first),
      pw.SizedBox(height: 4),
      for (var i = 1; i < lines.length - 1; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: body('$i.  ${lines[i]}'),
        ),
      pw.SizedBox(height: 4),
      body(lines.last, color: muted),
    ],
  );

  pw.Widget shapedInstructions(List<pw.Widget> lines) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      lines.first,
      pw.SizedBox(height: 4),
      for (var i = 1; i < lines.length - 1; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: lines[i],
        ),
      pw.SizedBox(height: 4),
      lines.last,
    ],
  );

  // Six groups to a row: the typed code reads like the frame's grouped
  // lines, scaled to 04 §7.4's real length (79 symbols + checksum = 21
  // groups → four rows), short enough that both languages fit one page.
  final rows = <String>[
    for (var i = 0; i < content.groups.length; i += _groupsPerRow)
      content.groups
          .sublist(
            i,
            i + _groupsPerRow > content.groups.length
                ? content.groups.length
                : i + _groupsPerRow,
          )
          .join('  '),
  ];

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_margin),
      theme: fonts.theme,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            en.onboardingRecoverySheetPdfTitle.toUpperCase(),
            style: pw.TextStyle(
              fontSize: _bodySize,
              color: muted,
              letterSpacing: 1.2,
              font: fonts.bold,
            ),
          ),
          ?secondTitle,
          pw.SizedBox(height: 6),
          body(en.onboardingRecoverySheetPdfKeep),
          ?secondKeep,
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(
                errorCorrectLevel: recoverySheetQrCorrection,
              ),
              data: content.qr,
              drawText: false,
              width: recoverySheetQrSide,
              height: recoverySheetQrSide,
              color: ink,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(child: body(en.onboardingRecoverySheetPdfScan)),
          if (secondScan != null) pw.Center(child: secondScan),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Column(
              children: [
                for (final r in rows)
                  pw.Text(
                    r,
                    style: pw.TextStyle(
                      fontSize: _codeSize,
                      color: ink,
                      font: fonts.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: body(en.onboardingRecoverySheetPdfType, color: muted),
          ),
          if (secondType != null) pw.Center(child: secondType),
          pw.SizedBox(height: 14),
          pw.Divider(color: hairline, thickness: 0.6),
          pw.SizedBox(height: 10),
          instructions(recoverySheetInstructions(en)),
          if (secondInstructions.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            shapedInstructions(secondInstructions),
          ],
        ],
      ),
    ),
  );
  return doc.save();
}

/// Renders for [locale]: English plus that language (04 §7.4).
Future<Uint8List> renderRecoverySheet(
  RecoverySheetContent content,
  Locale locale, {
  ReportFonts? fonts,
}) async => recoverySheetPdf(
  content,
  en: lookupAppLocalizations(const Locale('en')),
  local: lookupAppLocalizations(Locale(locale.languageCode)),
  fonts: fonts ?? await ReportFonts.load(),
);

const double _margin = 1.8 * PdfPageFormat.cm;

/// The QR's side on the page, in points.
const double recoverySheetQrSide = 6.5 * PdfPageFormat.cm;

/// The QR's error-correction level.
const pw.BarcodeQRCorrectionLevel recoverySheetQrCorrection =
    pw.BarcodeQRCorrectionLevel.medium;

/// The width the instructions wrap at: A4 less both margins.
const double _contentWidth = 21.0 * PdfPageFormat.cm - 2 * _margin;

const double _bodySize = 10;
const double _codeSize = 15;
const int _groupsPerRow = 6;
