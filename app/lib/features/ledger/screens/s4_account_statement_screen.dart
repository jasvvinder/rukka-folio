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
// **Export** is the trio of ADR 2026-09-12e §2 🔒 — *View · Download/Share ·
// Export (PDF/CSV/XLSX)* — binding on S4 since the owner confirmed it on
// 13 Sep, and the same bar S8.2 wears: **View** is this screen, **Download /
// Share** writes a PDF and hands it straight to the platform share sheet (the
// format a person hands to someone else — ADR 2026-09-12d §2–§3 🔒), and
// **Export** opens the three-format sheet. The report itself is built in
// `features/reports/statement_report.dart` from the rows already on screen,
// so paper and screen are the same statement by construction. A successful
// share gets no sentence from us; a share that could not be raised names the
// file it wrote instead (ADR 2026-09-13 §1 🔒), so the path is never a dead end.
//
// Entry detail (S4.1) is a separate lane; a row here only reports its entry id
// through [onOpenEntry].
import 'dart:async';
import 'dart:math' as math;

import 'package:core_ledger/core_ledger.dart' hide StatementRow;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../reports/day_book.dart' show reportHeading;
import '../../reports/export/file_report_sink.dart';
import '../../reports/export/csv_report.dart';
import '../../reports/export/pdf_report.dart';
import '../../reports/export/report_export.dart';
import '../../reports/export/xlsx_report.dart';
import '../../reports/statement_report.dart';
import '../../reports/widgets/export_actions.dart';
import '../../reports/widgets/export_sheet.dart';
import '../ledger_book.dart';
import '../widgets/cash_count_header.dart';
import '../widgets/text_metrics.dart';
import '../../../shared/seams/closed_years.dart';
import '../widgets/fy_switcher.dart';

class AccountStatementScreen extends StatefulWidget {
  const AccountStatementScreen({
    super.key,
    required this.accountId,
    this.bookId,
    this.onOpenEntry,
    this.onCountCash,
    this.closedYears = noClosedYears,
    this.sink = shareReportFile,
  });

  /// The account whose statement this is.
  final String accountId;

  /// Explicit book; when null the solo book is resolved ([soloBookId]).
  final String? bookId;

  final void Function(String entryId)? onOpenEntry;

  /// Opens S5.5 for this A/C — the *Count again* / *Open and count* door
  /// 02 §8.2 🔒 puts in the statement header of a `cash` or `cash_collection`
  /// account. Null draws no button (no dead door, 07 §1 rule 6); every other
  /// account draws none either way.
  final void Function(String accountId)? onCountCash;

  /// The certified-years seam (ADR 2026-09-09 §4, [ClosedYearsSource]). The
  /// default reports none, which is every build before Year Close (M9) — so
  /// the year ships as plain text and no switcher is drawn.
  final ClosedYearsSource closedYears;

  /// Where a generated report goes ([ReportSink]). The app raises the platform
  /// share sheet and names a file only if it cannot (ADR 2026-09-13 §1 🔒); a
  /// test injects a fake and reads the bytes.
  final ReportSink sink;

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

  /// The book's name, for the head of an exported statement.
  String _bookName = '';

  /// The latest statement and chart, kept so an export can run without
  /// re-reading the ledger — the file is then the very rows on screen.
  Statement? _latest;
  Chart? _chart;

