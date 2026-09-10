// S1 Home / Position (07 §4 🔒, 13 §3.2 row S1): the hero *Total money you
// have*, the books-balanced verification card, the position card (02 §9
// exactly, every line drilling into S1.1), the *This month In/Out* line, the
// four verb buttons, and today's entries newest first.
//
// Home is a CONSUMER surface (02 §10 🔒, CLAUDE.md rule 9): *Money in / Money
// out*, plain words, never Dr/Cr — those live on the A/C statement and the
// trial balance the verification card links to. Every figure is signed
// integer paise; nothing here re-implements a posting rule.
//
// The four states of 13 §4.3 are all here: loading (the ruled skeleton of
// 11 §4.5 — never a spinner), empty (the position card collapses to the S0.7
// setup checklist, 07 §4), error-with-retry, populated. Offline is not an
// error (07 §1 rule 7) and is not drawn here — the shell owns that chip.
//
// Not yet wired, and deliberately not invented here:
//   • S1.2/S1.3 scope chip — a later lane; the solo book is resolved instead.
//   • S1.4 rebuilding card — [rebuildingSlot] is the hole it drops into
//     (07 §28, ADR 2026-09-05c §3/§6, F1-07-38).
//   • S8.2 trial balance and the full day book have no route yet, so those
//     two actions render only when a caller supplies them.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../ledger/ledger_book.dart';
import '../home_data.dart';
import '../home_paths.dart';
import '../widgets/home_cards.dart';
import '../widgets/home_states.dart';

/// S1 Home — the Home tab's root screen (07 §4).
class HomeScreen extends StatefulWidget {
  /// Creates the screen.
  const HomeScreen({
    super.key,
    this.bookId,
    this.onOpenPosition,
    this.onOpenAccount,
    this.onVerb,
    this.onOpenEntry,
    this.onOpenDayBook,
    this.onOpenTrialBalance,
    this.onSetupStep,
    this.rebuildingSlot,
  });

  /// Explicit book; when null the solo book is resolved ([soloBookId]).
  final String? bookId;

  /// Drills a position line into its list (S1.1).
  final void Function(PositionLine line)? onOpenPosition;

  /// Opens one account's statement (S4).
  final void Function(String accountId)? onOpenAccount;

  /// Opens the S2 entry flow with the verb pre-chosen (07 §5).
  final void Function(EntryKind kind)? onVerb;

  /// Opens an entry's detail (S4.1) — the audit trail and amend/reverse.
  final void Function(String entryId)? onOpenEntry;

  /// Opens the whole day book (07 §4 *▸ full day book*).
  final VoidCallback? onOpenDayBook;

  /// Opens the S8.2 trial balance from the verification card.
  final VoidCallback? onOpenTrialBalance;

  /// Opens setup checklist step `index` (S0.7).
  final void Function(int index)? onSetupStep;

  /// S1.4 *Book incomplete — rebuilding* replaces the verification card while
  /// a book rebuilds (07 §4 🔒). A later lane fills it (F1-07-38).
  final Widget? rebuildingSlot;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _bookId;
  Object? _resolveError;
  bool _resolveStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // LedgerScope is an InheritedWidget, so it may only be read from here on;
    // reading it in initState() throws, and the caught throw would pin the
    // screen to its error state forever (the S3 lane hit exactly this).
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
      _resolveStarted = true;
    });
    _resolveBook();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.homeTitle)),
      body: SafeArea(
        child: _resolveError != null
            ? HomeErrorState(
                text: l10n.homeError,
                retryLabel: l10n.homeRetry,
                onRetry: _retry,
              )
            : _bookId == null
            ? HomeSkeleton(label: l10n.homeSkeleton)
            : _body(context, _bookId!),
      ),
    );
  }

  Widget _body(BuildContext context, String bookId) {
    final l10n = AppLocalizations.of(context);
    final ledger = LedgerScope.of(context);
    final today = ledger.today();
    return StreamBuilder<HomeSnapshot>(
      stream: watchHome(
        ledger,
        bookId,
        today: today,
        month: YearMonth(today.year, today.month),
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return HomeErrorState(
            text: l10n.homeError,
            retryLabel: l10n.homeRetry,
            onRetry: () => setState(() {}),
          );
        }
        final data = snap.data;
        if (data == null) return HomeSkeleton(label: l10n.homeSkeleton);
        return _HomeBody(
          snapshot: data,
          onOpenPosition: widget.onOpenPosition,
          onOpenAccount: widget.onOpenAccount,
          onVerb: widget.onVerb,
          onOpenEntry: widget.onOpenEntry,
          onOpenDayBook: widget.onOpenDayBook,
          onOpenTrialBalance: widget.onOpenTrialBalance,
          onSetupStep: widget.onSetupStep,
          rebuildingSlot: widget.rebuildingSlot,
        );
      },
    );
  }
}

