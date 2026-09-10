// S1.1 Position line drill-down (07 §4 "every line drills into its list";
// 13 §3.2 row S1.1): one screen parameterised by [PositionLine] that shows
// the accounts standing behind a Home position row, with the line's total,
// each row tapping through to that account's A/C statement (S4).
//
// Consumer surface (02 §10 🔒, CLAUDE.md rule 9): signed amounts and plain
// words, never Dr/Cr — those start at the statement. Integer paise
// throughout; colour is never alone (the sign and the label carry it too).
//
// The membership rule of every line is [rowsFor], which mirrors
// `LocalLedger.watchPosition` exactly (02 §9) rather than inventing a second
// classification — if the two ever drift, the position card and its own
// drill-down would disagree, which is the one thing this screen must not do.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../ledger/ledger_book.dart';
import '../home_paths.dart';
import '../widgets/home_states.dart';

/// The accounts behind [line], in the order the position card reads them
/// (creation order — 02 §9). [accountId], when given, narrows the list to
/// that one account: a Home bank row names its own account.
///
/// Pure, so the rule can be tested without a database.
List<AccountBalance> rowsFor(
  List<AccountBalance> accounts,
  PositionLine line, {
  String? accountId,
}) {
  final ordered = [
    for (final a in accounts)
      if (!a.archived) a,
  ]..sort((a, b) => a.account.createdOrder.compareTo(b.account.createdOrder));
  bool keep(AccountBalance r) {
    final a = r.account;
    switch (line) {
      case PositionLine.cash:
        return a.accountClass == AccountClass.money &&
            a.subtype == MoneySubtype.cash;
      case PositionLine.bank:
        return a.accountClass == AccountClass.money &&
            a.subtype != MoneySubtype.cash &&
            a.subtype != MoneySubtype.cashCollection;
      case PositionLine.youWillGet:
        return a.accountClass == AccountClass.party && r.balancePaise > 0;
      case PositionLine.youWillGive:
        return a.accountClass == AccountClass.party && r.balancePaise < 0;
      case PositionLine.advancesOut:
        return a.accountClass == AccountClass.advance && r.balancePaise != 0;
      case PositionLine.inTransit:
        return a.accountClass == AccountClass.equitySystem &&
            a.systemRole == SystemRole.dueToFrom;
    }
  }

  return [
    for (final r in ordered)
      if (keep(r) && (accountId == null || r.account.id == accountId)) r,
  ];
}

/// The position row's own label — the S1.1 app-bar title (13 §3.2 row S1.1).
String positionLineLabel(AppLocalizations l10n, PositionLine line) =>
    switch (line) {
      PositionLine.cash => l10n.homePositionCash,
      PositionLine.bank => l10n.homePositionTitle,
      PositionLine.youWillGet => l10n.homePositionYouWillGet,
      PositionLine.youWillGive => l10n.homePositionYouWillGive,
      PositionLine.advancesOut => l10n.homePositionAdvancesOut,
      PositionLine.inTransit => l10n.homePositionInTransit,
    };

/// S1.1 — the list behind one Home position row.
class PositionDrilldownScreen extends StatefulWidget {
  /// Creates the screen.
  const PositionDrilldownScreen({
    super.key,
    required this.line,
    this.accountId,
    this.bookId,
    this.onOpenAccount,
    this.onRecordEntry,
  });

  /// Which position row was tapped.
  final PositionLine line;

  /// Narrows the list to one account (a Home bank row).
  final String? accountId;

  /// Explicit book; when null the solo book is resolved ([soloBookId]).
  final String? bookId;

  /// Opens an account's A/C statement (S4).
  final void Function(String accountId)? onOpenAccount;

  /// The empty state's one next action (13 §8): record an entry.
  final VoidCallback? onRecordEntry;

  @override
  State<PositionDrilldownScreen> createState() =>
      _PositionDrilldownScreenState();
}

class _PositionDrilldownScreenState extends State<PositionDrilldownScreen> {
  String? _bookId;
  Object? _resolveError;
  bool _resolveStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // LedgerScope is inherited: readable from here on, never in initState().
    if (_resolveStarted) return;
    _resolveStarted = true;
    _resolveBook();
  }

  Future<void> _resolveBook() async {
    if (widget.bookId != null) {
      setState(() => _bookId = widget.bookId);
      return;
    }
    final ledger = LedgerScope.of(context);
    try {
      final id = await soloBookId(ledger);
      if (mounted) setState(() => _bookId = id);
    } catch (e) {
      if (mounted) setState(() => _resolveError = e);
    }
  }

  void _retry() {
    setState(() {
      _resolveError = null;
      _bookId = null;
    });
    _resolveBook();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.homeDrilldownTitle(positionLineLabel(l10n, widget.line)),
        ),
      ),
      body: SafeArea(
        child: _resolveError != null
            ? HomeErrorState(
                text: l10n.homeDrilldownError,
                retryLabel: l10n.homeRetry,
                onRetry: _retry,
              )
            : _bookId == null
            ? HomeSkeleton(label: l10n.homeDrilldownSkeleton)
            : _body(context, _bookId!),
      ),
    );
  }

  Widget _body(BuildContext context, String bookId) {
    final l10n = AppLocalizations.of(context);
    final ledger = LedgerScope.of(context);
    return StreamBuilder<List<AccountBalance>>(
      stream: ledger.watchAccounts(bookId),
      builder: (context, snap) {
        if (snap.hasError) {
          return HomeErrorState(
            text: l10n.homeDrilldownError,
            retryLabel: l10n.homeRetry,
            onRetry: () => setState(() {}),
          );
        }
        final all = snap.data;
        if (all == null) {
          return HomeSkeleton(label: l10n.homeDrilldownSkeleton);
        }
        final rows = rowsFor(all, widget.line, accountId: widget.accountId);
        if (rows.isEmpty) return _empty(context);
        final total = rows.fold<int>(0, (s, r) => s + r.balancePaise);
        return ListView(
          padding: const EdgeInsets.only(bottom: RkSpace.s10),
          children: [
            RkRuledCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in rows)
                    RkLabelAmountRow(
                      label: Text(
                        r.account.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      amount: MoneyText(r.balancePaise),
                      onTap: widget.onOpenAccount == null
                          ? null
                          : () => widget.onOpenAccount!(r.account.id),
                      semanticHint: widget.onOpenAccount == null
                          ? null
                          : l10n.homePositionDrill,
                    ),
                ],
              ),
            ),
            // The line's own total, in the same words as the position row it
            // came from — the two must read the same (02 §9).
            RkLabelAmountRow(
              label: Text(
                l10n.homeDrilldownTotal,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              amount: MoneyText(total),
            ),
          ],
        );
      },
    );
  }

  /// Empty, with the one next action (13 §4.3, 13 §8) — never a dead end.
  Widget _empty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        Text(
          l10n.homeDrilldownEmpty,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: status.muted),
        ),
        if (widget.onRecordEntry != null) ...[
          const SizedBox(height: RkSpace.s4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: widget.onRecordEntry,
              icon: const Icon(Icons.add),
              label: Text(l10n.homeDrilldownEmptyAction),
            ),
          ),
        ],
      ],
    );
  }
}
