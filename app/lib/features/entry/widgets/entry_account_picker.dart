// S2.1 — the counterpart picker, **in place** (07 §5 step 3 + the
// single-screen block 🔒). It replaces the keypad in the lower region: not a
// modal sheet (a mode change mid-flow) and not a second screen (which hides
// what the user already set). Recents and favourites fill it — most-used
// first — with search at the bottom and inline create per 02 §1.2.
//
// The class is inferred from the slot ([SlotSpec.creatable]); the one
// two-chip question is asked only where the slot is genuinely ambiguous
// (Money out FOR = an expense *or* a person you are paying). A search miss is
// never a dead end (07 §1 rule 6): the create row sits below the list.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../entry_books.dart';
import '../entry_slots.dart';

/// Widget keys S2.1's own tests drive the picker by.
abstract final class EntryPickerKeys {
  /// One book row in the S2.3 *To* chooser.
  static Key book(String bookId) => Key('entry.picker.book.$bookId');

  /// The header that leaves another book's list.
  static const bookBack = Key('entry.picker.book_back');
}

/// The word for a creatable class — consumer vocabulary (02 §10 🔒).
String createChipLabel(AppLocalizations l10n, AccountClass c) => switch (c) {
  AccountClass.categoryIncome => l10n.entryCreateIncome,
  AccountClass.categoryExpense => l10n.entryCreateExpense,
  _ => l10n.entryCreatePerson,
};

/// The in-place account list for one slot.
class EntryAccountPicker extends StatefulWidget {
  /// Creates the picker.
  const EntryAccountPicker({
    super.key,
    required this.spec,
    required this.rows,
    required this.onPick,
    required this.onCreate,
    this.searchKey,
    this.createKey,
    this.books = const [],
    this.onPickBook,
    this.inBook,
    this.onLeaveBook,
  });

  /// The slot being answered — its classes and what it may mint.
  final SlotSpec spec;

  /// Candidates, already filtered and ordered by the caller.
  final List<AccountBalance> rows;

  /// An account was chosen; the keypad returns.
  final void Function(String accountId) onPick;

  /// Create [name] as [accountClass], then choose it (02 §1.2).
  final void Function(String name, AccountClass accountClass) onCreate;

  /// Key for the search field.
  final Key? searchKey;

  /// Key for the create row.
  final Key? createKey;

  /// S2.3 only (13 §3.2 *within/between books*): the other books this device
  /// holds, offered **beside** this book's money accounts. Empty everywhere
  /// else, and on a solo install — which is why an ordinary transfer is
  /// unchanged by this list existing.
  final List<EntryBook> books;

  /// A book was chosen: the list stays open and swaps to that book's money
  /// accounts (07 §10's *To (book + money A/C)*), keeping the amount.
  final void Function(String bookId)? onPickBook;

  /// The name of the book being listed, when it is not this entry's own —
  /// the header that says where these accounts live.
  final String? inBook;

  /// Back out of [inBook] to this book's own list. Never a dead end (07 §1
  /// rule 6): a wrong book is one tap to undo.
  final VoidCallback? onLeaveBook;

  @override
  State<EntryAccountPicker> createState() => _EntryAccountPickerState();
}

class _EntryAccountPickerState extends State<EntryAccountPicker> {
  final TextEditingController _query = TextEditingController();
  bool _asking = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<AccountBalance> get _visible {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.rows;
    return [
      for (final r in widget.rows)
        if (r.account.name.toLowerCase().contains(q)) r,
    ];
  }

