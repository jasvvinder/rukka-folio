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
import '../entry_slots.dart';

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
    final canCreate = widget.spec.creatable.isNotEmpty && name.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: _asking
              ? _ClassQuestion(
                  classes: widget.spec.creatable,
                  onChoose: (c) => widget.onCreate(name, c),
                )
              : rows.isEmpty
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
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => _AccountRow(
                    row: rows[i],
                    onTap: () => widget.onPick(rows[i].account.id),
                  ),
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
