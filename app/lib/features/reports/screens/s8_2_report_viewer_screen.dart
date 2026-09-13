// S8.2 Report viewer + export (13 §3.2 row S8.2; 07 §14 🔒; ADR 2026-09-12
// §1 🔒 and ADR 2026-09-12d 🔒), scoped at M5 to the one report 10's M5 row names — *"basic day-book
// export"*. The remaining ten of 07 §14's 🔒 order are M12 (ADR 2026-09-12
// Consequences), and S8.1 keeps them disabled-with-reason until then.
//
// A report is a PROFESSIONAL surface (02 §10 🔒, CLAUDE.md rule 9): true
// ledger **Dr / Cr**, never *Money in / Money out*. The engine's posting never
// bends to the display language — `Vocabulary.professional` only picks words.
//
// The year comes from the switcher ruled by ADR 2026-09-09 §4 🔒 — one control
// on three surfaces, S4 · **S8.2** · S10.4. It is consumed, not re-drawn, from
// `features/ledger/widgets/fy_switcher.dart`: a chip once a year has closed,
// and plain muted text before that, because a control that opens a list of one
// is a lie. No year can have closed before S10.4 lands (M9), so plain text is
// the shipped state and the chip is exercised from a fake.
//
// Export: **View report** is this screen — it opens in-app. **Download/Share**
// is the primary action and sends **PDF** straight to the platform share sheet
// — *the format a person hands to someone else* (ADR 2026-09-12 §1 🔒, default
// restored by ADR 2026-09-12d §2 🔒 after 12c's CSV stopgap lapsed, and the
// *Share* half wired by ADR 2026-09-13 §1 🔒: before that the export ended at a
// temp path no reader could reach). Beside it sits *Choose a format*,
// which opens the three-format sheet — the ruling requires **both** paths and
// lets neither become the only one. See `widgets/export_sheet.dart` for the
// enumeration — all three rows generate since ADR 2026-09-12e §1 🔒 — and
// `export/pdf_report.dart` for why the document embeds its own fonts.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart' hide StatementRow;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../ledger/ledger_book.dart';
import '../../ledger/widgets/fy_switcher.dart';
import '../day_book.dart';
import '../export/csv_report.dart';
import '../export/file_report_sink.dart';
import '../export/pdf_report.dart';
import '../export/report_export.dart';
import '../export/xlsx_report.dart';
import '../widgets/export_sheet.dart';

/// S8.2 — the report viewer, showing the Day Book of one book for one
/// financial year, with two export affordances in its bar: *Download / Share*,
/// which writes the default format (PDF — ADR 2026-09-12d §2 🔒), and *Choose a
/// format*, which opens the sheet (ADR 2026-09-12c §1 🔒, the half 12d keeps).
class ReportViewerScreen extends StatefulWidget {
  /// Creates the screen.
  const ReportViewerScreen({
    super.key,
    this.bookId,
    this.onOpenEntry,
    this.closedYears = noClosedYears,
    this.sink = shareReportFile,
  });

  /// Explicit book; when null the solo book is resolved ([soloBookId]).
  final String? bookId;

  /// Opens S4.1 for a row's entry. Null leaves the rows un-tappable — the
  /// report is still a report, not a dead end.
  final void Function(String entryId)? onOpenEntry;

  /// The certified-years seam (ADR 2026-09-09 §4, [ClosedYearsSource]). The
  /// default reports none — every build before Year Close (M9) — so the year
  /// ships as plain text and no switcher is drawn.
  final ClosedYearsSource closedYears;

  /// Where a generated report goes ([ReportSink]). The app raises the
  /// platform share sheet and names a file only if it cannot (ADR
  /// 2026-09-13 §1 🔒); a test injects a fake and reads the bytes.
  final ReportSink sink;

