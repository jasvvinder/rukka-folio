// The committing step of the business branch (07 §3.1.1 O6a → O6b).
//
// S0.6b is a **review-and-fill** over accounts that already exist (ADR
// 2026-09-09c §3), so something has to create the book first. That is here:
// the S0.6a name / ownership / FY answers and the S0.6a1 owners are held by
// [OnboardingFlow], `createBook` runs once, its seeded chart (ADR
// 2026-09-09c §1) becomes the screen's rows, and the book id is remembered so
// a resumed step never creates a second book (07 §3.1.1: every branch step is
// resumable).
//
// The three states of 13 §4.3 that can happen here are all drawn: working
// (the ruled skeleton of 11 §4.5, never a spinner), error-with-retry (07 §1
// rule 12 — the book is created, or the user is told why not and offered the
// way on; never a dead end), and the screen itself.
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BookOwnership;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../entry/entry_restriction.dart';
import '../onboarding_flow.dart';
import '../screens/s0_6a_business_name_screen.dart';
import '../screens/s0_6b_business_opening_balances_screen.dart';

/// Creates the business book from [flow], then shows S0.6b over its chart.
class BusinessOpeningHost extends StatefulWidget {
  /// Creates the host.
  const BusinessOpeningHost({
    super.key,
    required this.flow,
    required this.startDate,
    this.onDone,
    this.onAddAccount,
  });

  /// The answers S0.6a and S0.6a1 collected.
  final OnboardingFlow flow;

  /// The day the book's books begin (ADR 2026-09-09d §4).
  final LocalDate startDate;

  /// Called once the balances are posted, or *Skip for now* is taken — the
  /// S0.7 checklist brings a skipped wizard back (07 §3.1 step 7).
  final VoidCallback? onDone;

  /// Opens *Add an account* for a group (S3.1) — how a bank arrives, since
  /// no book seeds one (ADR 2026-09-09d §1).
  final void Function(OpeningGroup group)? onAddAccount;

  @override
  State<BusinessOpeningHost> createState() => _BusinessOpeningHostState();
}

class _BusinessOpeningHostState extends State<BusinessOpeningHost> {
  List<OpeningRow>? _rows;
  Object? _error;
  bool _running = false;

  /// Read-only refused the book's creation (ADR 2026-09-24b §13): the S12.5
  /// sheet has risen, nothing was appended, and *Try again* asks once more.
  bool _blocked = false;

