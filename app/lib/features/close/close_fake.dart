// An in-memory [CloseSource] for tests and for driving S10 before the ledger
// lane lands (the `shared/seams/` fakes live in lib/ for the same reason).
//
// It decides one thing, and it decides it the engine's way: a lock is refused
// **exactly when the tray holds a blocker**, which is
// `monthLockPreconditions`' contract stated once (02 §8 step 3 🔒, ADR
// 2026-09-05b §3–4, ADR 2026-09-05e §4). Because a [CloseBlockingItem] carries
// the engine's own [CloseBlocker], a refusal here lists the same items the
// real implementation's refusal will.
//
// It cannot call `monthLockPreconditions` itself: that takes a `LedgerState`,
// and this fake holds a drawn [CloseView] rather than an envelope stream. The
// implementation over `LocalLedger` calls it directly, and that is where the
// rule is proved against a real projection.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';

import 'close_source.dart';

/// A [CloseSource] over a fixed view, recording what it was asked to save.
final class FakeCloseSource implements CloseSource {
  /// Creates the fake.
  FakeCloseSource({
    required this.view,
    this.failLoad = false,
    this.failLock = false,
    this.loadDelay,
  });

  /// What [loadClose] answers. Reassign it to change the state under test.
  CloseView view;

  /// Makes [loadClose] throw, for the error state.
  bool failLoad;

  /// Makes [lock] throw something that is *not* a [CloseRefused] — a write
  /// that failed rather than a month that may not close.
  bool failLock;

  /// Holds [loadClose] pending, for the loading state.
  Duration? loadDelay;

  /// Holds [loadClose] open for ever — the loading state without a pending
  /// timer, which a widget test would otherwise flag at tear-down.
  bool holdLoad = false;

  /// Every progress this fake was asked to save, in order — the *Resumable*
  /// rule is asserted against this list (07 §13 🔒).
  final List<CloseProgress> savedProgress = [];

  /// Every set of declared balances [lock] was called with, in order.
  final List<Map<String, Paise>> lockedWith = [];

  /// The `projectorVersion` the minted lock records (02 §8 step 4 🔒).
  int projectorVersion = 1;

  @override
  Future<CloseView> loadClose(String bookId, YearMonth period) async {
    if (holdLoad) return Completer<CloseView>().future;
    if (loadDelay != null) await Future<void>.delayed(loadDelay!);
    if (failLoad) throw StateError('no close for $bookId $period');
    return view;
  }

  @override
  Future<void> saveProgress(
    String bookId,
    YearMonth period,
    CloseProgress progress,
  ) async {
    savedProgress.add(progress);
    // Resuming is the point: a saved step is what the next load hands back.
    view = CloseView(
      bookId: view.bookId,
      bookName: view.bookName,
      period: view.period,
      cashAccounts: view.cashAccounts,
      bankAccounts: view.bankAccounts,
      tray: view.tray,
      progress: progress,
      readOnly: view.readOnly,
    );
  }

  @override
  Future<CloseLockResult> lock({
    required String bookId,
    required YearMonth period,
    required Map<String, Paise> declaredBalances,
  }) async {
    if (failLock) throw StateError('could not write the close envelope');
    final blockers = [
      for (final b in view.tray.blocks) CloseBlockerItem(b.kind, b.ref),
    ];
    if (blockers.isNotEmpty) throw CloseRefused(blockers);
    lockedWith.add(Map.of(declaredBalances));
    return CloseLockResult(
      lock: PeriodLock(
        id: 'lock-${period.toString()}',
        bookId: bookId,
        period: period,
        byUser: 'user-1',
        hlc: const Hlc(1),
        declaredBalances: Map.of(declaredBalances),
        vectorCanonical: 'fake-vector',
        projectorVersion: projectorVersion,
      ),
      verification: CloseVerification.verified,
    );
  }
}
