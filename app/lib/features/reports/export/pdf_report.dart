// PDF export of a report (ADR 2026-09-12 §1 🔒 — PDF is the first of the three
// formats and the one *Download/Share* defaults to; ADR 2026-09-12d §2–§3 🔒 —
// the default came back to PDF and this row generates). Built with
// `package:pdf`, which `printing` prints and shares; **A4 print-clean** is the
// requirement of 07 §14 🔒, so the page format is A4 and nothing is laid out
// against a screen.
//
// Generated **on device**, like every format (07 §14 🔒): no report content
// leaves the phone to be rendered.
//
// This is a PROFESSIONAL surface (02 §10 🔒, CLAUDE.md rule 9): the columns are
// **Dr** and **Cr**, never *Money in / Money out*, and the layout is the
// classical one the CSV writer already uses — one row per posting *line*, the
// date and note on the entry's first line, and a totals line at the foot that
// is the cross-check (13 §5, flow F3).
//
// Money is integer paise throughout (CLAUDE.md rule 1); figures are rendered by
// the app's own [formatPaise], the same function the screen uses, so paper and
// screen can never disagree about a figure.
//
// **Fonts are the defect this file exists to prevent.** `package:pdf` does not
// use system fonts: every glyph is drawn from a font embedded in the document,
// and the default (Helvetica) has neither Gurmukhi nor Devanagari — a Punjabi
// or Hindi day book would export as a page of empty boxes, silently, for
// exactly the readers 01 §1.8 is written for. So the document is built with the
// app's own faces (11 §4.4): **Mukta** (Latin + Devanagari + ₹) as the base and
// **Mukta Mahee** (Gurmukhi) as the fallback, with Noto Sans behind both.
// [ReportFonts.unsupportedRunes] is the proof — `F1-07-79` asserts that no rune
// of a Gurmukhi or Devanagari day book falls through them.
//
// ⚠️ SPEC: 07 §14's report *content* rules — b/d–c/d rows on ledgers and
// amount-in-words — are not built here: ADR 2026-09-12 §3's Open note puts them
// at M12 with the F3 byte goldens (`F3-07-1`, `F3-07-2`), and 10's M5 row is
// *"basic day-book export"*. The Free-tenant watermark is M12 too
// (ADR 2026-09-12 §2, `F3-07-3`). Indian digit grouping is not deferred — it is
// what [formatPaise] already does on every surface of the app.
import 'dart:ui' show Locale;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/format/money_format.dart';
import '../../../shared/tokens.dart';
import '../day_book.dart';
import 'report_export.dart';

/// The app's faces as `package:pdf` needs them — embedded in the document,
/// never assumed to exist on the reader's machine (11 §4.4).
///
/// [regular] and [bold] are Mukta, which carries Latin, Devanagari and ₹;
/// [fallback] leads with Mukta Mahee, which carries Gurmukhi. `package:pdf`
/// consults the fallback list per rune, so a line mixing scripts is drawn
/// correctly without the caller choosing a face.
@immutable
final class ReportFonts {
  const ReportFonts._(this.regular, this.bold, this.fallback, this._coverage);

  /// Loads the faces from the app's asset bundle.
  ///
  /// [bundle] defaults to [rootBundle]; a test may pass its own. Loading is
  /// done per export rather than cached: an export is a rare, deliberate act,
  /// and three fonts held for the life of the process would be megabytes kept
  /// warm for nothing.
  static Future<ReportFonts> load({AssetBundle? bundle}) async {
    final from = bundle ?? rootBundle;
    final regular = await from.load(fontMuktaRegular);
    final bold = await from.load(fontMuktaSemiBold);
    final gurmukhiRegular = await from.load(fontMuktaMaheeRegular);
    final gurmukhiBold = await from.load(fontMuktaMaheeSemiBold);
    final notoSans = await from.load(fontNotoSans);
    return ReportFonts._(
      pw.Font.ttf(regular),
      pw.Font.ttf(bold),
      [
        pw.Font.ttf(gurmukhiRegular),
        pw.Font.ttf(gurmukhiBold),
        pw.Font.ttf(notoSans),
      ],
      [
        for (final data in [
          regular,
          bold,
          gurmukhiRegular,
          gurmukhiBold,
          notoSans,
        ])
          TtfParser(data).charToGlyphIndexMap.keys.toSet(),
      ],
    );
  }

  /// Mukta Regular — Latin, Devanagari, ₹.
  final pw.Font regular;

  /// Mukta SemiBold — headings and the totals line.
  final pw.Font bold;

  /// Mukta Mahee (Gurmukhi) first, then Noto Sans.
  final List<pw.Font> fallback;

  /// One set of supported code points per loaded face, in the order
  /// [regular], [bold], then [fallback].
  final List<Set<int>> _coverage;

