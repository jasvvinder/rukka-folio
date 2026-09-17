// The solo book helper for this feature (07 §2: "solo users never see the
// chip at all — the app *is* their personal book"). Multi-book scope
// selection (S1.2/S1.3) is a later lane's screen.
//
// ⚠️ SPEC: when the scope switcher lands, S5 should be given an explicit
// `bookId` instead — the optional constructor parameter is already shaped for
// it. Deliberately a local six lines rather than an import across a feature
// boundary this lane does not own.
import '../../shared/ledger/local_ledger.dart';

/// The first (and, pre-scope-switcher, only) book id for [ledger].
Future<String> advancesBookId(LocalLedger ledger) async {
  final ids = await ledger.mirror.bookIds();
  if (ids.isEmpty) {
    throw StateError('no book yet — bootstrapSolo() was not given a name');
  }
  return ids.first;
}
