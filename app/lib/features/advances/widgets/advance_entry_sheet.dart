// The two in-feature sheets behind S5's card actions (07 §8): `Add spend` and
// `Return remaining`. Deliberately *not* a hop into the S2 entry flow — that
// feature belongs to another lane, and both movements are fully determined by
// the advance itself (02 §7), so all the user supplies is an amount and, for
// a spend, the category it lands in.
//
// Every posting goes through `LocalLedger`, in integer paise, with the ledger's
// own injected clock for the date (CLAUDE.md rules 1 and 3).
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/money/paise_input.dart';

/// Which movement the sheet posts (02 §7).
enum AdvanceSheetMode {
  /// `Dr expense-category · Cr Advance – {member}`.
  spend,

  /// `Dr money · Cr Advance – {member}`.
  returnRemaining,
}

/// Opens the sheet for [advance]; resolves true when an entry was posted.
Future<bool?> showAdvanceEntrySheet(
  BuildContext context, {
  required AdvanceView advance,
  required AdvanceSheetMode mode,
  required List<AccountBalance> accounts,
}) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) =>
      AdvanceEntrySheet(advance: advance, mode: mode, accounts: accounts),
);

/// Amount (+ category, for a spend) → one posting against the advance.
class AdvanceEntrySheet extends StatefulWidget {
  /// Creates the sheet.
  const AdvanceEntrySheet({
    super.key,
    required this.advance,
    required this.mode,
    required this.accounts,
  });

  /// The advance the entry posts against.
  final AdvanceView advance;

  /// Spend or return.
  final AdvanceSheetMode mode;

  /// The book's live accounts, handed down by S5. The sheet does no reading of
  /// its own: it opens over data the screen is already watching, so there is
  /// no second load to fail and nothing to wait for behind the keypad.
  final List<AccountBalance> accounts;

  @override
  State<AdvanceEntrySheet> createState() => _AdvanceEntrySheetState();
}

class _AdvanceEntrySheetState extends State<AdvanceEntrySheet> {
  final _amount = TextEditingController();
  String? _counterpartId;
  String? _amountError;
  bool _saving = false;
  bool _failed = false;
  late final List<AccountBalance> _eligible = _pick(widget.accounts);

  bool get _isSpend => widget.mode == AdvanceSheetMode.spend;

  @override
  void initState() {
    super.initState();
    if (_eligible.isNotEmpty) _counterpartId = _eligible.first.account.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// A spend lands in an expense category; a return goes back into money
  /// (02 §7). Archived accounts are out of every picker (02 §1.2).
  List<AccountBalance> _pick(List<AccountBalance> rows) => rows
      .where((r) => !r.archived)
      .where(
        (r) => _isSpend
            ? r.account.accountClass == AccountClass.categoryExpense
            : r.account.isMoney,
      )
      .toList();

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final paise = paiseOf(_amount.text);
    if (paise == null) {
      setState(() => _amountError = l10n.advancesSheetAmountEmpty);
      return;
    }
    if (paise > widget.advance.remainingPaise) {
      setState(
        () => _amountError = l10n.advancesSheetAmountTooMuch(
          formatPaise(widget.advance.remainingPaise, locale: locale),
        ),
      );
      return;
    }
    final counterpart = _counterpartId;
    if (counterpart == null) return;
    setState(() {
      _amountError = null;
      _failed = false;
      _saving = true;
    });
    final ledger = LedgerScope.of(context);
    try {
      if (_isSpend) {
        await ledger.spendAgainstAdvance(
          bookId: widget.advance.bookId,
          advance: widget.advance.accountId,
          forWhat: counterpart,
          paise: paise,
          date: ledger.today(),
        );
      } else {
        await ledger.returnAdvance(
          bookId: widget.advance.bookId,
          advance: widget.advance.accountId,
          into: counterpart,
          paise: paise,
          date: ledger.today(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      // The write is append-only and atomic: a failure posted nothing, which
      // is exactly what the error line promises.
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          RkSpace.gutter,
          0,
          RkSpace.gutter,
          RkSpace.gutter + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isSpend
                    ? l10n.advancesSheetSpendTitle
                    : l10n.advancesSheetReturnTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: RkSpace.s4),
              TextField(
                controller: _amount,
                autofocus: true,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: RkType.amountRow,
                decoration: InputDecoration(
                  labelText: l10n.advancesSheetAmount,
                  prefixText: rupeeSign,
                  errorText: _amountError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(RkRadius.md),
                  ),
                ),
              ),
              const SizedBox(height: RkSpace.s4),
              if (_eligible.isEmpty)
                // No dead end: say what is missing and what to do (07 §1 rule
                // 6). Only reachable for a spend — every book has a money A/C.
                Text(
                  l10n.advancesSheetSpendCategoryNone,
                  style: theme.textTheme.bodyMedium,
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _counterpartId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _isSpend
                        ? l10n.advancesSheetSpendCategory
                        : l10n.advancesSheetReturnInto,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(RkRadius.md),
                    ),
                  ),
                  items: [
                    for (final r in _eligible)
                      DropdownMenuItem(
                        value: r.account.id,
                        child: Text(r.account.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _counterpartId = v),
                ),
              if (_failed) ...[
                const SizedBox(height: RkSpace.s3),
                Text(
                  l10n.advancesSheetError,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: status.danger,
                  ),
                ),
              ],
              const SizedBox(height: RkSpace.s4),
              Wrap(
                spacing: RkSpace.s2,
                runSpacing: RkSpace.s2,
                children: [
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(
                      _saving
                          ? l10n.advancesSheetSaving
                          : l10n.advancesSheetSave,
                    ),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(l10n.advancesSheetCancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