  /// The document theme: base, bold, and the per-rune fallback chain.
  pw.ThemeData get theme => pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: regular,
    boldItalic: bold,
    fontFallback: fallback,
  );

  /// Every rune of [text] that **no** loaded face can draw.
  ///
  /// `package:pdf` draws an unsupported rune as an empty placeholder box and
  /// only warns in a debug `assert`, so a missing script is invisible in
  /// release. This is the assertion that makes it visible: `F1-07-79` runs the
  /// Gurmukhi and Devanagari strings of a real day book through it and expects
  /// nothing back. Whitespace is ignored, as `package:pdf` ignores it.
  Set<int> unsupportedRunes(String text) {
    final missing = <int>{};
    for (final rune in text.runes) {
      if (rune <= 0x20 || rune == 0x00A0 || rune == 0x200B) continue;
      if (_coverage.any((set) => set.contains(rune))) continue;
      missing.add(rune);
    }
    return missing;
  }
}

/// Asset key of Mukta Regular (11 §4.4; declared in `app/pubspec.yaml`).
const String fontMuktaRegular = 'assets/fonts/Mukta-Regular.ttf';

/// Asset key of Mukta SemiBold.
const String fontMuktaSemiBold = 'assets/fonts/Mukta-SemiBold.ttf';

/// Asset key of Mukta Mahee Regular — the Gurmukhi face.
const String fontMuktaMaheeRegular = 'assets/fonts/MuktaMahee-Regular.ttf';

/// Asset key of Mukta Mahee SemiBold.
const String fontMuktaMaheeSemiBold = 'assets/fonts/MuktaMahee-SemiBold.ttf';

/// Asset key of Noto Sans — the last-resort fallback of 11 §4.4.
const String fontNotoSans = 'assets/fonts/NotoSans[wdth,wght].ttf';

/// Page geometry. A4 with a 1.5 cm margin all round: print-clean on A4 is
/// 07 §14 🔒, and a margin narrower than this is eaten by a home printer.
const PdfPageFormat _a4 = PdfPageFormat.a4;
const double _margin = 1.5 * PdfPageFormat.cm;

/// Type sizes in points. A report is read on paper, so these are print sizes,
/// not the screen scale of `tokens.dart` — the tokens supply the ink.
const double _titleSize = 15;
const double _metaSize = 9.5;
const double _bodySize = 9;

/// Colours come from the light palette whatever the app's theme is: paper is
/// paper, and a dark-theme document would print as a black page. Tokens only —
/// a hex literal here is review-blocking (`check_purity`).
PdfColor get _ink => PdfColor.fromInt(RkColorsLight.text.toARGB32());
PdfColor get _muted => PdfColor.fromInt(RkColorsLight.textMuted.toARGB32());
PdfColor get _hairline => PdfColor.fromInt(RkColorsLight.hairline.toARGB32());

/// The day book as an A4 PDF document.
///
/// [accountName] resolves an account id to its display name — the caller holds
/// the [Chart], this file does not reach for one. [locale] only reaches
/// [formatPaise]; digits are Latin in every locale by rule (11 §4.4).
/// [pageNumber] renders the page footer, e.g. *Page 1 of 3*.
Future<Uint8List> dayBookPdf(
  DayBook book, {
  required String Function(String accountId) accountName,
  required ReportLabels labels,
  required String bookName,
  required String period,
  required String Function(LocalDate date) formatDate,
  required String Function(int page, int pages) pageNumber,
  required ReportFonts fonts,
  required Locale locale,
}) async {
  final doc = pw.Document(
    // Metadata that travels with the file: the report's own name and nothing
    // else — no account name, no party name, no figure (CLAUDE.md rule 4).
    title: labels.reportName,
  );

  String money(int paise) =>
      formatPaise(paise, locale: locale, showPaise: true);

  final rows = <pw.TableRow>[
    _headerRow(labels),
    for (final row in book.rows)
      ..._entryRows(row, accountName, formatDate, money),
    _totalsRow(labels, book, money),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: _a4,
      margin: const pw.EdgeInsets.all(_margin),
      theme: fonts.theme,
      // The default cap is 20 pages; a year of a busy book is more than that,
      // and a truncated day book would be a wrong report, not a short one.
      maxPages: 1000,
      header: (context) => _head(labels, bookName, period),
      footer: (context) => _foot(pageNumber, context),
      build: (context) => [
        pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(58),
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(74),
            3: pw.FixedColumnWidth(74),
            4: pw.FlexColumnWidth(2),
          },
          children: rows,
        ),
      ],
    ),
  );
  return doc.save();
}

