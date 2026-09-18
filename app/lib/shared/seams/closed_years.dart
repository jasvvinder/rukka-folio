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
import 'package:flutter/widgets.dart';

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

/// The [ClosedYearsSource] in force for the tree below.
///
/// S4 and S8.2 take their source through a constructor today, which is how a
/// test hands them a fake. This scope is the **other** way in, and it exists
/// so that the day a real source appears — S10.4's year close, M9 — the shell
/// can install it once above the router and neither screen changes its
/// constructor. `CloseScope` (`features/close/close_source.dart`) and
/// `LedgerScope` are the same arrangement; this is the seam-layer twin.
///
/// Reading it is deliberately *optional*: [maybeOf] returns null when no scope
/// is installed, and a screen then falls back to what it was constructed with
/// — [noClosedYears] in the shipped app. A missing scope is never an error and
/// never a red screen (07 §1 rule 6).
class ClosedYearsScope extends InheritedWidget {
  /// Creates the scope.
  const ClosedYearsScope({
    super.key,
    required this.source,
    required super.child,
  });

  /// The source in force.
  final ClosedYearsSource source;

  /// The nearest source, or null when the shell has installed none — the
  /// caller then keeps its own default rather than failing.
  static ClosedYearsSource? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ClosedYearsScope>()?.source;

  @override
  bool updateShouldNotify(ClosedYearsScope old) => source != old.source;
}