  void _create() {
    final classes = widget.spec.creatable;
    if (classes.length == 1) {
      widget.onCreate(_query.text.trim(), classes.single);
      return;
    }
    setState(() => _asking = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final name = _query.text.trim();
    final rows = _visible;
    final q = _query.text.trim().toLowerCase();
    final books = widget.inBook != null
        ? const <EntryBook>[]
        : [
            for (final b in widget.books)
              if (q.isEmpty || b.name.toLowerCase().contains(q)) b,
          ];
    // Nothing may be created inside another book from here: an account is
    // minted into the book that owns it (02 §1.2), and the create row's
    // class is inferred from *this* entry's slot. Refused rather than
    // guessed.
    final canCreate =
        widget.spec.creatable.isNotEmpty &&
        name.isNotEmpty &&
        widget.inBook == null;

    return Column(
      children: [
        // 07 §10's *To (book + money A/C)*: once a book is chosen the list is
        // that book's, and it says so.
        if (widget.inBook != null)
          ListTile(
            key: EntryPickerKeys.bookBack,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.arrow_back),
            title: Text(
              widget.inBook!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RkType.body,
            ),
            onTap: widget.onLeaveBook,
          ),
        Expanded(
          child: _asking
              ? _ClassQuestion(
                  classes: widget.spec.creatable,
                  onChoose: (c) => widget.onCreate(name, c),
                )
              : rows.isEmpty && books.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RkSpace.s4),
                    child: Text(
                      l10n.entryPickerEmpty(name),
                      textAlign: TextAlign.center,
                      style: RkType.body.copyWith(color: status.muted),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    // The other books sit *beside* the accounts in one
                    // chooser — 13 §3.2 row S2.3 is both destinations, not
                    // two doors — and above them, because 07 §10 🔒 asks for
                    // the **book** before the money A/C and because a row a
                    // member must scroll a short lower region to reach is a
                    // row they will not find. A solo install has none, so an
                    // ordinary transfer never pays for this.
                    if (books.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          RkSpace.s4,
                          RkSpace.s2,
                          RkSpace.s4,
                          0,
                        ),
                        child: Text(
                          l10n.entryMoveBooksHeader,
                          style: RkType.caption.copyWith(color: status.muted),
                        ),
                      ),
                      for (final b in books)
                        ListTile(
                          key: EntryPickerKeys.book(b.id),
                          dense: true,
                          leading: const Icon(Icons.menu_book_outlined),
                          title: Text(
                            b.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: widget.onPickBook == null
                              ? null
                              : () => widget.onPickBook!(b.id),
                        ),
                    ],
                    for (final r in rows)
                      _AccountRow(
                        row: r,
                        onTap: () => widget.onPick(r.account.id),
                      ),
                  ],
                ),
        ),
        // The create row is chrome, not content: it stays one line however
        // far the text scales, so the account list keeps a whole row of the
        // lower region at 200 % on 360×800 (07 §1 accessibility, 13 §8).
        // Letting it wrap to three lines squeezed the list to a ~20 pt strip
        // in which no row could be read or tapped.
        if (canCreate && !_asking)
          ListTile(
            key: widget.createKey,
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.add),
            title: Text(
              l10n.entryCreateRow(name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: _create,
          ),
        // Search at the bottom (07 §5 step 3) — under the thumb, not under
        // the notch.
        Padding(
          padding: const EdgeInsets.only(top: RkSpace.s2),
          child: TextField(
            key: widget.searchKey,
            controller: _query,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.entrySearchHint,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.row, required this.onTap});

  final AccountBalance row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      title: Text(
        row.account.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // The balance is professional detail on a consumer screen only as a
      // figure — no Dr/Cr word here (02 §10 🔒, CLAUDE.md rule 9).
      trailing: MoneyText(row.balancePaise, style: RkType.caption),
    );
  }
}

class _ClassQuestion extends StatelessWidget {
  const _ClassQuestion({required this.classes, required this.onChoose});

  final List<AccountClass> classes;
  final void Function(AccountClass) onChoose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The question sits in whatever the lower region has left — a few dozen
    // pixels once the create row and the search field have taken theirs, and
    // less again at 200 %. It scrolls *inside the picker* rather than
    // overflowing: 07 §5's "never scrolls" 🔒 governs the entry screen, which
    // still does not move; the lower region has always held a scrolling
    // account list.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RkSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.entryCreateAsk, style: RkType.section),
          const SizedBox(height: RkSpace.s3),
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s2,
            children: [
              for (final c in classes)
                OutlinedButton(
                  onPressed: () => onChoose(c),
                  child: Text(createChipLabel(l10n, c)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