  /// A Save is in flight — not drawn, only a re-entry guard, so a double tap
  /// never posts the opening balances twice or stacks two S12.5 sheets.
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _commit());
  }

  /// Which group a seeded account is reviewed under (ADR 2026-09-09c §3).
  /// Equity and category accounts carry no opening balance of their own —
  /// `Opening Balance / Capital A/c` absorbs the difference (§4) — so they
  /// are not rows.
  static OpeningGroup? _groupOf(Account a) => switch (a.accountClass) {
    AccountClass.money => OpeningGroup.have,
    AccountClass.partner => OpeningGroup.ownerContributions,
    AccountClass.party => null,
    AccountClass.advance ||
    AccountClass.categoryIncome ||
    AccountClass.categoryExpense ||
    AccountClass.equitySystem => null,
  };

  Future<void> _commit() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _blocked = false;
    });
    try {
      final ledger = LedgerScope.of(context);
      final flow = widget.flow;
      final draft = flow.business;
      if (draft == null) throw StateError('S0.6a has not been answered');
      // S12.5 (ADR 2026-09-24b §13): creating the book appends envelopes (its
      // book_config and the seeded chart), so read-only refuses it with the
      // same sheet **before** `createBook` runs. A resumed step whose book
      // already exists writes nothing here and is not asked. No book id is
      // passed: book full is a per-book answer (ADR 2026-09-05b §7) and a book
      // not yet created has none. The seams are read before the first await.
      if (flow.businessBookId == null) {
        final sources = entryRestrictionSourcesOf(context);
        final refused = await refuseIfEntryRestricted(
          context,
          sources,
          const <String>[],
          onBlocked: () => setState(() {
            _blocked = true;
            _running = false;
          }),
        );
        if (refused) return;
      }
      final bookId =
          flow.businessBookId ??
          await ledger.createBook(
            name: draft.name,
            type: BookType.business,
            fyStartMonth: draft.fyStartMonth,
            ownership: draft.ownership == BusinessOwnershipChoice.shared
                ? BookOwnership.shared
                : BookOwnership.justMe,
            ownerNames: flow.ownerNames,
            // ADR 2026-09-09 §2: the ratio is fixed at creation, so this is
            // the one moment it can be recorded. `createBook` keys it to the
            // partner account ids it mints (02 §7.1 🔒).
            ownerShares: flow.ownerShares,
            // The chart's Partner Current A/c → member mapping the owner set
            // is derived from (ADR 2026-09-14b; structural_reader
            // `_ownersNamed`). The creating user's id comes from the open
            // ledger, never a guess; an invited owner has none yet (02 §7.1),
            // and then nothing is passed — see [OnboardingFlow.ownerMemberIds].
            ownerMemberIds: flow.ownerMemberIds(ledger.identity.userId),
            startDate: widget.startDate,
          );
      flow.businessBookId = bookId;
      final chart = await ledger.chartOf(bookId);
      final rows = <OpeningRow>[
        for (final a in chart.accounts)
          if (_groupOf(a) case final group?)
            OpeningRow(accountId: a.id, name: a.name, group: group),
      ];
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _running = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _running = false;
      });
    }
  }

  Future<void> _save(Map<String, int> balances) async {
    if (_saving) return;
    _saving = true;
    try {
      // S12.5 (ADR 2026-09-24b §13): read-only blocks onboarding's opening
      // balances with the same sheet. The figures stay typed on the screen
      // underneath (drafts kept); *Skip for now* still leads on, so the step is
      // never a dead end. Both seams are read before the first await.
      final sources = entryRestrictionSourcesOf(context);
      final ledger = LedgerScope.of(context);
      final bookId = widget.flow.businessBookId;
      if (bookId == null) return;
      if (await refuseIfEntryRestricted(context, sources, [bookId])) return;
      try {
        await ledger.openingBalances(bookId, balances: balances);
        widget.onDone?.call();
      } on Object catch (e) {
        if (!mounted) return;
        setState(() => _error = e);
      }
    } finally {
      _saving = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return _CommitState(
        icon: Icons.error_outline,
        message: l10n.onboardingBusinessOpeningCreateError,
        action: l10n.onboardingBusinessOpeningRetry,
        onAction: _commit,
      );
    }
    if (_blocked) {
      // Colour never alone (07 §1): the lock and the words carry it; the way
      // on is *Try again*, which re-asks and re-raises the sheet whose action
      // opens S12.1 Plans — never a dead end (07 §1 rule 2).
      return _CommitState(
        icon: Icons.lock_outline,
        title: l10n.subscriptionBannerReadOnlyTitle,
        message: l10n.subscriptionBannerReadOnlyBody,
        action: l10n.onboardingBusinessOpeningRetry,
        onAction: _commit,
      );
    }
    final rows = _rows;
    if (rows == null) {
      return _CommitState(
        icon: Icons.hourglass_empty,
        message: l10n.onboardingBusinessOpeningCreating,
      );
    }
    return BusinessOpeningBalancesScreen(
      rows: rows,
      startDate: widget.startDate,
      onSave: _save,
      onSkip: widget.onDone,
      onAddAccount: widget.onAddAccount,
    );
  }
}

/// The working and error states — the ruled skeleton shape of 11 §4.5, with
/// the cause named and the way on offered (07 §1 rule 12).
class _CommitState extends StatelessWidget {
  const _CommitState({
    required this.icon,
    this.title,
    required this.message,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String? title;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Colour never alone (07 §1): the icon and the words carry it.
                Icon(icon, color: status.muted, size: RkIcon.grid),
                const SizedBox(height: RkSpace.s3),
                if (title case final title?) ...[
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: RkSpace.s2),
                ],
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: text.bodyLarge,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: RkSpace.s4),
                  FilledButton(onPressed: onAction, child: Text(action!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