  /// True while a file is being written. Shown as the 2 px loader **rule**,
  /// never a spinner (11 §4.5 🔒, 13 §4.3 loading state).
  bool _generating = false;

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
    // The FY switcher's source is the shell's when the shell has one (ADR
    // 2026-09-09 §4 🔒) and the constructor's otherwise — a missing scope is
    // never an error and never a red screen (07 §1 rule 6). Read here, beside
    // the ledger and **before** the first await: an InheritedWidget may not be
    // reached for across an async gap.
    final years = ClosedYearsScope.maybeOf(context) ?? widget.closedYears;
    try {
      final id = widget.bookId ?? await soloBookId(ledger);
      final startMonth = await ledger.fyStartMonthOf(id);
      // A plain future, never a stream's `.first`: a drift query stream's first
      // event arrives on a zero-duration timer that a widget test's fake-async
      // zone never lets fire.
      final heading = await reportHeading(ledger, id);
      final closed = await years(id, widget.accountId);
      if (!mounted) return;
      setState(() {
        _bookId = id;
        _bookName = heading.bookName;
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

  void _selectYear(FinancialYear fy) => setState(() {
    _fy = fy;
    _latest = null;
  });

  /// Builds the statement in [format] from the rows already on screen.
  ///
  /// Everything that needs the tree — strings, locale, the chart — is read
  /// **before** the first await: loading the PDF's fonts is asynchronous, and a
  /// context read after an await is a disposed context away from a crash.
  Future<ReportFile> _buildFile(ReportFormat format) async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final ledger = LedgerScope.of(context);
    final chart = _chart;
    final fy = _fy!;
    final statement =
        _latest ??
        Statement(
          accountId: widget.accountId,
          rows: const [],
          openingPaise: 0,
          from: fy.firstDay,
          to: fy.lastDay,
        );
    final today = ledger.today();
    final accountName =
        chart?.maybeAccount(widget.accountId)?.name ?? widget.accountId;
    final table = statementTable(
      statement,
      accountName: accountName,
      bookName: _bookName,
      period: l10n.ledgerStatementFy(fy.label),
      labels: StatementReportLabels.of(l10n),
      counterNames: (row) => [
        for (final id in row.counterAccountIds)
          chart?.maybeAccount(id)?.name ?? id,
      ],
      formatDate: (date) => formatLedgerDate(date, strings: l10n),
      openingDate: fy.firstDay,
      // 07 §6 🔒 (owner rule): the c/f is dated the period's last day, or
      // today's date while the period is still open — the same date the
      // screen's c/f row carries.
      closingDate: fy.contains(today) ? today : fy.lastDay,
    );
    final fileName = l10n.reportsStatementFileName(fy.label, format.extension);

    switch (format) {
      case ReportFormat.pdf:
        // The faces are loaded per export, not held: package:pdf embeds the
        // glyphs it draws, and Helvetica — its default — has no Gurmukhi and
        // no Devanagari (see `reports/export/pdf_report.dart`).
        final fonts = await ReportFonts.load();
        return reportTablePdfFile(
          table,
          pageNumber: (page, pages) => l10n.reportsExportPage(page, pages),
          fonts: fonts,
          locale: locale,
          fileName: fileName,
        );
      case ReportFormat.csv:
        return reportTableCsvFile(table, fileName: fileName);
      case ReportFormat.xlsx:
        return reportTableXlsxFile(table, fileName: fileName);
    }
  }

  /// Generates, delivers, and says only what the delivery leaves unsaid — a
  /// share sheet is its own confirmation, a written file must be named
  /// (ADR 2026-09-13 §1 🔒). The loader rule runs for as long as it takes.
  Future<void> _export(ReportFormat format) async {
    if (_generating) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _generating = true);
    try {
      await runReportExport(
        l10n: l10n,
        messenger: messenger,
        format: format,
        buildFile: _buildFile,
        sink: widget.sink,
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// The primary action: **PDF**, with no sheet in between (ADR 2026-09-12d
  /// §2 🔒).
  void _exportDefault() => unawaited(_export(ReportFormat.pdf));

  void _openExportSheet() {
    showReportExportSheet(
      context,
      // The sheet closes itself before the file is written, so the loader
      // belongs to this screen: it runs around the generating, which is the
      // part that takes time (the PDF loads five font faces).
      buildFile: (format) async {
        setState(() => _generating = true);
        try {
          return await _buildFile(format);
        } finally {
          if (mounted) setState(() => _generating = false);
        }
      },
      sink: widget.sink,
    );
  }

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
        _chart = chart;
        final account = chart.maybeAccount(widget.accountId);
        return StreamBuilder<Statement>(
          stream: _statementStream(ledger, _fy!),
          builder: (context, snap) {
            final l10n = AppLocalizations.of(context);
            final statement = snap.data;
            if (statement != null) _latest = statement;
            return Scaffold(
              appBar: AppBar(
                title: Text(account?.name ?? l10n.ledgerTitle),
                // The export trio of ADR 2026-09-12e §2 🔒: this screen is
                // *View*, and these are *Download / Share* and *Export*. They
                // are the same two widgets S8.2 wears, so neither bar can
                // drift from the other (see `reports/widgets/
                // export_actions.dart` for how the pair survives 200 % text
                // scale on a 360 px phone).
                actions: [
                  ReportExportAction(onPressed: _exportDefault),
                  ReportChooseFormatAction(onPressed: _openExportSheet),
                ],
              ),
              body: Column(
                children: [
                  // The wait is a 2 px rule with words beside it, never a
                  // spinner (11 §4.5 🔒, 13 §4.3).
                  if (_generating) const _GeneratingRule(),
                  Expanded(
                    child: snap.hasError
                        ? _ErrorState(
                            text: l10n.ledgerStatementError,
                            onRetry: () => setState(() {}),
                          )
                        : statement == null
                        ? _Skeleton(label: l10n.ledgerStatementSkeleton)
                        : _statement(context, chart, statement),
                  ),
                ],
              ),
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
          // 02 §8.2 🔒: the count block sits in the header, above the year —
          // an account with no entries this year is exactly the one you may
          // want to count.
          if (chart.maybeAccount(widget.accountId) case final account?)
            CashCountHeader(account: account, onCount: widget.onCountCash),
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

    String particularsOf(StatementRow row) {
      final names = [
        for (final id in row.counterAccountIds)
          chart.maybeAccount(id)?.name ?? id,
      ];
      return names.isEmpty ? '\u2014' : names.join(', ');
    }

    // Measured once for the whole page, so every row and the heading agree on
    // where a column starts (see [_StatementGrid]).
    final grid = _StatementGrid.measure(
      context,
      rows: statement,
      particularsOf: particularsOf,
      width: MediaQuery.sizeOf(context).width,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s2),
      children: [
        // The statement header of a cash / cash_collection A/C carries the
        // last count and the door to S5.5 (02 §8.2 🔒 *Where it appears*).
        if (chart.maybeAccount(widget.accountId) case final account?)
          CashCountHeader(account: account, onCount: widget.onCountCash),
        FySwitcher(
          selected: fy,
          closedYears: _closed,
          openYear: FinancialYear.of(today, startMonth: _fyStartMonth),
          onSelected: _selectYear,
        ),
        _ColumnHeader(l10n: l10n, grid: grid),
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
              grid: grid,
              particulars: particularsOf(row),
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

/// The wait while a report is written: the 2 px loader **rule** of 11 §4.5 🔒
/// with the words beside it, announced as a live region. Never a spinner, and
/// never colour alone (07 §1 rule 3) — the sentence is what says what is
/// happening, the rule only says it is still happening.
class _GeneratingRule extends StatelessWidget {
  const _GeneratingRule();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          minHeight: RkMotion.loaderTrackHeight,
          backgroundColor: status.loaderTrack,
          color: status.loaderSegment,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s2,
          ),
          child: Semantics(
            liveRegion: true,
            child: Text(
              l10n.reportsExportGenerating,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: status.muted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which of the three statement layouts the page can afford.
///
/// A paper ledger's columns are only worth having while every figure fits in
/// one. A figure given less room than it needs is not abbreviated, it is
/// **cut** — `₹1,14,600` drawn as `₹1,14,6` — and a cut figure is a wrong
/// figure, which is why 07 §1 forbids re-sizing a tabular figure by hand. So
/// the grid never assumes a column width: it measures the widest thing each
/// column must hold, at the reader's own text scale and in the reader's own
/// script, and then takes the richest layout that holds all of them.
enum _GridMode {
  /// The paper ledger: particulars on the left, the three figures beside
  /// them, headed by [_ColumnHeader].
  columns,

  /// The figures keep their columns — and their alignment with the heading —
  /// but take a line of their own beneath the particulars.
  rows,

  /// Three columns will not fit at all (200 % text on a 360 px phone is
  /// here). Every figure takes its own line, named by the word the heading
  /// would have carried, and the heading itself is dropped rather than drawn
  /// over its own edge.
  stacked,
}

/// The statement's own grid: the measured width of each figure column, and
/// the layout those widths allow. Not a design token — the three columns only
/// have to agree with each other and with [_ColumnHeader].
@immutable
class _StatementGrid {
  const _StatementGrid({
    required this.mode,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  /// The layout the page can afford.
  final _GridMode mode;

  /// Dr column width, gutter included.
  final double debit;

  /// Cr column width, gutter included.
  final double credit;

  /// Running-balance column width — wider, because it also carries Dr/Cr.
  final double balance;

  /// Measures the grid for [rows] on a line [width] wide.
  static _StatementGrid measure(
    BuildContext context, {
    required Iterable<StatementRow> rows,
    required String Function(StatementRow) particularsOf,
    required double width,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final figureStyle = (text.labelLarge ?? RkType.amountRow).copyWith(
      fontFeatures: RkType.tabular,
    );
    final headingStyle = text.labelLarge;
    final particularsStyle = text.bodyMedium;

    double run(String s, TextStyle? style) => textRunWidth(context, s, style);
    // Particulars wrap, so what they need is their longest *unbreakable*
    // word — the same thing a squeezed paragraph draws past its edge.
    double word(String s, TextStyle? style) =>
        longestWordWidth(context, s, style);
    String figure(int paise, {required bool withSide}) =>
        professionalFigure(context, paise, withSide: withSide);

    var debit = run(l10n.moneySideDr, headingStyle);
    var credit = run(l10n.moneySideCr, headingStyle);
    var balance = run(l10n.ledgerStatementColumnBalance, headingStyle);
    var particulars = 0.0;
    for (final row in rows) {
      if (row.debitPaise != 0) {
        debit = math.max(
          debit,
          run(figure(row.debitPaise, withSide: false), figureStyle),
        );
      }
      if (row.creditPaise != 0) {
        credit = math.max(
          credit,
          run(figure(row.creditPaise, withSide: false), figureStyle),
        );
      }
      balance = math.max(
        balance,
        run(figure(row.runningBalancePaise, withSide: true), figureStyle),
      );
      particulars = math.max(
        particulars,
        word(particularsOf(row), particularsStyle),
      );
      if (row.note case final note?) {
        particulars = math.max(particulars, word(note, particularsStyle));
      }
    }
    // Each column is its widest content plus the gutter that keeps two
    // figures from touching.
    debit += RkSpace.s2;
    credit += RkSpace.s2;
    balance += RkSpace.s2;
    // The line a row actually has, inside the tile's own padding.
    final line = width - RkSpace.gutter * 2;
    final figures = debit + credit + balance;
    return _StatementGrid(
      mode: figures + particulars <= line
          ? _GridMode.columns
          : figures <= line
          ? _GridMode.rows
          : _GridMode.stacked,
      debit: debit,
      credit: credit,
      balance: balance,
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.l10n, required this.grid});

  final AppLocalizations l10n;
  final _StatementGrid grid;

  @override
  Widget build(BuildContext context) {
    // Stacked: there are no columns to head, and each row names its own
    // figures instead.
    if (grid.mode == _GridMode.stacked) return const SizedBox.shrink();
    final status = RkStatusColors.of(context);
    Widget cell(String label, double width) => SizedBox(
      width: width,
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
          const Spacer(),
          cell(l10n.moneySideDr, grid.debit),
          cell(l10n.moneySideCr, grid.credit),
          cell(l10n.ledgerStatementColumnBalance, grid.balance),
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

class _StatementLine extends StatelessWidget {
  const _StatementLine({
    required this.row,
    required this.grid,
    required this.particulars,
    this.onTap,
  });

  final StatementRow row;
  final _StatementGrid grid;

  /// The counter accounts, already joined — the *other* side of this entry.
  final String particulars;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final favour = row.amountPaise >= 0
        ? Favour.favourable
        : Favour.unfavourable;
    final runningFavour = row.runningBalancePaise == 0
        ? null
        : row.runningBalancePaise > 0
        ? Favour.favourable
        : Favour.unfavourable;

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

    final title = Text(
      particulars,
      style: Theme.of(context).textTheme.bodyMedium,
    );
    final note = row.note == null ? null : Text(row.note!);

    final figures = [
      SizedBox(width: grid.debit, child: debit),
      SizedBox(width: grid.credit, child: credit),
      SizedBox(width: grid.balance, child: balance),
    ];

    switch (grid.mode) {
      case _GridMode.columns:
        return ListTile(
          minTileHeight: RkSpace.rowMinHeight,
          onTap: onTap,
          title: title,
          subtitle: note,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: figures),
        );
      case _GridMode.rows:
        // The figures still line up with the heading — they have simply been
        // given the line below the particulars to do it on.
        return ListTile(
          minTileHeight: RkSpace.rowMinHeight,
          onTap: onTap,
          title: title,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ?note,
              const SizedBox(height: RkSpace.s1),
              Row(children: [const Spacer(), ...figures]),
            ],
          ),
        );
      case _GridMode.stacked:
        // No columns, so the heading's words come down into the row: each
        // figure is named beside itself, and wraps under itself where even
        // that will not fit on one line.
        Widget named(String label, Widget value) => Padding(
          padding: const EdgeInsets.only(top: RkSpace.s1),
          child: Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: status.muted),
              ),
              value,
            ],
          ),
        );
        return ListTile(
          minTileHeight: RkSpace.rowMinHeight,
          onTap: onTap,
          title: title,
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ?note,
              if (debit != null) named(l10n.moneySideDr, debit),
              if (credit != null) named(l10n.moneySideCr, credit),
              named(l10n.ledgerStatementColumnBalance, balance),
            ],
          ),
        );
    }
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
