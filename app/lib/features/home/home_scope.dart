// The Home scope model (13 §2.2 🔒): `Me | one Book | Everything`.
//
// The scope chip is visible **only when the user has more than one book** —
// a solo user never sees a control at all (13 §2.2, 07 §2). Which control it
// is, is ruled by 07 §5.7 🔒 and is a count, not a preference: exactly two
// books (Me + one business) get the inline two-chip toggle (S1.2); three or
// more get the grouped bottom sheet (S1.3). The grouped sheet is never shown
// to someone who owns two books.
//
// Switching scope never leaves the screen (13 §2.2): the selection lives in
// this controller, S1 rebuilds its body around it, and nothing is pushed.
//
// ⚠️ SPEC: 13 §2.2 also says scope "persists per tab, defaults to last used".
// That is shell state — it outlives this screen and is shared with the other
// tabs — so it is deliberately NOT stored here. The seam the shell would need
// is a `Scope` read/write on the shell's own state holder
// (`app/lib/shared/`), which this lane does not own; recorded as an open item.
import 'package:flutter/foundation.dart';

import '../../shared/ledger/local_ledger.dart';

/// The four groups the S1.3 sheet is organised by (13 §3.2 row S1.3:
/// *Me / Family / Businesses / Organizations / Everything*). `Everything` is
/// not a group — it is the aggregate row under them.
enum HomeScopeGroup {
  /// The user's own personal book.
  me,

  /// Family, sub-family and joint/common-pool books.
  family,

  /// Business books (02 §7.1).
  businesses,

  /// Trusts, societies, organizations (02 §8.2).
  organizations,
}

/// One book as the scope control needs it: what to call it and where it sits.
final class BookRef {
  /// Creates the reference.
  const BookRef({required this.id, required this.name, required this.group});

  /// Book id.
  final String id;

  /// Display name, as the user wrote it.
  final String name;

  /// Which S1.3 group it belongs under.
  final HomeScopeGroup group;

  /// The group a `books_p.type` wire name belongs to (02 §1.1 wire names).
  ///
  /// ⚠️ SPEC: no group is defined for a type this build does not know. The
  /// conservative reading is taken — an unknown non-personal book is shown
  /// under *Businesses* rather than hidden, because a book the user owns must
  /// never disappear from the switcher (07 §1 rule 12, no dead ends).
  static HomeScopeGroup groupOfType(String wire) => switch (wire) {
    'personal' => HomeScopeGroup.me,
    'family' || 'joint' => HomeScopeGroup.family,
    'organization' => HomeScopeGroup.organizations,
    _ => HomeScopeGroup.businesses,
  };
}

/// A selected scope: one book, or the read-only aggregate (13 §2.2).
@immutable
final class HomeScope {
  /// One book.
  const HomeScope.book(String this.bookId) : isEverything = false;

  /// The read-only aggregate across every book the user can see.
  const HomeScope.everything() : bookId = null, isEverything = true;

  /// The book, or null in *Everything*.
  final String? bookId;

  /// True in *Everything* scope.
  final bool isEverything;

  @override
  bool operator ==(Object other) =>
      other is HomeScope &&
      other.bookId == bookId &&
      other.isEverything == isEverything;

  @override
  int get hashCode => Object.hash(bookId, isEverything);
}

/// Holds the books this device has and which scope Home is showing.
///
/// Feature-level on purpose: S1 owns the selection for as long as it is on
/// screen. Persisting it across tabs and launches is the shell's job (see the
/// file header).
class HomeScopeController extends ChangeNotifier {
  List<BookRef> _books = const [];
  HomeScope? _selected;

  /// Every book on this device, Me first (see [setBooks]).
  List<BookRef> get books => _books;

  /// The chosen scope, or null while nothing has been chosen yet.
  HomeScope? get selected => _selected;

  /// True once the user has more than one book (13 §2.2: hidden for an
  /// individual).
  bool get showsControl => _books.length > 1;

  /// 🔒 07 §5.7: the grouped sheet (S1.3) belongs to **three or more** books;
  /// exactly two get the inline toggle (S1.2), never the sheet.
  bool get isGrouped => _books.length >= 3;

  /// The scope to render, falling back to [fallbackBookId] (the book S1
  /// resolved for itself) and then to the first book.
  HomeScope? effective(String? fallbackBookId) {
    final selected = _selected;
    if (selected != null) return selected;
    // The books are ordered Me first (see [watchBookRefs]), so the default
    // scope is the user's own book — never whichever book the mirror happens
    // to list first.
    if (_books.isNotEmpty) return HomeScope.book(_books.first.id);
    if (fallbackBookId != null) return HomeScope.book(fallbackBookId);
    return null;
  }

  /// Replaces the book list; drops a selection whose book has gone away.
  void setBooks(List<BookRef> books) {
    if (_books.length == books.length) {
      var same = true;
      for (var i = 0; i < books.length; i++) {
        if (_books[i].id != books[i].id || _books[i].name != books[i].name) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    _books = List.unmodifiable(books);
    final selected = _selected;
    if (selected != null &&
        selected.bookId != null &&
        !books.any((b) => b.id == selected.bookId)) {
      _selected = null;
    }
    notifyListeners();
  }

  /// Chooses [scope] — the same screen re-renders in it (13 §2.2).
  void select(HomeScope scope) {
    if (_selected == scope) return;
    _selected = scope;
    notifyListeners();
  }
}

/// Every book on this device as the switcher needs it, Me first and then by
/// group order, name-ordered inside a group.
Stream<List<BookRef>> watchBookRefs(LocalLedger ledger) =>
    ledger.watchBooks().map((rows) {
      final refs =
          [
            for (final r in rows)
              BookRef(
                id: r.id,
                name: r.name,
                group: BookRef.groupOfType(r.type),
              ),
          ]..sort((a, b) {
            final g = a.group.index.compareTo(b.group.index);
            return g != 0 ? g : a.name.compareTo(b.name);
          });
      return refs;
    });
