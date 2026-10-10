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
// Scope (13 §2.2 🔒) is held by a [HomeScopeController]: with one book there
// is no control at all, with exactly two the S1.2 inline toggle sits in the
// top bar, with three or more the S1.3 grouped sheet opens from it (07 §5.7
// 🔒). Switching never leaves the screen — only this body re-renders. In
// *Everything* the body is one read-only card per book.
//
// S1.4 (07 §28 🔒) replaces that body while the book's projections rebuild:
// [rebuildProgress] is the seam, [HomeRebuildGate] decides, and the return to
// the normal card is gated on `integrity_ok` (ADR 2026-09-05c §3/§6).
//
// Not yet wired, and deliberately not invented here:
//   • The full day book has no route here yet, so that action renders only
//     when a caller supplies it. The trial-balance door is wired by
//     `home_routes.dart` (desk 193 (c)), to S8.1 until the S8.2 trial balance
//     exists (⚠️ SPEC there).
import 'dart:async';
import 'dart:math' as math;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_settings.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../close/close_paths.dart';
import '../../close/close_source.dart';
import '../../ledger/ledger_book.dart';
import '../../onboarding/opening_setup_record.dart';
import '../../onboarding/personal_book.dart';
import '../../onboarding/screens/s0_3_purpose_screen.dart'
    show OnboardingPurpose;