  @override
  State<ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends State<ReportViewerScreen> {
  String? _bookId;
  String _bookName = '';
  Object? _resolveError;
  bool _resolveStarted = false;

  int _fyStartMonth = 4;
  List<ClosedYear> _closed = const [];
  FinancialYear? _fy;

  /// Memoised so a rebuild does not resubscribe the drift stream every frame.
  Stream<DayBook>? _stream;
  String? _streamKey;

  /// The latest day book and chart, kept so the export action can run without
  /// re-reading the ledger.
  DayBook? _book;
  Chart? _chart;

  Stream<DayBook> _dayBookStream(
    LocalLedger ledger,
    String bookId,
    FinancialYear fy,
  ) {
    final key = '$bookId|${fy.label}|${fy.startMonth}';
    if (_streamKey != key) {
      _streamKey = key;
      _stream = watchDayBook(ledger, bookId, from: fy.firstDay, to: fy.lastDay);
    }
    return _stream!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope is an InheritedWidget, so it may only be read from here — not
    // initState(), where a caught throw would pin the screen to its error
    // state forever (the defect S3 carried).
    if (_resolveStarted) return;
    _resolveStarted = true;
    _resolveBook();
  }

  Future<void> _resolveBook() async {
    final ledger = LedgerScope.of(context);
    try {
      final id = widget.bookId ?? await soloBookId(ledger);
      // A plain future, never `watchBooks().first`: a drift query stream's
      // first event arrives on a zero-duration timer, which a bare `await`
      // inside a widget test's fake-async zone never lets fire — the screen
      // would sit on its skeleton forever under test and only work in the app.
      final heading = await reportHeading(ledger, id);
      final closed = await widget.closedYears(id, '');
      if (!mounted) return;
      setState(() {
        _bookId = id;
        _bookName = heading.bookName;
        _fyStartMonth = heading.fyStartMonth;
        _closed = closed;
        _fy = FinancialYear.of(
          ledger.today(),
          startMonth: heading.fyStartMonth,
        );
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
    _book = null;
  });

  /// Builds the report in [format].
  ///
  /// All three formats generate at M5: PDF and CSV since ADR 2026-09-12d §3
  /// 🔒, and XLSX since ADR 2026-09-12e §1 🔒 unblocked it — the sheet has no
  /// disabled row left.
  ///
  /// Everything that needs the tree — strings, locale — is read **before** the
  /// first await: loading the PDF's fonts is asynchronous, and a context read
  /// after an await is a disposed context away from a crash.
  Future<ReportFile> _buildFile(ReportFormat format) async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final chart = _chart;
    final book = _book ?? DayBook.empty(_bookId ?? '');
    final fy = _fy!;
    String named(String id) => chart?.maybeAccount(id)?.name ?? id;
    String date(LocalDate d) => formatLedgerDate(d, strings: l10n);
    final labels = ReportLabels.dayBook(l10n);
    final period = l10n.ledgerStatementFy(fy.label);
    final fileName = l10n.reportsExportFileName(fy.label, format.extension);

    switch (format) {
      case ReportFormat.pdf:
        // The faces are loaded per export, not held: package:pdf embeds the
        // glyphs it draws, and Helvetica — its default — has no Gurmukhi and
        // no Devanagari (see `export/pdf_report.dart`).
        final fonts = await ReportFonts.load();
        return dayBookPdfFile(
          book,
          accountName: named,
          labels: labels,
          bookName: _bookName,
          period: period,
          formatDate: date,
          pageNumber: (page, pages) => l10n.reportsExportPage(page, pages),
          fonts: fonts,
          locale: locale,
          fileName: fileName,
        );
      case ReportFormat.csv:
        return dayBookCsvFile(
          book,
          accountName: named,
          labels: labels,
          bookName: _bookName,
          period: period,
          formatDate: date,
          fileName: fileName,
        );
      case ReportFormat.xlsx:
        // Written in-house over archive + xml (ADR 2026-09-12e §1 🔒). No
        // await: the sheet is built from data already in hand, unlike the
        // PDF's font load.
        return dayBookXlsxFile(
          book,
          accountName: named,
          labels: labels,
          bookName: _bookName,
          period: period,
          fileName: fileName,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reportsDayBookRowTitle),
        // Two affordances, never one (ADR 2026-09-12c §1 🔒): the default
        // that writes, and the door to the choice. See [_ExportAction] for
        // how the pair survives 200% text scale on a 360 px phone.
        actions: [
          _ExportAction(onPressed: _exportDefault),
          _ChooseFormatAction(onPressed: _openExportSheet),
        ],
      ),
      body: SafeArea(
        child: _resolveError != null
            ? _ErrorState(text: l10n.reportsViewerError, onRetry: _retry)
            : _bookId == null || _fy == null
            ? _Skeleton(label: l10n.reportsViewerSkeleton)
            : _body(context, _bookId!),
      ),
    );
  }

  void _openExportSheet() {
    showReportExportSheet(context, buildFile: _buildFile, sink: widget.sink);
  }

  /// The primary action: write the default format and say where it went, with
  /// no sheet in between. The default is **PDF** — the format a person hands
  /// to someone else (ADR 2026-09-12 §1 🔒, ADR 2026-09-12d §2 🔒).
  void _exportDefault() {
    unawaited(
      runReportExport(
        l10n: AppLocalizations.of(context),
        messenger: ScaffoldMessenger.of(context),
        format: ReportFormat.pdf,
        buildFile: _buildFile,
        sink: widget.sink,
      ),
    );
  }

  Widget _body(BuildContext context, String bookId) {
    final ledger = LedgerScope.of(context);
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Chart>(
      future: ledger.chartOf(bookId),
      builder: (context, chartSnap) {
        if (chartSnap.hasError) {
          return _ErrorState(
            text: l10n.reportsViewerError,
            onRetry: () => setState(() {}),
          );
        }
        final chart = chartSnap.data;
        if (chart == null) {
          return _Skeleton(label: l10n.reportsViewerSkeleton);
        }
        _chart = chart;
        return StreamBuilder<DayBook>(
          stream: _dayBookStream(ledger, bookId, _fy!),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorState(
                text: l10n.reportsViewerError,
                onRetry: () => setState(() {}),
              );
            }
            final book = snap.data;
            if (book == null) {
              return _Skeleton(label: l10n.reportsViewerSkeleton);
            }
            _book = book;
            return _report(context, chart, book);
          },
        );
      },
    );
  }

  Widget _report(BuildContext context, Chart chart, DayBook book) {
    final l10n = AppLocalizations.of(context);
    final ledger = LedgerScope.of(context);
    final today = ledger.today();
    final fy = _fy!;

    // The switcher sits above everything and stays on every state: an empty
    // year must not be a year you cannot switch out of (07 §1 rule 2).
    final switcher = FySwitcher(
      selected: fy,
      closedYears: _closed,
      openYear: FinancialYear.of(today, startMonth: _fyStartMonth),
      onSelected: _selectYear,
    );

    if (book.isEmpty) {
      return ListView(
        children: [
          switcher,
          Padding(
            padding: const EdgeInsets.all(RkSpace.gutter),
            child: Text(
              l10n.reportsViewerEmpty,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }

    final order = <LocalDate>[];
    final groups = <LocalDate, List<DayBookRow>>{};
    for (final row in book.rows) {
      if (!groups.containsKey(row.date)) {
        groups[row.date] = [];
        order.add(row.date);
      }
      groups[row.date]!.add(row);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s8),
      children: [
        switcher,
        _Takeaway(book: book),
        _CrossCheck(balances: book.balances),
        _ColumnHeader(l10n: l10n),
        for (final date in order) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              RkSpace.s1,
            ),
            child: Text(
              formatLedgerDate(date, strings: l10n),
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: RkStatusColors.of(context).muted),
            ),
          ),
          for (final row in groups[date]!)
            _EntryBlock(
              row: row,
              accountName: (id) => chart.maybeAccount(id)?.name ?? id,
              onTap: widget.onOpenEntry == null
                  ? null
                  : () => widget.onOpenEntry!(row.entryId),
            ),
        ],
        const Divider(height: RkSpace.s6),
        _TotalsRow(book: book),
      ],
    );
  }
}

