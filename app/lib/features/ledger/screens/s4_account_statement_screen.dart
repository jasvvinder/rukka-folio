// S4 A/C statement (07 §6, 13 §3.2, design-system §5): the traditional
// three-column paper ledger — ਨਾਮੇ | ਜਮ੍ਹਾਂ | ਬਾਕੀ (Dr | Cr | Balance) — grouped
// by date, opening balance b/f first and closing balance c/f last. This is a
// PROFESSIONAL surface (02 §10 🔒): true ledger Dr/Cr, never Money in/out —
// the engine's sign never bends, `Vocabulary.professional` only picks words.
//
// The statement is scoped to one financial year, through the switcher ruled
// by ADR 2026-09-09 §4 🔒 (see `widgets/fy_switcher.dart`): the year is a chip
// once a year has closed and plain text before that, because a control that
// opens a list of one is a lie. The b/f is **computed** — the sum of this
// account's lines dated before the year began, which is correct for a
// continuous ledger — until Year Close (S10.4, M9) publishes the certified
// opening vector of 02 §8.1 to replace it. The c/f falls on the year's last
// day, or on today while the year is still open (07 §6 🔒, owner rule).
//
// Export (S8.1/S8.2) and entry detail (S4.1) are separate lanes; a row here
// only reports its entry id through [onOpenEntry].
import 'package:core_ledger/core_ledger.dart' hide StatementRow;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../ledger_book.dart';
import '../widgets/fy_switcher.dart';

class AccountStatementScreen extends StatefulWidget {
  const AccountStatementScreen({
    super.key,
    required this.accountId,
    this.bookId,
    this.onOpenEntry,
    this.closedYears = noClosedYears,
  });

  /// The account whose statement this is.
  final String accountId;

  /// Explicit book; when null the solo book is resolved ([soloBookId]).
  final String? bookId;

  final void Function(String entryId)? onOpenEntry;

  /// The certified-years seam (ADR 2026-09-09 §4, [ClosedYearsSource]). The
  /// default reports none, which is every build before Year Close (M9) — so
  /// the year ships as plain text and no switcher is drawn.
  final ClosedYearsSource closedYears;

  @override
  State<AccountStatementScreen> createState() => _AccountStatementScreenState();
}

class _AccountStatementScreenState extends State<AccountStatementScreen> {
  String? _bookId;
  Object? _resolveError;

  bool _resolveStarted = false;

  /// The book's FY calendar (02 §1.1), its certified years, and the year on
  /// screen — all resolved once, with the book.
  int _fyStartMonth = 4;
  List<ClosedYear> _closed = const [];
  FinancialYear? _fy;

  /// Memoised so a rebuild does not resubscribe the drift stream every frame.
  Stream<Statement>? _rows;
  String? _rowsKey;

  Stream<Statement> _statementStream(LocalLedger ledger, FinancialYear fy) {
    final key = '${widget.accountId}|${fy.label}|${fy.startMonth}';
    if (_rowsKey != key) {
      _rowsKey = key;
      _rows = ledger.watchStatement(
        widget.accountId,
        from: fy.firstDay,
        to: fy.lastDay,
      );
    }
    return _rows!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope is an InheritedWidget, so it may only be read from here on —
    // reading it in initState() throws, and a caught throw would pin the
    // screen to its error state forever (the same defect S3 carried).
    if (_resolveStarted) return;
    _resolveStarted = true;
    _resolveBook();
  }

  Future<void> _resolveBook() async {
    final ledger = LedgerScope.of(context);
    try {
      final id = widget.bookId ?? await soloBookId(ledger);
      final startMonth = await ledger.fyStartMonthOf(id);
      final closed = await widget.closedYears(id, widget.accountId);
      if (!mounted) return;
      setState(() {
        _bookId = id;
        _fyStartMonth = startMonth;
        _closed = closed;
        _fy = FinancialYear.of(ledger.today(), startMonth: startMonth);
      });
    } catch (e) {
      if (mounted) setState(() => _resolveError = e);
    }
  }

  void _retry() {
    setState(() => _resolveError = null);
    _resolveBook();
  }

