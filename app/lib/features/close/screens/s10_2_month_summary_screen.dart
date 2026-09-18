// S10.2 on its own — the month summary card for a month that already closed
// (07 §13 🔒, 13 §3.2 row S10.2).
//
// The wizard shows the same [MonthSummaryCard] inline the second the lock
// lands, which is where 07 §13 🔒 puts it. This screen is the *second* way in:
// the Home close card, once a book is closed, "gives way to the S10.2 door for
// that month", and a reward nobody can reach again is a receipt after all.
//
// Nothing is recomputed here — the card is a pure function of
// [CloseSource.monthSummary], the same read the wizard makes, so opening it in
// December shows exactly what it showed on the 1st of September.
//
// The three 13 §4.3 states are all here: the ruled skeleton, an error with a
// retry, and the card. There is no empty state: a locked month with no entries
// is a real, honest answer — zero in, zero out — and the card says so.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../close_source.dart';
import '../widgets/month_summary_card.dart';

/// S10.2 — one book's closed month, on its own screen.
class MonthSummaryScreen extends StatefulWidget {
  /// Creates the screen for [bookId]'s [period].
  const MonthSummaryScreen({
    super.key,
    required this.bookId,
    required this.period,
    this.source,
    this.onDone,
  });

  /// The book.
  final String bookId;

  /// The month that closed.
  final YearMonth period;

  /// The ledger door; when null it is read from [CloseScope].
  final CloseSource? source;

  /// Leaves the card. `closeRoutes` passes `context.pop`.
  final VoidCallback? onDone;

  @override
  State<MonthSummaryScreen> createState() => _MonthSummaryScreenState();
}

class _MonthSummaryScreenState extends State<MonthSummaryScreen> {
  CloseSource? _source;
  MonthSummary? _summary;
  Object? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = widget.source ?? CloseScope.maybeOf(context);
    if (source == null) {
      // No scope, no door: the error state, not a thrown red screen
      // (07 §1 rule 6).
      if (_error == null && !_started) {
        setState(() => _error = StateError('no CloseSource in scope'));
      }
      return;
    }
    if (identical(source, _source) && _started) return;
    _source = source;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _error = null;
      _summary = null;
    });
    try {
      final summary = await source.monthSummary(widget.bookId, widget.period);
      if (!mounted) return;
      setState(() => _summary = summary);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  String _month(AppLocalizations l) =>
      '${monthName(l, widget.period.month)} ${widget.period.year}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
        title: RkFitText(l.closeSummaryTitle(_month(l)), maxLines: 1),
      ),
      body: SafeArea(
        child: switch ((summary, _error)) {
          (_, final Object _) => RkErrorState(
            text: l.closeSummaryError,
            retryLabel: l.closeRetry,
            onRetry: _load,
          ),
          (null, _) => RkSkeleton(label: l.closeSummarySkeleton, rows: 4),
          (final MonthSummary s, _) => SingleChildScrollView(
            child: MonthSummaryCard(
              summary: s,
              monthLabel: _month(l),
              onDone: widget.onDone,
            ),
          ),
        },
      ),
    );
  }
}
