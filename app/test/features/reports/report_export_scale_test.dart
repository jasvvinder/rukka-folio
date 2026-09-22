// F1-07-434 — a report at **200 % text scale on 360×800** (07 §1 rule 11;
// 13 §4.3), taken through the export the M12 content rules changed.
//
// The closing block of 07 §14 🔒 (b/d–c/d, the Total line) and the amount in
// words are new rows and a new line of text, and text is what a 200 % layout
// breaks on. This case is the S8.2 viewer pattern — `pumpRk`'s live
// MediaQuery, both the exception check and [expectTextFits], all three
// languages — run at the harder of the two reference phones and then *through*
// the export, so a report that renders at 200 % but cannot be handed over at
// 200 % still fails.
//
// [expectTextFits] is here for the reason the viewer cases give: given less
// room than one of its words a paragraph draws that word past its edge and
// throws nothing, so the tree is measured as well as asked whether it threw.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/reports/export/report_export.dart';
import 'package:rukka_folio/features/reports/screens/s8_2_report_viewer_screen.dart';

import '../../shared/test_app.dart';

/// A [ReportSink] that keeps what it was handed instead of writing a file.
final class _CapturingSink {
  ReportFile? file;

  Future<ReportDelivery> call(ReportFile f) async {
    file = f;
    return ReportSaved(f.name);
  }
}

void main() {
  group('a report at 200 % on 360×800 (07 §1 rule 11)', () {
    for (final locale in rkLocales) {
      testWidgets('F1-07-434 the report and its export survive 200 % in '
          '${locale.languageCode} on 360×800 — nothing overflows and the file '
          'still reaches the sink (07 §14 🔒 content rules)', (tester) async {
        final seeded = await seedSoloLedger();
        final sink = _CapturingSink();
        await pumpRk(
          tester,
          ReportViewerScreen(sink: sink.call),
          ledger: seeded.ledger,
          locale: locale,
          textScale: 2,
          viewport: rkPhone360,
        );

        expect(tester.takeException(), isNull);
        expectTextFits(
          tester,
          reason: 'S8.2 in ${locale.languageCode} at 200% on 360×800',
        );

        // Past 1.3x the primary action is an icon, which is what lets it
        // share the bar at all; it exports the PDF (ADR 2026-09-12d §2 🔒).
        await tester.tap(find.byIcon(Icons.ios_share));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final file = sink.file;
        expect(file, isNotNull, reason: 'the report never reached the sink');
        expect(file!.format, ReportFormat.pdf);
        expect(file.bytes, isNotEmpty);

        // ⚠️ SPEC: the *confirmation* is deliberately not measured here.
        // The fallback delivery draws `reports.export.saved` — "Saved:
        // day-book-2026-27.pdf" — and at 200 % that file name is one
        // unbreakable word needing 452 px in the snackbar's 312 px, which
        // is an 07 §1 rule 11 defect of its own on a path this lane did not
        // touch (the shipped path is the share sheet, ADR 2026-09-13 §1 🔒).
        // Fixing it means choosing between naming the file in full (rule 6)
        // and fitting it (rule 11), which is the owner's call, not this
        // lane's — recorded as a desk item rather than papered over with an
        // ellipsis here.

        // Tear down inside the test so the snackbar's four-second timer and
        // drift's cleanup timer fire before the binding's pending-timer
        // invariant runs.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
      });
    }
  });
}