/// The day book as a [ReportFile] ready for a [ReportSink].
Future<ReportFile> dayBookPdfFile(
  DayBook book, {
  required String Function(String accountId) accountName,
  required ReportLabels labels,
  required String bookName,
  required String period,
  required String Function(LocalDate date) formatDate,
  required String Function(int page, int pages) pageNumber,
  required ReportFonts fonts,
  required Locale locale,
  required String fileName,
}) async {
  final bytes = await dayBookPdf(
    book,
    accountName: accountName,
    labels: labels,
    bookName: bookName,
    period: period,
    formatDate: formatDate,
    pageNumber: pageNumber,
    fonts: fonts,
    locale: locale,
  );
  return ReportFile(name: fileName, format: ReportFormat.pdf, bytes: bytes);
}

/// The masthead, repeated on every page so a loose sheet still says what it is
/// and which book and period it covers.
pw.Widget _head(ReportLabels labels, String bookName, String period) =>
    pw.Container(
      margin: const pw.EdgeInsets.only(bottom: RkSpace.s3),
      padding: const pw.EdgeInsets.only(bottom: RkSpace.s2),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.7)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            labels.reportName,
            style: pw.TextStyle(
              fontSize: _titleSize,
              fontWeight: pw.FontWeight.bold,
              color: _ink,
            ),
          ),
          pw.SizedBox(height: RkSpace.s1),
          pw.Text(
            '${labels.bookLabel}: $bookName    '
            '${labels.periodLabel}: $period',
            style: pw.TextStyle(fontSize: _metaSize, color: _muted),
          ),
        ],
      ),
    );

/// *Page 1 of 3*, right-aligned under the body.
pw.Widget _foot(
  String Function(int page, int pages) pageNumber,
  pw.Context context,
) => pw.Container(
  alignment: pw.Alignment.centerRight,
  margin: const pw.EdgeInsets.only(top: RkSpace.s2),
  child: pw.Text(
    pageNumber(context.pageNumber, context.pagesCount),
    style: pw.TextStyle(fontSize: _metaSize, color: _muted),
  ),
);

/// The column headings — repeated at the top of every page, because a table
/// whose Dr and Cr columns are named only on page one is unreadable on page
/// two (07 §1 rule 2: never a dead end, and a nameless column is one).
pw.TableRow _headerRow(ReportLabels labels) => pw.TableRow(
  repeat: true,
  decoration: pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.7)),
  ),
  children: [
    _cell(labels.columnDate, bold: true),
    _cell(labels.columnParticulars, bold: true),
    _cell(labels.columnDebit, bold: true, align: pw.TextAlign.right),
    _cell(labels.columnCredit, bold: true, align: pw.TextAlign.right),
    _cell(labels.columnNote, bold: true),
  ],
);

/// One row per posting **line**, classical layout: the date and the note sit
/// on the entry's first line, every further line continues under it.
List<pw.TableRow> _entryRows(
  DayBookRow row,
  String Function(String accountId) accountName,
  String Function(LocalDate date) formatDate,
  String Function(int paise) money,
) {
  final lines = [...row.debits, ...row.credits];
  return [
    for (var i = 0; i < lines.length; i++)
      pw.TableRow(
        decoration: i == lines.length - 1
            ? pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(color: _hairline)),
              )
            : null,
        children: [
          _cell(i == 0 ? formatDate(row.date) : ''),
          _cell(accountName(lines[i].accountId)),
          _cell(
            lines[i].isDebit ? money(lines[i].figurePaise) : '',
            align: pw.TextAlign.right,
          ),
          _cell(
            lines[i].isCredit ? money(lines[i].figurePaise) : '',
            align: pw.TextAlign.right,
          ),
          _cell(i == 0 ? (row.note ?? '') : '', muted: true),
        ],
      ),
  ];
}

/// The cross-check footer (13 §5, flow F3): the two columns totalled, which
/// agree because every entry balances (02 §1.4).
pw.TableRow _totalsRow(
  ReportLabels labels,
  DayBook book,
  String Function(int paise) money,
) => pw.TableRow(
  decoration: pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: _ink, width: 0.7)),
  ),
  children: [
    _cell(''),
    _cell(labels.totalLabel, bold: true),
    _cell(money(book.debitTotalPaise), bold: true, align: pw.TextAlign.right),
    _cell(money(book.creditTotalPaise), bold: true, align: pw.TextAlign.right),
    _cell(''),
  ],
);

/// One table cell.
pw.Widget _cell(
  String text, {
  bool bold = false,
  bool muted = false,
  pw.TextAlign align = pw.TextAlign.left,
}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(
    horizontal: RkSpace.s1,
    vertical: RkSpace.s1,
  ),
  child: pw.Text(
    text,
    textAlign: align,
    style: pw.TextStyle(
      fontSize: _bodySize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: muted ? _muted : _ink,
    ),
  ),
);