/// Share of the bar the labelled primary action may occupy before its words
/// are clipped. The pair is this plus one 48 px icon button, so the title
/// keeps a little over a third of the line at every width and in every
/// language. A fraction, not a token: this is the report bar's own budget,
/// and the two actions only have to agree with each other.
const double _labelledActionShare = 0.5;

/// The primary action (ADR 2026-09-12 §1 🔒, default restored by 12d §2 🔒) —
/// it writes the PDF, it does not open a sheet. Labelled in words at normal scale;
/// past 1.3x the words would push the title off the bar, so it becomes an
/// icon that still carries the same label to a screen reader and a tooltip
/// (07 §1 rules 3 and 11).
///
/// 12c puts a **second** affordance beside it ([_ChooseFormatAction]), and the
/// bar has to hold both at 200% on a 360 px phone in all three languages. Two
/// things make that true, and the second was a live defect before 12c:
///
///  1. **Only this action is ever labelled.** Above 1.3x the pair is two
///     [IconButton]s, 48 logical px each and independent of text scale, and
///     the [AppBar] title ellipsises rather than fighting them for the line.
///     Giving the chooser a label too would break that, which is why it has
///     none.
///  2. **The labelled form is capped and clips.** A scale threshold alone was
///     never enough: at 1.3x the Punjabi label alone overflowed a 360 px bar,
///     and no test caught it because only 200% — where the label is already
///     gone — was being asserted. A threshold cannot know how wide a word is
///     in a font it has not measured, so the words are held to
///     [_labelledActionShare] of the bar and clipped past it. The cap never
///     bites at the real label widths; it is the guarantee that a longer
///     translation, or a wider fallback font, cannot spill the bar.
class _ExportAction extends StatelessWidget {
  const _ExportAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
      return IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.ios_share),
        tooltip: l10n.reportsViewerExport,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: RkSpace.s2),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * _labelledActionShare,
        ),
        // Hand-built rather than `TextButton.icon`, so the label is the piece
        // that gives when the cap bites — and it keeps the tooltip, so the
        // full words reach a screen reader and a long-press even clipped.
        child: Tooltip(
          message: l10n.reportsViewerExport,
          child: TextButton(
            onPressed: onPressed,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.ios_share),
                const SizedBox(width: RkSpace.s1),
                Flexible(
                  child: Text(
                    l10n.reportsViewerExport,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The door to the format sheet (ADR 2026-09-12c §1 🔒: *"the format sheet
/// stays reachable from the viewer so a person can still choose a format
/// rather than accept the default"*). Without it the CSV default would be the
/// only path and PDF would vanish from the product — the enumeration is 🔒,
/// and a format you cannot even see named is a dead end (07 §1 rules 2 and 6).
///
/// Icon-only at every text scale, deliberately: see [_ExportAction]. The
/// string rides as tooltip and screen-reader label, so the affordance is never
/// carried by the glyph alone (07 §1 rule 3).
class _ChooseFormatAction extends StatelessWidget {
  const _ChooseFormatAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.more_horiz),
      tooltip: l10n.reportsViewerExportFormats,
    );
  }
}

/// 07 §14's *one-line takeaway header*, in professional words: how many
/// entries, and the two column totals.
class _Takeaway extends StatelessWidget {
  const _Takeaway({required this.book});

  final DayBook book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    // A Wrap, not a Row: at 200% the three pieces cannot share a 360 px line,
    // and a takeaway that overflows is worse than one that folds (07 §1
    // rule 11).
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Wrap(
        spacing: RkSpace.s3,
        runSpacing: RkSpace.s1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.reportsViewerEntriesCount(book.rows.length),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: status.muted),
          ),
          MoneyText(
            book.debitTotalPaise,
            vocabulary: Vocabulary.professional,
            showDirection: true,
          ),
          MoneyText(
            // The Cr total is a credit figure, so it reaches [MoneyText] with
            // the engine's own sign — the widget tags the side, it is not told
            // which word to print (02 §10 🔒).
            -book.creditTotalPaise,
            vocabulary: Vocabulary.professional,
            showDirection: true,
          ),
        ],
      ),
    );
  }
}

