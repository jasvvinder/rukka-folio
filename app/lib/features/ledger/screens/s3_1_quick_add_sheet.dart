// S3.1 Quick add sheet (07 §6, 13 §3.2): bottom-sheet A/C creation opened
// from the Ledger tab's `+ New A/C`. Same component family as the entry
// flow's full-screen picker (design S2-C) — this is the sheet presentation.
//
// Step 1 — a grid of type tiles (07 §6 step 1) decides the account's class;
// step 2 asks name + opening balance (02 §4: money asks "balance today",
// negative allowed for overdraft; a party asks who owes whom, answered here
// by which tile was picked, then just the amount). Categories skip the
// balance question — they default to zero for the current FY (02 §1.2).
// Posting is the shared path everyone uses: `addAccount` then, only for a
// non-zero opening figure, `openingBalances` (02 §4) — no bespoke posting
// logic lives in this widget.
//
// ⚠️ SPEC: 07 §6 step 1 lists eight tiles including "Capital". 02 §7.1 says a
// business's Capital/Drawings pair is created once, at business setup, as a
// structural pair — nothing in 02 says how (or whether) a ninth ad-hoc
// Capital account from this sheet should coexist with that pair. Rather than
// guess, this build offers the other seven tiles and leaves Capital as an
// open item (see the lane report).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/tokens.dart';

/// One tile of step 1 (07 §6). Carries the engine shape the tile creates and
/// how the opening-balance question is asked for it.
enum QuickAddTile {
  bank(AccountClass.money, MoneySubtype.saving),
  cash(AccountClass.money, MoneySubtype.cash),
  credit(AccountClass.money, MoneySubtype.cc),
  creditor(AccountClass.party, null, partySign: -1),
  debtor(AccountClass.party, null, partySign: 1),
  expense(AccountClass.categoryExpense, null, hasOpening: false),
  income(AccountClass.categoryIncome, null, hasOpening: false);

  const QuickAddTile(
    this.accountClass,
    this.subtype, {
    this.hasOpening = true,
    this.partySign = 0,
  });

  final AccountClass accountClass;
  final MoneySubtype? subtype;

  /// False for categories (02 §1.2: default to zero for the current FY).
  final bool hasOpening;

  /// For a party tile, the sign applied to the typed magnitude (+1 = they
  /// owe you / Dr, -1 = you owe them / Cr). Zero for non-party tiles, whose
  /// sign comes straight from what the user typed (negative = overdraft).
  final int partySign;

  bool get isParty => accountClass == AccountClass.party;

  String label(AppLocalizations l10n) => switch (this) {
    QuickAddTile.bank => l10n.ledgerQuickAddTypeBank,
    QuickAddTile.cash => l10n.ledgerQuickAddTypeCash,
    QuickAddTile.credit => l10n.ledgerQuickAddTypeCredit,
    QuickAddTile.creditor => l10n.ledgerQuickAddTypeCreditor,
    QuickAddTile.debtor => l10n.ledgerQuickAddTypeDebtor,
    QuickAddTile.expense => l10n.ledgerQuickAddTypeExpense,
    QuickAddTile.income => l10n.ledgerQuickAddTypeIncome,
  };

  IconData get icon => switch (this) {
    QuickAddTile.bank => Icons.account_balance,
    QuickAddTile.cash => Icons.payments_outlined,
    QuickAddTile.credit => Icons.credit_card,
    QuickAddTile.creditor => Icons.arrow_upward,
    QuickAddTile.debtor => Icons.arrow_downward,
    QuickAddTile.expense => Icons.trending_down,
    QuickAddTile.income => Icons.trending_up,
  };
}

/// Parses a plain rupee amount the user typed (`1234`, `1234.50`) into
/// signed integer paise — no floats touch money (CLAUDE.md rule 1). An empty
/// string is zero; anything else that doesn't match is invalid (`null`).
int? parseRupeesToPaise(String input) {
  final s = input.trim();
  if (s.isEmpty) return 0;
  final negative = s.startsWith('-');
  final body = negative ? s.substring(1) : s;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(body);
  if (m == null) return null;
  final rupees = int.parse(m.group(1)!);
  final fraction = (m.group(2) ?? '').padRight(2, '0');
  final paise = rupees * 100 + int.parse(fraction);
  return negative ? -paise : paise;
}