import '../../onboarding/setup_progress.dart';
import '../home_data.dart';
import '../home_paths.dart';
import '../home_rebuild.dart';
import '../home_scope.dart';
import '../widgets/home_cards.dart';
import '../widgets/home_close_card.dart';
import '../widgets/home_everything.dart';
import '../widgets/home_rebuild_gate.dart';
import '../widgets/home_scope_switcher.dart';
import '../widgets/home_verb_gate.dart';
import '../../../shared/widgets/rk_states.dart';
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
    this.onOpenReconciliation,
    this.onSetupStep,
    this.setupDoors = const {...SetupStep.values},
    this.rebuildingSlot,
    this.scopeController,
    this.rebuildProgress,
    this.closeSource,
    this.onOpenClose,
    this.onOpenSearch,
  });

  /// Explicit book; when null the solo book is resolved ([soloBookId]) and
  /// the scope controller takes over as soon as a second book exists.
  final String? bookId;

  /// Drills a position line into its list (S1.1) over the book in scope.
  final void Function(PositionLine line, String bookId)? onOpenPosition;

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

  /// Opens S8.3 Family reconciliation from the position card's *In transit*
  /// label (07 §10 🔒).
  final VoidCallback? onOpenReconciliation;

  /// Opens a setup checklist row (S0.7).
  final void Function(SetupStep step)? onSetupStep;

  /// The checklist rows [onSetupStep] has a destination for; the others are
  /// drawn as information only (07 §1 rule 6 — never a tap to nowhere).
  final Set<SetupStep> setupDoors;

  /// A caller-supplied card in place of the verification card. Kept for the
  /// shell; S1.4 itself now comes from [rebuildProgress] and replaces the
  /// whole body, because the book may not be shown as whole while it rebuilds
  /// (07 §28 🔒).
  final Widget? rebuildingSlot;

  /// Scope selection (13 §2.2). When null S1 owns one for its own lifetime;
  /// the shell passes one in once it persists scope per tab.
  final HomeScopeController? scopeController;

  /// The S1.4 progress seam (07 §28, [RebuildProgressSource]). When null no
  /// rebuild can be reported and the normal body always shows.
  final RebuildProgressSource? rebuildProgress;

  /// The close seam behind the *Close card* (07 §13 🔒 bullet 1). When null it
  /// is read from [CloseScope]; with neither, no card is drawn and Home is
  /// otherwise untouched — a close card is an invitation, never a dependency.
  final CloseSource? closeSource;

  /// Opens a close path — S10 for a month still open, S10.2 for one that has
  /// closed. The future completes when the closer comes back, which is when
  /// the card re-reads its state: a month closed in the wizard must not still
  /// read *Close Aug 2026* on return.
  final Future<void> Function(String path)? onOpenClose;

  /// Opens S21 Search (07 §25 🔒 ⟦tests: F1-07-35⟧; 13 §3.2: reached from
  /// S3 and S1) over the book in scope — the id S1 is showing, never the
  /// mirror's first book. When null no search button is drawn; nor is one in
  /// *Everything*, which is no single book.
  final void Function(String bookId)? onOpenSearch;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// The pinned verb bar, measured so the *Not needed* toast floats above
  /// its buttons (canvas 1 O8f), never over them.
  final GlobalKey _verbBarKey = GlobalKey();
  String? _bookId;
  Object? _resolveError;
  bool _resolveStarted = false;
  late final HomeScopeController _scope =
      widget.scopeController ?? HomeScopeController();
  StreamSubscription<List<BookRef>>? _booksSub;
  // The S1.4 streams, memoised per book: a stream rebuilt on every frame
  // would make [HomeRebuildGate] resubscribe forever.
  String? _gateBook;
  Stream<RebuildProgress?>? _progressStream;
  Stream<bool>? _integrityStream;
  // The Close card's input (07 §13 🔒). Empty until the seam answers, and
  // empty for ever when there is no seam — Home draws no card and loses
  // nothing else.
  List<BookCloseStatus> _closeStatuses = const [];
  // S0.6's *Finish* (desk 172): ticks the checklist's *Opening balances* row
  // even when every figure was ₹0 and nothing was posted. Per book — the
  // record of the book in scope, never an install-wide bit (P1A review,
  // finding 6): S0.6 fills the personal book only.
  String? _recordBook;
  bool _openingRecorded = false;

  // The personal book — the only one S0.6 fills, so the only one whose
  // *Opening balances* row may open it (P1A review, finding 6).
  String? _personalBookId;

  // ADR 2026-10-07 ruling 3 — what sign-up left for the checklist, read from
  // the device so the rows survive a cold start: the purpose card, the
  // skipped invite step, and whether the recovery sheet was scanned back.
  OnboardingPurpose? _purpose;
  SetupBranch? _branch;
  bool _sheetVerified = false;

  Future<void> _readSetup() async {
    final prefs = AppSettingsScope.read(context)?.prefs;
    final purpose = await SetupProgress.purpose(prefs);
    final branch = await SetupProgress.branch(prefs);
    final verified = await SetupProgress.recoverySheetVerified(prefs);
    if (!mounted) return;
    if (purpose != _purpose ||
        branch != _branch ||
        verified != _sheetVerified) {
      setState(() {
        _purpose = purpose;
        _branch = branch;
        _sheetVerified = verified;
      });
    }
  }

  void _onSetupChange() => unawaited(_readSetup());

  /// The *Finish …* row (ruling 3), or null: no skipped invite step, a
  /// purpose without one, or ⋮ → *Not needed*.
  SetupBranchRow? _branchRow() {
    final branch = _branch;
    if (branch == null || branch.state == SetupBranchState.notNeeded) {
      return null;
    }
    final step = switch (branch.purpose) {
      OnboardingPurpose.family => SetupStep.finishFamily,
      OnboardingPurpose.trust => SetupStep.finishTrust,
      _ => null,
    };
    if (step == null) return null;
    final books = _scope.books;
    // The book the record names; before S0.6f / S0.6i recorded it, the one
    // book of the branch's kind (a chain that skipped invites always makes
    // exactly one — ADR 2026-10-07 ruling 1 makes S0.6f / S0.6i required).
    final group = step == SetupStep.finishFamily
        ? HomeScopeGroup.family
        : HomeScopeGroup.organizations;
    final named =
        books.where((b) => b.id == branch.bookId).firstOrNull ??
        (branch.bookId == null
            ? books.where((b) => b.group == group).singleOrNull
            : null);
    return SetupBranchRow(
      step: step,
      done: branch.state == SetupBranchState.done,
      bookName: named?.name,
    );
  }

  /// ⋮ → *Not needed* (ruling 3): hides the row, deletes nothing, and offers
  /// Undo in a toast — no confirm dialog. Menu stays the way in.
  Future<void> _notNeeded(SetupStep step) async {
    final prefs = AppSettingsScope.read(context)?.prefs;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final before = _branch;
    if (before != null) {
      setState(
        () => _branch = before.copyWith(state: SetupBranchState.notNeeded),
      );
    }
    await SetupProgress.setBranchState(prefs, SetupBranchState.notNeeded);
    // Canvas 1 O8f: the toast's bottom edge meets the verb buttons' top — it
    // overlaps only the bar's top padding, so all four verbs stay in reach
    // (07 §1 rules 1–2 🔒; SETUP174 review, finding 2). Measured after the
    // await, when the bar is laid out.
    final bar = _verbBarKey.currentContext?.findRenderObject();
    final lift = bar is RenderBox && bar.hasSize
        ? math.max(0.0, bar.size.height - RkSpace.s3)
        : 0.0;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // Canvas 1 O8f: a floating paper card with ink words and the
          // primary *Undo*, not the theme's dark bar.
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            RkSpace.s3,
            RkSpace.s1,
            RkSpace.s3,
            RkSpace.s2 + lift,
          ),
          // 13 §4.2 *the 10 s Undo*; then it leaves on its own. An action
          // would otherwise keep it up until tapped (Flutter ≥ 3.29 persists
          // a SnackBar with an action by default) — over the verbs, and with
          // Undo as the only way out.
          duration: const Duration(seconds: 10),
          persist: false,
          backgroundColor: scheme.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(RkRadius.lg),
            side: BorderSide(color: status.hairline),
          ),
          content: Text(
            step == SetupStep.finishTrust
                ? l10n.homeSetupNotNeededTrustToast
                : l10n.homeSetupNotNeededFamilyToast,
            style: text.bodyLarge,
          ),
          action: SnackBarAction(
            textColor: scheme.primary,
            label: l10n.homeSetupUndo,
            onPressed: () {
              if (mounted && before != null) {
                setState(
                  () => _branch = before.copyWith(state: SetupBranchState.open),
                );
              }
              unawaited(
                SetupProgress.setBranchState(prefs, SetupBranchState.open),
              );
            },
          ),
        ),
      );
  }

  void _watchRecordOf(String bookId) {
    if (_recordBook == bookId) return;
    _recordBook = bookId;
    _openingRecorded = false;
    unawaited(_readOpeningRecord(bookId));
  }

  Future<void> _readOpeningRecord(String bookId) async {
    final recorded = await OpeningSetupRecord.isFinished(
      AppSettingsScope.read(context)?.prefs,
      bookId,
    );
    if (mounted && _recordBook == bookId && recorded != _openingRecorded) {
      setState(() => _openingRecorded = recorded);
    }
  }

  void _onOpeningRecord() {
    if (_recordBook case final bookId?) unawaited(_readOpeningRecord(bookId));
  }

  Future<void> _resolvePersonal() async {
    try {
      final id = await personalBookIdOf(LedgerScope.of(context));
      if (mounted && id != _personalBookId) {
        setState(() => _personalBookId = id);
      }
    } on Object {
      // Unreadable: the row stays information, never a door to the wrong
      // book (07 §1 rule 6).
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // LedgerScope is an InheritedWidget, so it may only be read from here on;
    // reading it in initState() throws, and the caught throw would pin the
    // screen to its error state forever (the S3 lane hit exactly this).
    if (_resolveStarted) return;
    _resolveStarted = true;
    _scope.addListener(_onScope);
    _booksSub = watchBookRefs(LedgerScope.of(context)).listen(
      (books) {
        _scope.setBooks(books);
        unawaited(_resolvePersonal());
      },
      // A book list that cannot be read is not a reason to lose Home: the
      // switcher simply stays hidden (07 §1 rule 12, no dead ends).
      onError: (Object _) {},
    );
    _resolveBook();
    unawaited(_loadClose());
    OpeningSetupRecord.changes.addListener(_onOpeningRecord);
    SetupProgress.changes.addListener(_onSetupChange);
    unawaited(_resolvePersonal());
    unawaited(_readSetup());
  }

  /// Reads every book's close state for the month that has just ended.
  ///
  /// 07 §13 🔒: the card appears **from the 1st**, so the month it offers is
  /// the one before today's — never the month in progress, which has nothing
  /// to close. The clock is the ledger's injected one (CLAUDE.md rule 3), the
  /// same reading the rest of Home takes.
  Future<void> _loadClose() async {
    final source = widget.closeSource ?? CloseScope.maybeOf(context);
    if (source == null) return;
    final today = LedgerScope.of(context).today();
    final ended = today.month == 1
        ? YearMonth(today.year - 1, 12)
        : YearMonth(today.year, today.month - 1);
    try {
      final statuses = await source.closeStatuses(ended);
      if (mounted) setState(() => _closeStatuses = statuses);
    } on Object {
      // A close card that cannot be read is not a reason to lose Home
      // (07 §1 rule 12): the section simply stays unbuilt.
      if (mounted) setState(() => _closeStatuses = const []);
    }
  }

  void _onScope() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Synchronous by design: awaiting a drift stream's cancel during disposal
    // deadlocks flutter_test's fake-async zone (the U2a finding).
    unawaited(_booksSub?.cancel());
    OpeningSetupRecord.changes.removeListener(_onOpeningRecord);
    SetupProgress.changes.removeListener(_onSetupChange);
    _scope.removeListener(_onScope);
    if (widget.scopeController == null) _scope.dispose();
    super.dispose();
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
    final scope = _scope.effective(widget.bookId ?? _bookId);
    // 13 §2.2 🔒: the chip exists only above one book — hidden for an
    // individual, whose app *is* their personal book (07 §2).
    final control = scope != null && _scope.showsControl
        ? HomeScopeControl(controller: _scope, scope: scope)
        : null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        // S21 (07 §25, 13 §3.2: reached from S3 and S1) — the same button S3
        // draws, named by the same string.
        actions: [
          // The search covers the book in scope (07 §25 🔒), so the button
          // waits for a book and hands it over.
          // ⚠️ SPEC: what S21 searches in *Everything* is not ruled (07 §25
          // says "in scope"; S21 searches one book). The conservative reading:
          // no search door while the aggregate is on screen — never a search
          // over one book presented as the aggregate. Switching back to a
          // book brings the door back, so this is not a dead end.
          if (widget.onOpenSearch case final open?)
            if (scope?.bookId case final bookId?)
              IconButton(
                tooltip: l10n.ledgerSearchTitle,
                icon: const Icon(Icons.search),
                onPressed: () => open(bookId),
              ),
        ],
        bottom: control == null
            ? null
            : PreferredSize(
                // Grows with the text scale: two Gurmukhi book names at 200%
                // need more than a fixed 48 px strip (07 §1 rule 11).
                preferredSize: Size.fromHeight(
                  RkSpace.rowMinHeight *
                      MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
                ),
                child: control,
              ),
      ),
      body: SafeArea(child: _content(context, scope)),
    );
  }

  Widget _content(BuildContext context, HomeScope? scope) {
    final l10n = AppLocalizations.of(context);
    if (_resolveError != null && (scope == null || scope.bookId == null)) {
      return RkErrorState(
        text: l10n.homeError,
        retryLabel: l10n.homeRetry,
        onRetry: _retry,
      );
    }
    if (scope == null) return RkSkeleton(label: l10n.homeSkeleton);
    if (scope.isEverything) {
      return HomeEverythingList(
        ledger: LedgerScope.of(context),
        books: _scope.books,
      );
    }
    return _gated(context, scope.bookId!);
  }

  /// S1.4 or the book, decided by the gate (07 §28 🔒).
  Widget _gated(BuildContext context, String bookId) {
    final source = widget.rebuildProgress;
    if (source == null) return _body(context, bookId);
    if (_gateBook != bookId) {
      _gateBook = bookId;
      _progressStream = source(bookId);
      _integrityStream = LedgerScope.of(context)
          .watchHealth(bookId)
          .map((h) => h.integrityOk);
    }
    final l10n = AppLocalizations.of(context);
    return HomeRebuildGate(
      progress: _progressStream!,
      integrityOk: _integrityStream!,
      rebuilding: (context, progress) => ListView(
        padding: const EdgeInsets.only(top: RkSpace.s4),
        children: [
          HomeRebuildingCard(
            title: l10n.homeRebuildTitle,
            progressText: l10n.homeRebuildProgress(
              progress.done,
              progress.total,
            ),
            note: l10n.homeRebuildNote,
            fraction: progress.fraction,
          ),
        ],
      ),
      book: (context) => _body(context, bookId),
    );
  }

  Widget _body(BuildContext context, String bookId) {
    _watchRecordOf(bookId);
    // *Opening balances* opens S0.6, which fills the personal book and no
    // other; over a business, family or trust book the row is information
    // until their own openings (S0.6b/f/i) have a door from Home (⚠️ SPEC,
    // open P1A (a)).
    final doors = bookId == _personalBookId
        ? widget.setupDoors
        : widget.setupDoors.difference(const {SetupStep.openingBalances});
    final purpose = _purpose ?? _branch?.purpose;
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
          return RkErrorState(
            text: l10n.homeError,
            retryLabel: l10n.homeRetry,
            onRetry: () => setState(() {}),
          );
        }
        final data = snap.data;
        if (data == null) return RkSkeleton(label: l10n.homeSkeleton);
        return _HomeBody(
          snapshot: data,
          // One card per book the user closes (07 §13 🔒). This body is one
          // book's, so it carries that book's card; the *Everything* body is
          // where the full set belongs once it adopts the section.
          closeStatuses: [
            for (final s in _closeStatuses)
              if (s.bookId == bookId) s,
          ],
          onOpenClose: _openClose,
          // The book in scope travels with the line (02 §9 "per selected
          // scope"): S1.1 must total the rows this card summed.
          onOpenPosition: switch (widget.onOpenPosition) {
            final open? => (line) => open(line, bookId),
            null => null,
          },
          onOpenAccount: widget.onOpenAccount,
          onVerb: widget.onVerb,
          onOpenEntry: widget.onOpenEntry,
          onOpenDayBook: widget.onOpenDayBook,
          onOpenTrialBalance: widget.onOpenTrialBalance,
          onOpenReconciliation: widget.onOpenReconciliation,
          onSetupStep: widget.onSetupStep,
          setupDoors: doors,
          openingRecorded: _openingRecorded,
          recoverySheetVerified: _sheetVerified,
          setupBranch: _branchRow(),
          // Ruling 3: the family's *Finish …* row replaces *Add your
          // family*; a trust has no family row.
          showAddFamily:
              purpose != OnboardingPurpose.family &&
              purpose != OnboardingPurpose.trust,
          onNotNeeded: (step) => unawaited(_notNeeded(step)),
          rebuildingSlot: widget.rebuildingSlot,
          verbBarKey: _verbBarKey,
        );
      },
    );
  }

  /// Opens S10, or S10.2 for a month that has already closed (07 §13 🔒),
  /// then re-reads the card: the closer comes back to the state he left.
  Future<void> _openClose(BookCloseStatus status) async {
    final open = widget.onOpenClose;
    if (open == null) return;
    final period = status.period.toString();
    await open(
      status.state == BookCloseState.closed
          ? ClosePaths.summaryFor(status.bookId, period)
          : ClosePaths.forBook(status.bookId, period),
    );
    if (mounted) await _loadClose();
  }
}