/// The cross-check (13 §5, flow F3 — *cross-check footer*): every entry
/// balances (02 §1.4), so the two columns must agree. Words beside an icon,
/// never colour alone (07 §1 rule 3).
class _CrossCheck extends StatelessWidget {
  const _CrossCheck({required this.balances});

  final bool balances;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final tint = balances ? status.success : status.danger;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            balances
                ? Icons.check_circle_outline
                : Icons.warning_amber_outlined,
            size: RkSpace.s4,
            color: tint,
          ),
          const SizedBox(width: RkSpace.s1),
          Expanded(
            child: Text(
              balances
                  ? l10n.reportsViewerCrosscheckOk
                  : l10n.reportsViewerCrosscheckMismatch,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Width of a Dr or Cr figure column at 100% text scale — the report's own
/// grid, not a design token: the two columns only have to agree with each
/// other and with [_ColumnHeader].
const double _amountColumn = 88;

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(color: status.muted);
    final scaler = MediaQuery.textScalerOf(context);
    final width = scaler.scale(_amountColumn);

    Widget figure(String label, TextAlign align) => Semantics(
      header: true,
      child: Text(label, textAlign: align, style: style),
    );

    // The heading folds on the same rule its rows do, and for a stronger
    // reason: *Particulars* is a single word in English, so it cannot wrap —
    // when the line is too narrow it is silently **cut**, and a column whose
    // name reads "Particula" is a column the reader has to guess at (07 §1
    // rules 2 and 11). The width it needs is measured, never guessed from a
    // scale threshold: the word, the font and the locale all decide it, and a
    // threshold knows none of the three. Above 200% on a 360 px phone even the
    // whole line is too short for it, and only there does it ellipsise.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final particulars = l10n.reportsViewerColumnParticulars;
          final needed = (TextPainter(
            text: TextSpan(text: particulars, style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
            maxLines: 1,
          )..layout()).width;
          final fits = needed + width * 2 <= constraints.maxWidth;
          final label = Semantics(
            header: true,
            child: Text(
              particulars,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
          if (fits) {
            // The two figure columns are the **same** fixed, scaled width the
            // rows use, so the headings sit over their own numbers instead of
            // over a share of the line.
            return Row(
              children: [
                Expanded(child: label),
                SizedBox(
                  width: width,
                  child: figure(l10n.moneySideDr, TextAlign.right),
                ),
                SizedBox(
                  width: width,
                  child: figure(l10n.moneySideCr, TextAlign.right),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              label,
              const SizedBox(height: RkSpace.s1),
              // Folded, the rows put a Dr figure at the start of the line and
              // a Cr figure at the end ([_LineRow]); the headings follow them.
              Row(
                children: [
                  Expanded(child: figure(l10n.moneySideDr, TextAlign.start)),
                  figure(l10n.moneySideCr, TextAlign.end),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One entry: its Dr lines, then its Cr lines, then its note. Tapping it opens
/// S4.1 — a report row is a door to the entry behind it (07 §1 rule 8).
class _EntryBlock extends StatelessWidget {
  const _EntryBlock({required this.row, required this.accountName, this.onTap});

  final DayBookRow row;
  final String Function(String accountId) accountName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final lines = [...row.debits, ...row.credits];
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s2,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: status.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in lines)
              _LineRow(name: accountName(line.accountId), line: line),
            if (row.note != null)
              Padding(
                padding: const EdgeInsets.only(top: RkSpace.s1),
                child: Text(
                  row.note!,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: status.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.name, required this.line});

  final String name;
  final DayBookLine line;

  @override
  Widget build(BuildContext context) {
    // The two figure columns are sized in text, not pixels: at 200% a fixed
    // 88 px cannot hold a scaled figure on a 360 px phone (07 §1 rule 11).
    // Scaled, they either still fit — and stay aligned down the page, which is
    // the whole point of a classical column — or the line folds and the
    // figures take a row of their own.
    final scaler = MediaQuery.textScalerOf(context);
    final width = scaler.scale(_amountColumn);

    final figure = MoneyText(
      // The line reaches [MoneyText] with the engine's own sign; the widget
      // picks Dr or Cr from it (02 §10 🔒). The column it lands in is chosen
      // here, from the same sign.
      line.amountPaise,
      vocabulary: Vocabulary.professional,
      showPaise: true,
      textAlign: TextAlign.right,
    );
    final particulars = Text(
      name,
      style: Theme.of(context).textTheme.bodyMedium,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Leave the particulars at least a third of the line before folding.
          final fits = width * 2 <= constraints.maxWidth * 2 / 3;
          if (fits) {
            return Row(
              children: [
                Expanded(child: particulars),
                SizedBox(
                  width: width,
                  child: line.isDebit ? figure : const SizedBox.shrink(),
                ),
                SizedBox(
                  width: width,
                  child: line.isCredit ? figure : const SizedBox.shrink(),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              particulars,
              const SizedBox(height: RkSpace.s1),
              Align(
                alignment: line.isDebit
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
                child: figure,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The totalled columns at the foot — the figures the cross-check compares.
class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.book});

  final DayBook book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final width = scaler.scale(_amountColumn);
    final label = Text(
      l10n.reportsViewerTotal,
      style: Theme.of(context).textTheme.labelLarge,
    );
    final debit = MoneyText(
      book.debitTotalPaise,
      vocabulary: Vocabulary.professional,
      showPaise: true,
      textAlign: TextAlign.right,
    );
    final credit = MoneyText(
      -book.creditTotalPaise,
      vocabulary: Vocabulary.professional,
      showPaise: true,
      textAlign: TextAlign.right,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (width * 2 <= constraints.maxWidth * 2 / 3) {
            return Row(
              children: [
                Expanded(child: label),
                SizedBox(width: width, child: debit),
                SizedBox(width: width, child: credit),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              label,
              const SizedBox(height: RkSpace.s1),
              debit,
              credit,
            ],
          );
        },
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

/// The ruled skeleton (11 §4.5): true row pitch, no shimmer, no spinner.
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