  void _selectYear(FinancialYear fy) => setState(() => _fy = fy);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: _resolveError != null
            ? _ErrorState(text: l10n.ledgerStatementError, onRetry: _retry)
            : _bookId == null || _fy == null
            ? _Skeleton(label: l10n.ledgerStatementSkeleton)
            : _body(context, _bookId!),
      ),
    );
  }

  Widget _body(BuildContext context, String bookId) {
    final ledger = LedgerScope.of(context);
    return FutureBuilder<Chart>(
      future: ledger.chartOf(bookId),
      builder: (context, chartSnap) {
        final chart = chartSnap.data;
        if (chartSnap.hasError) {
          return _ErrorState(
            text: AppLocalizations.of(context).ledgerStatementError,
            onRetry: () => setState(() {}),
          );
        }
        if (chart == null) {
          return _Skeleton(
            label: AppLocalizations.of(context).ledgerStatementSkeleton,
          );
        }
        final account = chart.maybeAccount(widget.accountId);
        return StreamBuilder<Statement>(
          stream: _statementStream(ledger, _fy!),
          builder: (context, snap) {
            final l10n = AppLocalizations.of(context);
            return Scaffold(
              appBar: AppBar(title: Text(account?.name ?? l10n.ledgerTitle)),
              body: snap.hasError
                  ? _ErrorState(
                      text: l10n.ledgerStatementError,
                      onRetry: () => setState(() {}),
                    )
                  : snap.data == null
                  ? _Skeleton(label: l10n.ledgerStatementSkeleton)
                  : _statement(context, chart, snap.data!),
            );
          },
        );
      },
    );
  }

  Widget _statement(BuildContext context, Chart chart, Statement statement) {
    final l10n = AppLocalizations.of(context);
    final ledger = LedgerScope.of(context);
    final now = ledger.now();
    final fy = _fy!;
    // Nothing in this year *and* nothing carried into it: the account has
    // never been touched. A year with no rows but a b/f is a real statement —
    // the ledger is continuous — and still draws its b/f and c/f.
    if (statement.isEmpty && statement.openingPaise == 0) {
      return ListView(
        children: [
          // The switcher stays: an empty year must not be a dead end you
          // cannot switch out of (07 §1 rule 2).
          FySwitcher(
            selected: fy,
            closedYears: _closed,
            openYear: FinancialYear.of(
              ledger.today(),
              startMonth: _fyStartMonth,
            ),
            onSelected: _selectYear,
          ),
          _EmptyStatement(now: now),
        ],
      );
    }
    final today = ledger.today();
    final groups = <LocalDate, List<StatementRow>>{};
    final order = <LocalDate>[];
    for (final r in statement) {
      if (!groups.containsKey(r.date)) {
        groups[r.date] = [];
        order.add(r.date);
      }
      groups[r.date]!.add(r);
    }
    // 07 §6 🔒 (owner rule): the c/f is dated the period's last day, or
    // today's date while the period is still open.
    final closingDate = fy.contains(today) ? today : fy.lastDay;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s2),
      children: [
        FySwitcher(
          selected: fy,
          closedYears: _closed,
          openYear: FinancialYear.of(today, startMonth: _fyStartMonth),
          onSelected: _selectYear,
        ),
        _ColumnHeader(l10n: l10n),
        _OpeningClosingRow(
          label: l10n.ledgerStatementOpening,
          date: formatLedgerDate(fy.firstDay, strings: l10n),
          balancePaise: statement.openingPaise,
        ),
        for (final date in order) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              RkSpace.s1,
            ),
            child: Text(
              formatListDate(date, strings: l10n, now: now),
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: RkStatusColors.of(context).muted),
            ),
          ),
          for (final row in groups[date]!)
            _StatementLine(
              row: row,
              counterNames: [
                for (final id in row.counterAccountIds)
                  chart.maybeAccount(id)?.name ?? id,
              ],
              onTap: widget.onOpenEntry == null
                  ? null
                  : () => widget.onOpenEntry!(row.entryId),
            ),
        ],
        _OpeningClosingRow(
          label: l10n.ledgerStatementClosing,
          date: formatLedgerDate(closingDate, strings: l10n),
          balancePaise: statement.closingPaise,
        ),
      ],
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    Widget cell(String label) => Expanded(
      child: Semantics(
        header: true,
        child: Text(
          label,
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: status.muted),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: const SizedBox.shrink()),
          cell(l10n.moneySideDr),
          cell(l10n.moneySideCr),
          cell(l10n.ledgerStatementColumnBalance),
        ],
      ),
    );
  }
}

class _OpeningClosingRow extends StatelessWidget {
  const _OpeningClosingRow({
    required this.label,
    required this.date,
    required this.balancePaise,
  });