/// The loaded surface — a pure function of the snapshot, so a test (and the
/// 200% / 360×800 layout check) can pump it without a database.
class _HomeBody extends StatelessWidget {
  const _HomeBody({
    required this.snapshot,
    this.closeStatuses = const [],
    this.onOpenClose,
    this.onOpenPosition,
    this.onOpenAccount,
    this.onVerb,
    this.onOpenEntry,
    this.onOpenDayBook,
    this.onOpenTrialBalance,
    this.onOpenReconciliation,
    this.onSetupStep,
    this.setupDoors = const {...SetupStep.values},
    this.openingRecorded = false,
    this.recoverySheetVerified = false,
    this.setupBranch,
    this.showAddFamily = true,
    this.onNotNeeded,
    this.rebuildingSlot,
    this.verbBarKey,
  });

  final HomeSnapshot snapshot;
  final List<BookCloseStatus> closeStatuses;
  final void Function(BookCloseStatus status)? onOpenClose;
  final void Function(PositionLine line)? onOpenPosition;
  final void Function(String accountId)? onOpenAccount;
  final void Function(EntryKind kind)? onVerb;
  final void Function(String entryId)? onOpenEntry;
  final VoidCallback? onOpenDayBook;
  final VoidCallback? onOpenTrialBalance;
  final VoidCallback? onOpenReconciliation;
  final void Function(SetupStep step)? onSetupStep;
  final Set<SetupStep> setupDoors;
  final bool openingRecorded;
  final bool recoverySheetVerified;
  final SetupBranchRow? setupBranch;
  final bool showAddFamily;
  final void Function(SetupStep step)? onNotNeeded;
  final Widget? rebuildingSlot;

