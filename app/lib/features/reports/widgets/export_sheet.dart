// S8.2's export sheet (ADR 2026-09-12 §1 🔒; default and row states per
// ADR 2026-09-12d §2–§3 🔒).
//
// The enumeration is the ruling: **PDF, CSV and XLSX — no more, no fewer**, in
// that order, PDF first. Every format is generated **on device** (07 §14 🔒).
// Adding a fourth row, or dropping one, is a 🔒 change. Neither 12c nor 12d
// moved the enumeration or the order.
//
//   • **PDF** — generates (`export/pdf_report.dart`), and is what the viewer's
//     primary action writes without asking. 12c had this row
//     disabled-with-reason on a dependency reading that 12d overturned: the
//     workspace pins `archive` into `pdf`'s window instead of downgrading
//     sodium, so `pdf` and `printing` resolve and `constantTimeEquals` stays
//     libsodium-backed (ADR 2026-09-12d §1, root `pubspec.yaml`).
//   • **CSV** — generates (`export/csv_report.dart`), the machine-readable
//     copy.
//   • **XLSX** — generates (`export/xlsx_report.dart`), the copy an accountant
//     can sum. It shipped disabled-with-reason while the package choice was an
//     open owner call; ADR 2026-09-12e §1 🔒 closed that by writing the format
//     in-house over `archive` + `xml`, so the row runs and its reason line is
//     gone with the blocker — a reason naming a limitation the build no longer
//     has is a lie on the screen. **No row of this sheet is disabled now.**
//
// This sheet stays reachable from the viewer beside the default that writes —
// the half of ADR 2026-09-12c §1 that survives 12d. Both paths exist; neither
// may become the only one.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/tokens.dart';
import '../export/report_export.dart';
import 'reports_row.dart';

/// Builds the report in [format], hands it to [sink] and tells the reader what
/// became of it — the single path **both** of S8.2's export affordances take
/// (ADR 2026-09-12c §1 🔒, ADR 2026-09-12d §2 🔒): the app bar's primary action
/// calls it straight with [ReportFormat.pdf], and this sheet calls it for the
/// row that was tapped.
///
/// The two deliveries get different treatment, which is the whole reason
/// [ReportDelivery] is a pair rather than a string (ADR 2026-09-13 §1 🔒):
/// a [ReportShared] needs no snackbar — the share sheet is the confirmation,
/// it covers the screen a snackbar would appear on, and the platform tells us
/// neither that the reader finished nor that they cancelled — while a
/// [ReportSaved] must name the file, or the export is a silent no-op.
///
/// [l10n] and [messenger] are passed in rather than read from a context,
/// because the sheet closes itself before the file is written and its own
/// context is gone by then.
Future<void> runReportExport({
  required AppLocalizations l10n,
  required ScaffoldMessengerState messenger,
  required ReportFormat format,
  required Future<ReportFile> Function(ReportFormat format) buildFile,
  required ReportSink sink,
}) async {
  try {
    final file = await buildFile(format);
    switch (await sink(file)) {
      case ReportShared():
        break;
      case ReportSaved(:final where):
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.reportsExportSaved(where))),
        );
    }
  } catch (_) {
    // The exception itself is never surfaced or logged: it can carry a path
    // and this is plaintext financial data (CLAUDE.md rule 4). One plain
    // sentence, no error code (07 §1 rule 12).
    messenger.showSnackBar(SnackBar(content: Text(l10n.reportsExportFailed)));
  }
}

/// Opens the export sheet over [context].
///
/// [buildFile] generates the report in the chosen format — every one of the
/// three at M5 (ADR 2026-09-12e §1 🔒).
/// [sink] takes the finished bytes and reports which [ReportDelivery]
/// happened — shared, or saved and named (an export is never silent).
Future<void> showReportExportSheet(
  BuildContext context, {
  required Future<ReportFile> Function(ReportFormat format) buildFile,
  required ReportSink sink,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _ExportSheet(buildFile: buildFile, sink: sink),
  );
}

class _ExportSheet extends StatelessWidget {
  const _ExportSheet({required this.buildFile, required this.sink});

  final Future<ReportFile> Function(ReportFormat format) buildFile;
  final ReportSink sink;

  void _export(BuildContext context, ReportFormat format) {
    // Everything that needs the tree is read before the sheet closes: its own
    // context is gone by the time the file is written.
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    unawaited(
      runReportExport(
        l10n: l10n,
        messenger: messenger,
        format: format,
        buildFile: buildFile,
        sink: sink,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s1,
                RkSpace.gutter,
                RkSpace.s2,
              ),
              child: Text(
                l10n.reportsExportTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            // 1 of 3 — PDF: first by the 🔒 order, and the format the primary
            // action writes without asking (ADR 2026-09-12d §2–§3 🔒).
            ReportsActionRow(
              title: l10n.reportsExportPdf,
              description: l10n.reportsExportPdfDescription,
              icon: Icons.picture_as_pdf_outlined,
              onTap: () => _export(context, ReportFormat.pdf),
            ),
            // 2 of 3 — CSV, the machine-readable copy.
            ReportsActionRow(
              title: l10n.reportsExportCsv,
              description: l10n.reportsExportCsvDescription,
              icon: Icons.table_rows_outlined,
              onTap: () => _export(context, ReportFormat.csv),
            ),
            // 3 of 3 — XLSX, the copy that sums: money lands in the cells as
            // numbers, not text (ADR 2026-09-12e §1 🔒).
            ReportsActionRow(
              title: l10n.reportsExportXlsx,
              description: l10n.reportsExportXlsxDescription,
              icon: Icons.grid_on_outlined,
              onTap: () => _export(context, ReportFormat.xlsx),
            ),
            const SizedBox(height: RkSpace.s4),
          ],
        ),
      ),
    );
  }
}
