// The Inbox's three live seams, built once over the ledger and installed as
// scopes — the one place the composition root (`bootstrap.dart`) gets them
// from, so a test that pumps S6 under [LedgerInboxSeams.scopes] runs on
// exactly what production runs (desk 200 (c)).
//
// Every one of them is device-wide: the Inbox is one surface (07 §9 🔒), so
// the late-arrivals tray, the review queue and the structural requests merge
// every book this device holds rather than following Home's selected book.
// Each screen still falls back to its seam's own fake when a scope is absent
// (07 §1 rule 6 — a missing scope is never a red screen), which is exactly why
// the scopes must be installed: S6.3 ran on an empty fake in production until
// this file existed.
import 'package:flutter/widgets.dart';

import '../../shared/ledger/local_ledger.dart';
import 'late_arrivals.dart';
import 'ledger_late_arrivals.dart';
import 'ledger_review_queue.dart';
import 'ledger_structural_requests.dart';
import 'review_queue.dart';
import 'structural_requests.dart';

/// S6's live seams over one [LocalLedger].
final class LedgerInboxSeams {
  /// Builds the seams and starts them watching.
  ///
  /// [memberName] is the members repository's name for a user, or the
  /// *someone in this book* string — never a raw id (ADR 2026-09-05c §4).
  /// [signerOf] is whose **certified** device signed a structural envelope at
  /// this read, or null — in the app `certifiedSignerOf(trust, suite)`, which
  /// re-runs the 04 §3.4 chain over the stored envelope; it decides whose a
  /// structural signature is (02 §7.2.1 🔒). [refreshOn] re-reads the structural
  /// requests on each event — the sync status, whose meta read is where
  /// certificates arrive.
  LedgerInboxSeams(
    LocalLedger ledger, {
    required String Function(String userId) memberName,
    required StructuralSigner signerOf,
    Stream<Object?>? refreshOn,
  }) : lateArrivals = LedgerLateArrivals(ledger),
       reviews = LedgerReviewQueue(ledger, authorNameOf: memberName),
       structural = LedgerStructuralRequests(
         ledger,
         nameOf: memberName,
         signerOf: signerOf,
         refreshOn: refreshOn,
       );

  /// S10.3's tray (07 §13 🔒).
  final LedgerLateArrivals lateArrivals;

  /// S6 / S6.1 / S6.2's review queue (07 §9 🔒).
  final LedgerReviewQueue reviews;

  /// S6.3's structural requests (07 §26 🔒).
  final LedgerStructuralRequests structural;

  /// [child] under all three scopes.
  Widget scopes({required Widget child}) => LateArrivalsScope(
    tray: lateArrivals,
    child: ReviewQueueScope(
      queue: reviews,
      child: StructuralRequestsScope(requests: structural, child: child),
    ),
  );

  /// Stops all three. The app never calls it (they live as long as the
  /// process); tests do.
  Future<void> dispose() async {
    await structural.dispose();
    await reviews.dispose();
    await lateArrivals.dispose();
  }
}
