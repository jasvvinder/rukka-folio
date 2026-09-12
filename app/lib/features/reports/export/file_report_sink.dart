// The app's shipped [ReportSink]: saves a generated report beside the app's
// own temporary files and tells the reader where it went.
//
// ⚠️ SPEC: ADR 2026-09-12 §1 makes **Download/Share** the primary action, and
// the share half of that is `printing`'s OS sheet. `printing` now resolves
// (ADR 2026-09-12d §1 pinned `archive` into `pdf`'s window), so the blocker
// this file was written around is gone — but swapping the shipped sink for
// `Printing.sharePdf` changes what the primary action *does* on a real phone,
// which is a decision above a report lane. Until it is taken, *Download* is
// what ships and *Share* is not claimed: the file is written and named, never
// silently discarded, so the export is a real artefact rather than a dead end
// (07 §1 rules 2 and 6). Swapping this one function is the whole of the change.
//
// The file is plaintext financial data (CLAUDE.md rule 4), so it goes to the
// temporary directory and purges under the rule `F2-05a-11` already carries
// (ADR 2026-09-12 §4 — no new rule minted). It is never logged: the returned
// description names the file, never its contents.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'report_export.dart';

/// Writes [file] into the app's temporary directory and returns its full
/// path for the confirmation line.
Future<String> saveReportToTempFile(ReportFile file) async {
  final dir = await getTemporaryDirectory();
  final out = File(p.join(dir.path, file.name));
  await out.writeAsBytes(file.bytes, flush: true);
  return out.path;
}
