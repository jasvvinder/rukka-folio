// The person's own personal book (13 §2.1: every entity type starts with
// "1 personal"; canvas 1, *Myself* path: "One private book is already made").
//
// Desk 164 (JOURNEY0): sign-up never made one. `bootstrap.dart` opens the
// identity with `bootstrapSolo()` and no name — at the first launch there is
// no name to give it — and `bootstrapSolo` creates a book only when named, so
// *Myself* and F1b → *Set up new books* reached Home with no book at all and
// the business, family and trust paths had no personal book beside their own.
//
// **When.** At S0.4, the moment the name is known (07 §3.1 step 4): the book
// carries the person's name (canvas 1 O8 draws the scope holder as the
// person's name), S0.2 has already confirmed the identity the book is authored
// under (ADR 2026-10-04b §2 🔒 — nothing is authored while it is provisional),
// and every purpose path, F1b's *Set up new books* and the debug demo card
// all pass through S0.4 — so by the branch steps "one private book is already
// made", as canvas 1 says. The hand-over would be too late: S0.6 (desk 172),
// the step before it on every path, fills this book's Cash A/c. The S0.6 host
// calls this again as a safety net (a creation that failed at S0.4, or a cold
// start that resumed past S0.4), so whichever runs first makes the book and
// the other finds it.
//
// **Never two.** The projection is asked for any book of type `personal`
// first; one that exists — made here earlier, by the demo builder, or brought
// by sync — is the book, and nothing is created. Concurrent calls in one
// process share one in-flight creation.
import 'package:core_ledger/core_ledger.dart' show BookType, LocalDate;

import '../../shared/ledger/local_ledger.dart';

/// The in-flight creation per ledger, so two callers in one process (S0.4's
/// Continue and a quickly following S0.6 host) never race to two books.
final Expando<Future<String>> _inFlight = Expando('personal book creation');

/// The id of this install's personal book, or null when none exists yet.
Future<String?> personalBookIdOf(LocalLedger ledger) async {
  final books = await ledger.db.select(ledger.db.booksP).get();
  for (final b in books) {
    if (b.type == BookType.personal.name) return b.id;
  }
  return null;
}

/// Returns the personal book's id, creating it — named [name], beginning on
/// [startDate] (ADR 2026-09-09d §4) — only when the install has none.
///
/// Throws what `createBook` throws (an unconfirmed identity, a closed
/// ledger); nothing is created then, and a later call tries again.
Future<String> ensurePersonalBook(
  LocalLedger ledger, {
  required String name,
  required LocalDate startDate,
}) {
  final running = _inFlight[ledger];
  if (running != null) return running;
  final created = () async {
    final existing = await personalBookIdOf(ledger);
    if (existing != null) return existing;
    return ledger.createBook(
      name: name,
      type: BookType.personal,
      startDate: startDate,
    );
  }();
  _inFlight[ledger] = created;
  return created.whenComplete(() => _inFlight[ledger] = null);
}
