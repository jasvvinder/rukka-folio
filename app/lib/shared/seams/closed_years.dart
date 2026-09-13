// The certified-years seam (ADR 2026-09-09 §4 🔒).
//
// It lives here, beside `auth_client.dart` / `key_store.dart` / `sync_client.dart`,
// because it is a **domain seam consumed by two features** — `features/ledger`
// (S4) and `features/reports` (S8.2) — and S10.4 will be the third at M9. It was
// declared inside `features/ledger/widgets/fy_switcher.dart` until 13 Sep 2026,
// which meant `features/reports` reached into another feature's *widgets* folder
// for a domain type: a cross-feature dependency through the wrong layer, and the
// kind that compounds. Moved with no behaviour change.
//
// There is no year-close source until S10.4 lands (M9), so [noClosedYears] —
// *no year has closed* — is what the app ships, and every switcher is exercised
// from a fake. The shape mirrors `features/home`'s `RebuildProgressSource`.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/foundation.dart';

/// A financial year that has been closed and certified (02 §8.1).
@immutable
final class ClosedYear {
  /// Creates the record.
  const ClosedYear({required this.year, required this.carriedForwardPaise});

  /// The year itself.
  final FinancialYear year;

  /// The **b/f it hands to the next year** for the account being shown,
  /// signed paise (+ = Dr) — the certified closing balance of 02 §8.1.
  final int carriedForwardPaise;

  @override
  bool operator ==(Object other) =>
      other is ClosedYear &&
      other.year == year &&
      other.carriedForwardPaise == carriedForwardPaise;

  @override
  int get hashCode => Object.hash(year, carriedForwardPaise);
}

/// The seam S4 and S8.2 consume: the certified years of [bookId], for
/// [accountId], oldest first. Empty until the first year close — which is every
/// build before M9, so [noClosedYears] is what the app ships.
typedef ClosedYearsSource = Future<List<ClosedYear>> Function(
  String bookId,
  String accountId,
);

/// The shipped source: no year has closed, so there is no switcher.
Future<List<ClosedYear>> noClosedYears(String bookId, String accountId) async =>
    const <ClosedYear>[];
