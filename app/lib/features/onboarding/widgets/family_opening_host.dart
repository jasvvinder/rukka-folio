// The committing step of the family branch (07 §3.1.1 O6d → O6e → O6f).
//
// S0.6f is a review-and-fill over accounts that already exist (ADR
// 2026-09-09c §3, applied to the family pool), so something has to create
// the pool book first. That is here, mirroring [BusinessOpeningHost]: the
// S0.6d name answer is held by [OnboardingFlow], `createBook` runs once with
// `BookType.family`, its seeded chart (ADR 2026-09-09c §1 — `Joint Cash A/c`,
// `Opening Balance / Capital`, no bank, no categories) becomes the screen's
// rows, and the book id is remembered so a resumed step never creates a
// second book (07 §3.1.1: every branch step is resumable).
//
// A joint family that owns businesses is several books linked by
// Due-to/from pairs, never one book with sub-family shares (ADR 2026-09-09c
// §2) — this host creates **the pool book only**; each head's own book and
// each business are separate onboarding flows.
//
// The three states of 13 §4.3 that can happen here are all drawn: working
// (the ruled skeleton of 11 §4.5, never a spinner), error-with-retry (07 §1
// rule 12), and the screen itself.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../onboarding_flow.dart';
import '../screens/s0_6b_business_opening_balances_screen.dart'
    show OpeningGroup, OpeningRow;
import '../screens/s0_6f_family_accounts_screen.dart';

/// Creates the family pool book from [flow], then shows S0.6f over its chart.
class FamilyOpeningHost extends StatefulWidget {
  /// Creates the host.
  const FamilyOpeningHost({
    super.key,
    required this.flow,
    required this.startDate,
    this.onDone,
    this.onAddAccount,
  });

  /// The answer S0.6d collected.
  final OnboardingFlow flow;

  /// The day the book's books begin (ADR 2026-09-09d §4).
  final LocalDate startDate;

  /// Called once the balances are posted, or *Skip for now* is taken — the
  /// S0.7 checklist brings a skipped wizard back (07 §3.1 step 7).
  final VoidCallback? onDone;

  /// Opens *Add an account* (S3.1) — how a bank arrives, since no book seeds
  /// one (ADR 2026-09-09d §1).
  final void Function(OpeningGroup group)? onAddAccount;

  @override
  State<FamilyOpeningHost> createState() => _FamilyOpeningHostState();
}

class _FamilyOpeningHostState extends State<FamilyOpeningHost> {
  List<OpeningRow>? _rows;
  Object? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _commit());
  }

  Future<void> _commit() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final ledger = LedgerScope.of(context);
      final flow = widget.flow;
      final draft = flow.family;
      if (draft == null) throw StateError('S0.6d has not been answered');
      final bookId =
          flow.familyBookId ??
          await ledger.createBook(
            name: draft.name,
            type: BookType.family,
            startDate: widget.startDate,
          );
      flow.familyBookId = bookId;
      final chart = await ledger.chartOf(bookId);
      // Only money accounts are reviewed here (ADR 2026-09-09c §1: the pool
      // seeds `Joint Cash A/c` and nothing else besides its Opening Balance /
      // Capital account, which absorbs the difference rather than being a row
      // — same shape as [BusinessOpeningHost]'s `_groupOf`).
      final rows = <OpeningRow>[
        for (final a in chart.accounts)
          if (a.accountClass == AccountClass.money)
            OpeningRow(accountId: a.id, name: a.name, group: OpeningGroup.have),
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
    final ledger = LedgerScope.of(context);
    final bookId = widget.flow.familyBookId;
    if (bookId == null) return;
    try {
      await ledger.openingBalances(bookId, balances: balances);
      widget.onDone?.call();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return _CommitState(
        icon: Icons.error_outline,
        message: l10n.onboardingFamilyAccountsCreateError,
        action: l10n.onboardingFamilyAccountsRetry,
        onAction: _commit,
      );
    }
    final rows = _rows;
    if (rows == null) {
      return _CommitState(
        icon: Icons.hourglass_empty,
        message: l10n.onboardingFamilyAccountsCreating,
      );
    }
    return FamilySharedAccountsScreen(
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
    required this.message,
    this.action,
    this.onAction,
  });

  final IconData icon;
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
                Icon(icon, color: status.muted, size: RkIcon.grid),
                const SizedBox(height: RkSpace.s3),
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