/// The loaded surface — a pure function of the snapshot, so a test (and the
/// 200% / 360×800 layout check) can pump it without a database.
class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.snapshot,
    this.onOpenPosition,
    this.onOpenAccount,
    this.onVerb,
    this.onOpenEntry,
    this.onOpenDayBook,
    this.onOpenTrialBalance,
    this.onSetupStep,
    this.rebuildingSlot,
  });

  final HomeSnapshot snapshot;
  final void Function(PositionLine line)? onOpenPosition;
  final void Function(String accountId)? onOpenAccount;
  final void Function(EntryKind kind)? onVerb;
  final void Function(String entryId)? onOpenEntry;
  final VoidCallback? onOpenDayBook;
  final VoidCallback? onOpenTrialBalance;
  final void Function(int index)? onSetupStep;
  final Widget? rebuildingSlot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final chart = snapshot.accountsById;
    final moneyAccounts = [
      for (final a in snapshot.accounts)
        if (a.account.accountClass == AccountClass.money && !a.archived) a,
    ];

    // ⚠️ SPEC: 07 §4 says the position card collapses to the setup checklist
    // for a "new user" but never defines the test. The conservative reading
    // is taken here — a book with no entries at all — so a book that already
    // carries postings never loses its position card.
    final firstRun = snapshot.entryCount == 0;

    final review = [
      for (final r in snapshot.today)
        if (r.underReview) r,
    ];
    final reviewPaise = review.fold<int>(
      0,
      (s, r) => s + (HomeTodayRow.amountLine(r, chart)?.amountPaise.abs() ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s10),
      children: [
        HomeHero(
          totalPaise: snapshot.position.totalMoneyPaise,
          accounts: moneyAccounts,
          onOpenAccount: onOpenAccount,
        ),
        rebuildingSlot ??
            HomeVerificationCard(
              balanced: snapshot.booksBalanced,
              differencePaise: snapshot.differencePaise,
              onOpenTrialBalance: onOpenTrialBalance,
            ),
        if (firstRun)
          HomeSetupChecklist(
            // With no entries in the book neither step can be done; the
            // completion sources for steps 3 and 4 are the widget's own
            // ⚠️ SPEC note (S11.4, S13).
            openingBalancesDone: false,
            firstEntryDone: false,
            onStep: onSetupStep,
          )
        else
          HomePositionCard(
            snapshot: snapshot,
            onOpenPosition: onOpenPosition,
            onOpenAccount: onOpenAccount,
          ),
        HomeMonthLine(
          inPaise: snapshot.monthInPaise,
          outPaise: snapshot.monthOutPaise,
        ),
        HomeVerbButtons(onVerb: onVerb),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s3,
            RkSpace.gutter,
            0,
          ),
          // A Wrap, not a Row: *Today* plus *Full day book* in Gurmukhi at
          // 200% does not fit one line on a 360 px phone (07 §1 rule 11).
          child: Wrap(
            spacing: RkSpace.s3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.homeTodayTitle,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: status.muted),
                ),
              ),
              if (onOpenDayBook != null)
                TextButton(
                  onPressed: onOpenDayBook,
                  child: Text(l10n.homeTodayFullDayBook),
                ),
            ],
          ),
        ),
        // 07 §4: one summary chip per book view is the single place the
        // review status is written out; the rows themselves carry only the
        // small amber clock. Under review never changes a balance (02 §3).
        if (review.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RkSpace.gutter,
              vertical: RkSpace.s2,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ActionChip(
                avatar: Icon(Icons.schedule, size: 16, color: status.pending),
                label: Text(
                  l10n.homeTodayReviewChip(
                    review.length,
                    formatPaise(
                      reviewPaise,
                      locale: Localizations.localeOf(context),
                    ),
                  ),
                ),
                onPressed: onOpenDayBook,
              ),
            ),
          ),
        if (snapshot.today.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s2,
              RkSpace.gutter,
              RkSpace.s2,
            ),
            child: Text(
              l10n.homeTodayEmpty,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: status.muted),
            ),
          )
        else
          for (final row in snapshot.today)
            HomeTodayRow(
              row: row,
              accountsById: chart,
              onTap: onOpenEntry == null
                  ? null
                  : () => onOpenEntry!(row.entryId),
            ),
      ],
    );
  }
}