  /// Keys the pinned verb bar so the screen can measure it.
  final Key? verbBarKey;

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
    // for a "new user" but never defines the test. The reading taken here —
    // no entry beyond the opening balances ([HomeSnapshot.firstRun]) — lets
    // desk 172's *Finish* land on the O8 checklist with the row ticked, and
    // a book with one ordinary posting never loses its position card.
    final firstRun = snapshot.firstRun;
    // Desk 172: S0.6's *Finish* ticks the row whatever was typed; a figure on
    // `Opening Balance / Capital A/c` ticks it too (an opening posted any
    // other way). *Skip for now* does neither, so the row stays the way back.
    // [openingRecorded] is this book's own record.
    final openingDone = snapshot.openingBalancesDone || openingRecorded;

    final review = [
      for (final r in snapshot.today)
        if (r.underReview) r,
    ];
    final reviewPaise = review.fold<int>(
      0,
      (s, r) => s + (HomeTodayRow.amountLine(r, chart)?.amountPaise.abs() ?? 0),
    );

    // Canvas 1 O8 and canvas 15 S1 pin the four verbs in a bar directly above
    // the tab bar, with the list (hero, checklist or position, Today)
    // scrolling above it; 07 §1 rules 1–2 🔒 ask the same — the verbs are
    // never below the fold, first run or populated. Only the list scrolls.
    final list = ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s4),
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
        // ADR 2026-10-07 ruling 3: the checklist outlives the empty state —
        // it leaves only when every row is ticked or set to *Not needed*
        // (the optional *Add your family* never holds it open). Until then
        // it sits above the position card, which returns with the first
        // entry.
        if (HomeSetupChecklist.isOpen(
          openingBalancesDone: openingDone,
          firstEntryDone: !firstRun,
          recoverySheetVerified: recoverySheetVerified,
          branch: setupBranch,
        ))
          HomeSetupChecklist(
            openingBalancesDone: openingDone,
            doors: setupDoors,
            // The book's first entry, which is also what ends the empty
            // state.
            firstEntryDone: !firstRun,
            recoverySheetVerified: recoverySheetVerified,
            branch: setupBranch,
            showAddFamily: showAddFamily,
            onStep: onSetupStep,
            onNotNeeded: onNotNeeded,
          ),
        if (!firstRun)
          HomePositionCard(
            snapshot: snapshot,
            onOpenPosition: onOpenPosition,
            onOpenAccount: onOpenAccount,
            onOpenReconciliation: onOpenReconciliation,
          ),
        HomeMonthLine(
          inPaise: snapshot.monthInPaise,
          outPaise: snapshot.monthOutPaise,
        ),
        // The *Close card* (07 §13 🔒 bullet 1).
        //
        // ⚠️ SPEC: 07 §4 🔒 draws Home card by card and never places this one
        // — the only instruction is 07 §13's *"appears on Home from the 1st"*
        // — and no canvas frame draws it on Home. 07 §1 rule 1 🔒 says every
        // design decision loses to the 8-second entry, so a monthly invitation
        // may not push the verbs out of thumb reach (rule 2). The verbs are
        // now pinned in [HomeVerbBar] below the list, so nothing in the list
        // can push them; the card keeps its old slot, after the month line
        // and above Today — the first thing the list offers after the figures.
        HomeCloseCards(
          statuses: closeStatuses,
          onOpenClose: onOpenClose,
          onOpenSummary: onOpenClose,
        ),
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
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          Expanded(child: list),
          HomeVerbBar(
            key: verbBarKey,
            // Never more than half the body (07 §1 rule 11): at 200 % in a
            // short window the bar scrolls inside itself and the list keeps
            // its half.
            maxHeight: box.maxHeight.isFinite ? box.maxHeight / 2 : null,
            child: HomeVerbGate(onVerb: onVerb),
          ),
        ],
      ),
    );
  }
}
