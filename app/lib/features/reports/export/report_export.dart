// The export surface of S8.2 (ADR 2026-09-12 §1 🔒): the sheet offers exactly
// three formats — **PDF, CSV and XLSX**, no more, no fewer — every one of them
// generated **on device**, no report content leaving it to be rendered
// (07 §14 🔒, unchanged by every ADR since).
//
// What ships at M5, and why:
//
//   • **PDF** — `package:pdf` + `printing` (`pdf_report.dart`). Shipped, and
//     the default of *Download/Share*: it is the format a person hands to
//     someone else (ADR 2026-09-12d §2–§3 🔒, which restored the default 12c
//     had moved to CSV and turned this row from disabled-with-reason into a
//     working one). It resolves because the workspace root pins `archive` into
//     `pdf`'s window rather than downgrading sodium — see the
//     `dependency_overrides` note there and ADR 2026-09-12d §1.
//   • **CSV** — pure Dart, no package (`csv_report.dart`). Shipped.
//   • **XLSX** — written in-house over `archive` + `xml`, no package
//     (`xlsx_report.dart`). Shipped: ADR 2026-09-12e §1 🔒 closed the package
//     question by ruling that an `.xlsx` is a zip of XML parts and we write
//     the manifest ourselves — the two free writers need `archive` 3.x and
//     sodium needs 4.x, and the one compatible package is proprietary.
//
// **No row of the export sheet is disabled now.** The trio is the same on
// every report surface (ADR 2026-09-12e §2 🔒), and the day book is the one
// report that exists at M5 — the other ten of 07 §14 are M12.
import 'package:flutter/foundation.dart';

import '../../../l10n/gen/app_localizations.dart';

/// The three formats of ADR 2026-09-12 §1 🔒, in the ADR's own order — PDF
/// first because *Download/Share* defaults to it (ADR 2026-09-12d §2 🔒). This
/// enum is the enumeration: adding a fourth, or dropping one, is a 🔒 change.
enum ReportFormat {
  /// Portable document — the format a person hands to someone else. Carries
  /// the Free-tenant watermark (ADR 2026-09-12 §2, M12); A4 print-clean (§3).
  pdf('pdf', 'application/pdf'),

  /// Comma-separated values — the machine-readable copy. Never watermarked
  /// (ADR 2026-09-12 §2).
  csv('csv', 'text/csv'),

  /// Spreadsheet. Never watermarked (ADR 2026-09-12 §2).
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );

  const ReportFormat(this.extension, this.mediaType);

  /// File extension, no dot.
  final String extension;

  /// IANA media type for the share sheet.
  final String mediaType;
}

/// The localised words an exported report carries — shared by every writer, so
/// the PDF and the CSV of one report can never disagree about a column name.
///
/// Pulled off [AppLocalizations] by [ReportLabels.dayBook] so the writers stay
/// pure functions of data and strings — testable without a widget tree.
@immutable
final class ReportLabels {
  /// Creates the label set.
  const ReportLabels({
    required this.reportName,
    required this.bookLabel,
    required this.periodLabel,
    required this.columnDate,
    required this.columnParticulars,
    required this.columnDebit,
    required this.columnCredit,
    required this.columnNote,
    required this.totalLabel,
  });

  /// Reads the day-book labels from the locale's strings.
  factory ReportLabels.dayBook(AppLocalizations strings) => ReportLabels(
    reportName: strings.reportsDayBookRowTitle,
    bookLabel: strings.reportsViewerBookLabel,
    periodLabel: strings.reportsViewerPeriodLabel,
    columnDate: strings.reportsViewerColumnDate,
    columnParticulars: strings.reportsViewerColumnParticulars,
    columnDebit: strings.moneySideDr,
    columnCredit: strings.moneySideCr,
    columnNote: strings.reportsViewerColumnNote,
    totalLabel: strings.reportsViewerTotal,
  );

  /// *Day Book* — the report's own name (07 §14 🔒 row 1).
  final String reportName;

  /// *Book* — heading for the book-name line.
  final String bookLabel;

  /// *Period* — heading for the financial-year line.
  final String periodLabel;

  /// *Date* column.
  final String columnDate;

  /// *Particulars* column — the account each line posts to.
  final String columnParticulars;

  /// *Dr* column (professional vocabulary, 02 §10 🔒).
  final String columnDebit;

  /// *Cr* column.
  final String columnCredit;

  /// *Note* column.
  final String columnNote;

  /// *Total* — the cross-check line at the foot.
  final String totalLabel;
}

/// A generated report, in memory, on its way to the reader.
///
/// The bytes are **plaintext financial data** (CLAUDE.md rule 4): they never
/// reach a log, a crash report or a notification, and any file a [ReportSink]
/// writes purges under the temp-file rule already carried by `F2-05a-11`
/// (ADR 2026-09-12 §4 — no new rule is minted for reports).
@immutable
final class ReportFile {
  /// Creates the file.
  const ReportFile({
    required this.name,
    required this.format,
    required this.bytes,
  });

  /// File name including the extension, e.g. `day-book-2026-27.pdf`. Carries
  /// no account name, party name or figure — a file name is metadata that
  /// leaves the app with the share sheet.
  final String name;

  /// Which of the three formats this is.
  final ReportFormat format;

  /// The document.
  final Uint8List bytes;
}

/// What became of a generated report — the two ends of *Download/Share*
/// (ADR 2026-09-13 §1 🔒).
///
/// A sealed pair rather than a string, because the two outcomes need different
/// words on the screen and only the sink knows which happened: the share sheet
/// is its own confirmation, a file on disk is not.
sealed class ReportDelivery {
  /// Creates a delivery.
  const ReportDelivery();
}

/// Handed to the platform share sheet — the reader chose where it goes from
/// there (WhatsApp, Files, Mail).
///
/// **No snackbar follows this.** The sheet is the confirmation, it covers the
/// screen the snackbar would appear on, and the platform reports neither
/// completion nor cancellation — so any sentence we wrote would be a guess
/// about what the reader did next (07 §1 rule 12).
final class ReportShared extends ReportDelivery {
  /// Creates the shared outcome.
  const ReportShared();
}

/// Written to a file at [where] — the fallback when no share sheet can be
/// raised, so an export is never a dead end (07 §1 rules 2 and 6).
final class ReportSaved extends ReportDelivery {
  /// Creates the saved outcome.
  const ReportSaved(this.where);

  /// The file's full path, shown to the reader. A path, never a figure and
  /// never an account name (CLAUDE.md rule 4).
  final String where;
}

/// Where a generated report goes — the seam S8.2 hands its bytes to.
///
/// Shaped as a seam for the same reason `ClosedYearsSource` is: the app's sink
/// raises the share sheet, while a test injects a fake and reads the bytes.
/// `printing` resolves since ADR 2026-09-12d §1, and ADR 2026-09-13 §1 🔒 took
/// the decision the swap was waiting on — see `file_report_sink.dart`.
///
/// Returns which of the two deliveries happened, so an export is never a
/// silent no-op (07 §1 rule 6).
typedef ReportSink = Future<ReportDelivery> Function(ReportFile file);
