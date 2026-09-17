// The books S2.3 *Move money* can send to (07 §5 🔒 → 07 §10 🔒, 02 §6 🔒).
//
// 13 §3.2 row S2.3 is *Transfer (within/between books)*: one position of the
// pill, two destinations. The **To** chooser therefore offers the other books
// this device holds **beside** this book's own money accounts, and choosing
// one switches the flow to 07 §10 — From (book + money A/C) → To (book +
// money A/C) → Save — without losing the amount.
//
// "The books this device holds" is `books_p`, the projection of the books
// whose keys this install has (04 §5.2): a book the reader cannot open is not
// in it, and half a pair may never be authored into a book that is not there
// ([InterBookRefusal.bookNotHeld]). No figure and no posting rule lives here
// — this file is a name list.
import '../../shared/ledger/local_ledger.dart';

/// One book as the *To* chooser needs it: an id and what to call it.
final class EntryBook {
  /// Creates the reference.
  const EntryBook({required this.id, required this.name});

  /// Book id.
  final String id;

  /// Display name, as the user wrote it (03 §4 — ciphertext-side, so it is
  /// user data and never an ARB label).
  final String name;
}

/// Every book this device holds, by name — the chooser's source.
Stream<List<EntryBook>> watchEntryBooks(LocalLedger ledger) =>
    ledger.watchBooks().map(
      (rows) =>
          [for (final b in rows) EntryBook(id: b.id, name: b.name)]
            ..sort((x, y) => x.name.compareTo(y.name)),
    );

/// [all] without [bookId] — the destinations a movement out of [bookId] has.
/// Empty on a solo install, which is exactly when the chooser shows no book
/// row at all and S2.3 stays the within-book transfer it has always been.
List<EntryBook> otherBooks(List<EntryBook> all, String bookId) => [
  for (final b in all)
    if (b.id != bookId) b,
];

/// The book called [id], or null while the projection has not caught up.
EntryBook? bookOf(List<EntryBook> all, String? id) {
  if (id == null) return null;
  for (final b in all) {
    if (b.id == id) return b;
  }
  return null;
}
