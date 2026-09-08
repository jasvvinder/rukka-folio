// The solo book helper (07 §2 scope switcher: "solo users never see the chip
// at all — the app *is* their personal book"). Multi-book scope selection
// (S1.2/S1.3) is a later lane's screen; until it lands, every root screen in
// this feature resolves the one book a freshly bootstrapped solo ledger has.
// ⚠️ SPEC: when the scope switcher lands, callers should pass an explicit
// `bookId` instead of calling this — the optional parameter on each screen
// here is already shaped for that (see S3/S8.1 constructors).
import '../../shared/ledger/local_ledger.dart';

/// The first (and, pre-scope-switcher, only) book id for [ledger].
Future<String> soloBookId(LocalLedger ledger) async {
  final ids = await ledger.mirror.bookIds();
  if (ids.isEmpty) {
    throw StateError('no book yet — bootstrapSolo() was not given a name');
  }
  return ids.first;
}
