// An in-memory [YearCloseSource] for tests and for driving S10.4 before the
// ledger lane lands — the twin of `close_fake.dart` (the `shared/seams/` fakes
// live in lib/ for the same reason).
//
// It decides one thing, and it decides it the engine's way: a close is refused
// **exactly when the checklist holds a blocker**, which is
// `yearClosePreconditions`' contract stated once (02 §8.1 🔒, ADR 2026-09-05e
// §4). Because a [YearCloseBlocker] carries the engine's own
// [CloseBlockerItem], a refusal here lists the same items the real
// implementation's refusal will.
//
// It cannot call `yearClosePreconditions` itself: that takes a `LedgerState`,
// and this fake holds a drawn [YearCloseView] rather than an envelope stream.
// The implementation over `LocalLedger` calls it directly, and that is where
// the rule is proved against a real projection.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';

import 'year_close_source.dart';

/// A [YearCloseSource] over a fixed view, recording what it was asked to do.
final class FakeYearCloseSource implements YearCloseSource {
  /// Creates the fake.
  FakeYearCloseSource({required this.view, this.failLoad = false});

  /// What [loadYearClose] answers. Reassign it to change the state under test.
  YearCloseView view;

  /// Makes [loadYearClose] throw, for the error state.
  bool failLoad;

  /// Holds [loadYearClose] open for ever — the loading state without a pending
  /// timer, which a widget test would otherwise flag at tear-down.
  bool holdLoad = false;

  /// Makes [closeYear] throw something that is *not* a [YearCloseRefused] — a
  /// ceremony that failed to publish rather than a year that may not close.
  bool failClose = false;

  /// Holds [closeYear] pending for ever — the *certifying…* state.
  bool holdClose = false;

  /// What this device's verification of the new close comes back as. The three
  /// outcomes of ADR 2026-09-05c §3 🔒 are all reachable from here, including
  /// [CloseVerification.readerOutdated] — *unverified-by-you*, never a
  /// mismatch.
  CloseVerification? verification = CloseVerification.verified;

  /// The `projectorVersion` the minted close records (02 §8.1 🔒).
  int projectorVersion = 1;

  /// What [certifiedYears] answers. Empty is the shipped state and the one
  /// ADR 2026-09-09 §4 🔒 turns into *no switcher at all*.
  List<CertifiedYear> years = const [];

  /// Makes [certifiedYears] throw — the switcher is then simply absent, and
  /// the year close itself is unaffected.
  bool failYears = false;

  /// Every `(bookId, fy)` [closeYear] was called with, in order.
  final List<String> closed = [];

  /// Every `(bookId, fy)` [loadYearClose] was asked for, in order — what the
  /// *Resumable* rule is asserted against (07 §13 🔒). S10.4 holds nothing, so
  /// coming back **must** be a fresh read of the ledger rather than a redraw
  /// of what the screen remembered.
  final List<String> loaded = [];

  @override
  Future<YearCloseView> loadYearClose(String bookId, FinancialYear fy) async {
    loaded.add('$bookId/${fy.label}');
    if (holdLoad) return Completer<YearCloseView>().future;
    if (failLoad) throw StateError('no year close for $bookId ${fy.label}');
    return view;
  }

  @override
  Future<YearCloseResult> closeYear(String bookId, FinancialYear fy) async {
    if (holdClose) return Completer<YearCloseResult>().future;
    if (failClose) throw StateError('could not publish the year close');
    final blockers = [for (final b in view.blockers) b.item];
    if (blockers.isNotEmpty) throw YearCloseRefused(blockers);
    closed.add('$bookId/${fy.label}');
    final vector = view.vector?.vector ?? BalanceVector(const {});
    return YearCloseResult(
      close: YearClose(
        id: 'yc-${fy.label}',
        bookId: bookId,
        financialYear: fy,
        vector: vector,
        byUser: 'user-1',
        hlc: const Hlc(1),
        projectorVersion: projectorVersion,
      ),
      verification: verification,
    );
  }

  @override
  Future<List<CertifiedYear>> certifiedYears(String bookId) async {
    if (failYears) throw StateError('no certified years for $bookId');
    return years;
  }
}