/// The S3.1 sheet body (host pushes it with `showModalBottomSheet`).
class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key, required this.bookId});

  /// The book the new account belongs to.
  final String bookId;

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  QuickAddTile? _tile;
  final _name = TextEditingController();
  final _amount = TextEditingController();
  bool _nameError = false;
  bool _amountError = false;
  bool _saving = false;
  bool _saveError = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(QuickAddTile tile) async {
    final name = _name.text.trim();
    final nameError = name.isEmpty;
    int? magnitude;
    var amountError = false;
    if (tile.hasOpening) {
      magnitude = parseRupeesToPaise(_amount.text);
      amountError = magnitude == null;
    }
    if (nameError || amountError) {
      setState(() {
        _nameError = nameError;
        _amountError = amountError;
      });
      return;
    }
    setState(() {
      _saving = true;
      _saveError = false;
    });
    try {
      final ledger = LedgerScope.of(context);
      final account = await ledger.addAccount(
        widget.bookId,
        name: name,
        accountClass: tile.accountClass,
        subtype: tile.subtype,
      );
      final signed = tile.isParty
          ? (magnitude ?? 0).abs() * tile.partySign
          : (magnitude ?? 0);
      if (signed != 0) {
        // Dated at the book's start (ADR 2026-09-09d §4): an opening balance
        // is the position on the day the books began, whenever the account
        // was added.
        await ledger.openingBalances(
          widget.bookId,
          balances: {account.id: signed},
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tile = _tile;
    return Padding(
      padding: EdgeInsets.only(
        left: RkSpace.gutter,
        right: RkSpace.gutter,
        top: RkSpace.s2,
        bottom: MediaQuery.of(context).viewInsets.bottom + RkSpace.s6,
      ),
      // The sheet is height-capped (half the screen on a short phone, less
      // again at 200% text scale), and step 1 is eight tall tiles — so the
      // body scrolls rather than overflowing (07 §1 rule 9).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.ledgerQuickAddTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: RkSpace.s4),
            if (tile == null) _typeGrid(l10n) else _details(l10n, tile),
          ],
        ),
      ),
    );
  }

  Widget _typeGrid(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.ledgerQuickAddTypeSection,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: RkSpace.s3),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: RkSpace.s2,
          crossAxisSpacing: RkSpace.s2,
          childAspectRatio: 2.4,
          children: [
            for (final t in QuickAddTile.values)
              _TypeCard(
                tile: t,
                label: t.label(l10n),
                onTap: () => setState(() => _tile = t),
              ),
          ],
        ),
        const SizedBox(height: RkSpace.s3),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ledgerQuickAddCancel),
          ),
        ),
      ],
    );
  }

  Widget _details(AppLocalizations l10n, QuickAddTile tile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tile.label(l10n), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: RkSpace.s3),
        TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.ledgerQuickAddNameLabel,
            hintText: l10n.ledgerQuickAddNameHint,
            errorText: _nameError ? l10n.ledgerQuickAddNameError : null,
          ),
          onChanged: (_) {
            if (_nameError) setState(() => _nameError = false);
          },
        ),
        if (tile.hasOpening) ...[
          const SizedBox(height: RkSpace.s3),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ],
            decoration: InputDecoration(
              prefixText: '₹',
              labelText: tile.isParty
                  ? l10n.ledgerQuickAddOpeningLabelParty
                  : l10n.ledgerQuickAddOpeningLabelMoney,
              hintText: l10n.ledgerQuickAddOpeningHint,
              errorText: _amountError ? l10n.ledgerQuickAddOpeningError : null,
            ),
            onChanged: (_) {
              if (_amountError) setState(() => _amountError = false);
            },
          ),
        ],
        if (_saveError) ...[
          const SizedBox(height: RkSpace.s2),
          Text(
            l10n.ledgerQuickAddSaveError,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: RkSpace.s4),
        // Stacked, full-width actions rather than a Row: the app theme gives
        // FilledButton `Size.fromHeight` (a full-bleed primary button), which
        // a Row would hand unbounded width — and stacking is what survives
        // 200% text scale on a 360 dp phone (07 §1 rule 9).
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : () => _save(tile),
            child: Text(l10n.ledgerQuickAddSave),
          ),
        ),
        const SizedBox(height: RkSpace.s2),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _saving ? null : () => setState(() => _tile = null),
            child: Text(l10n.ledgerQuickAddBack),
          ),
        ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.tile,
    required this.label,
    required this.onTap,
  });

  final QuickAddTile tile;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RkRadius.md),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(RkRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.s3,
            vertical: RkSpace.s2,
          ),
          child: Row(
            children: [
              Icon(tile.icon),
              const SizedBox(width: RkSpace.s2),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}
