// The app's shipped [ReportSink]: raises the platform share sheet, and falls
// back to a named file when it cannot (ADR 2026-09-13 §1 🔒, which is the
// ruling — this comment does not restate it).
//
// `Printing.sharePdf` shares all three formats despite its name: the iOS plugin
// writes the bytes to `NSTemporaryDirectory()/<name>` and presents a
// `UIActivityViewController` over that file URL, so our extension is what the
// system reads the type from (`printing-5.14.3/ios/Classes/PrintJob.swift:255`).
//
// Nothing here is logged — not the path, not the exception, not the bytes
// (CLAUDE.md rule 4); files purge under `F2-05a-11` (ADR 2026-09-12 §4).
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import 'report_export.dart';

/// The shipped sink: hands [file] to the platform share sheet, and writes it
/// to a named file if that is not possible.
///
/// The fallback is what keeps 07 §1 rules 2 and 6 true on a platform with no
/// share sheet, or when the plugin throws: the report still becomes a real
/// artefact the reader is told the location of, rather than disappearing.
Future<ReportDelivery> shareReportFile(ReportFile file) async {
  try {
    // `subject` is the file name, which carries no figure and no account name
    // (see [ReportFile.name]); `body` stays null so no report content can ride
    // out in a mail body.
    final raised = await Printing.sharePdf(
      bytes: file.bytes,
      filename: file.name,
      subject: file.name,
    );
    if (raised) return const ReportShared();
  } on Object {
    // Never logged and never surfaced: an exception from a file operation
    // carries a path, and this is plaintext financial data (CLAUDE.md rule 4).
    // The fallback below is the answer, not an error message.
  }
  return ReportSaved(await saveReportToTempFile(file));
}

/// Writes [file] into the app's temporary directory and returns its full
/// path for the confirmation line.
///
/// The fallback half of [shareReportFile], and the whole of what shipped
/// before ADR 2026-09-13 §1.
Future<String> saveReportToTempFile(ReportFile file) async {
  final dir = await getTemporaryDirectory();
  final out = File(p.join(dir.path, file.name));
  await out.writeAsBytes(file.bytes, flush: true);
  return out.path;
}