  final String label;
  final String date;
  final int balancePaise;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Builder(
        builder: (context) {
          final text = Text(
            '$label · $date',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: status.muted),
          );
          final amount = MoneyText(
            balancePaise,
            vocabulary: Vocabulary.professional,
            showDirection: true,
            favour: balancePaise == 0
                ? null
                : balancePaise > 0
                ? Favour.favourable
                : Favour.unfavourable,
          );
          // A Row lays the amount out at its natural width first, so at 200%
          // the label's Expanded collapses to nothing and the line overflows.
          // Past 1.3x the b/f and c/f lines stack instead (07 §1 rule 11).
          if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                text,
                const SizedBox(height: RkSpace.s1),
                amount,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: text),
              amount,
            ],
          );
        },
      ),
    );
  }
}

/// Width of a Dr or Cr figure column at 100% text scale — the statement's own
/// grid, not a design token: the three columns only have to agree with each
/// other and with [_ColumnHeader].
const double _amountColumn = 72;

/// Width of the running-balance column, wider because it also carries Dr/Cr.
const double _balanceColumn = 84;

class _StatementLine extends StatelessWidget {
  const _StatementLine({
    required this.row,
    required this.counterNames,
    this.onTap,
  });

  final StatementRow row;
  final List<String> counterNames;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final favour = row.amountPaise >= 0
        ? Favour.favourable
        : Favour.unfavourable;
    final runningFavour = row.runningBalancePaise == 0
        ? null
        : row.runningBalancePaise > 0
        ? Favour.favourable
        : Favour.unfavourable;

    // The three figure columns are sized in text, not pixels: at 200% the
    // fixed 72/72/84 of a paper ledger cannot fit beside the particulars on a
    // 360 px phone (07 §1 rule 11). Scaled, they either still fit — and the
    // columns stay aligned down the page, which is the whole point of a
    // statement — or the line folds and the figures take a row of their own.
    final scaler = MediaQuery.textScalerOf(context);
    final amountWidth = scaler.scale(_amountColumn);
    final balanceWidth = scaler.scale(_balanceColumn);

    Widget figure(int paise, {required bool blankWhenZero}) => MoneyText(
      paise,
      vocabulary: Vocabulary.professional,
      showDirection: !blankWhenZero,
      favour: blankWhenZero ? favour : runningFavour,
      textAlign: TextAlign.right,
    );

    // Blank, not zero: an empty Dr cell on a credit line is how a paper
    // ledger reads (07 §6).
    final Widget? debit = row.debitPaise == 0
        ? null
        : figure(row.debitPaise, blankWhenZero: true);
    final Widget? credit = row.creditPaise == 0
        ? null
        : figure(row.creditPaise, blankWhenZero: true);
    final balance = figure(row.runningBalancePaise, blankWhenZero: false);

    final particulars = Text(
      counterNames.isEmpty ? '—' : counterNames.join(', '),
      style: Theme.of(context).textTheme.bodyMedium,
    );
    final note = row.note == null ? null : Text(row.note!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final figuresWidth = amountWidth * 2 + balanceWidth;
        // Leave the particulars at least a third of the line before folding.
        final fits = figuresWidth <= constraints.maxWidth * 2 / 3;
        if (fits) {
          return ListTile(
            minTileHeight: RkSpace.rowMinHeight,
            onTap: onTap,
            title: particulars,
            subtitle: note,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: amountWidth, child: debit),
                SizedBox(width: amountWidth, child: credit),
                SizedBox(width: balanceWidth, child: balance),
              ],
            ),
          );
        }
        // Folded: the figures take a row of their own and share the width,
        // so nothing is forced to a size the line cannot give it.
        return ListTile(
          minTileHeight: RkSpace.rowMinHeight,
          onTap: onTap,
          title: particulars,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ?note,
              const SizedBox(height: RkSpace.s1),
              Row(
                children: [
                  Expanded(child: debit ?? const SizedBox.shrink()),
                  Expanded(child: credit ?? const SizedBox.shrink()),
                  Expanded(child: balance),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyStatement extends StatelessWidget {
  const _EmptyStatement({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.ledgerStatementEmpty,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: RkSpace.s2),
          Text(
            l10n.ledgerStatementEmptyAction,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: RkSpace.s3),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: RkSpace.s4),
            FilledButton(onPressed: onRetry, child: Text(l10n.ledgerListRetry)),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      child: ListView.builder(
        padding: const EdgeInsets.all(RkSpace.gutter),
        itemCount: 6,
        itemBuilder: (context, i) => Container(
          height: RkSpace.rowMinHeight,
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: i.isEven
                  ? RkMotion.skeletonLabelWidthMax
                  : RkMotion.skeletonLabelWidthMin,
              child: Container(
                height: RkSpace.s3,
                decoration: BoxDecoration(
                  color: status.skeletonLabel,
                  borderRadius: BorderRadius.circular(RkRadius.sm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
