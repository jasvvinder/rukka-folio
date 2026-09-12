// The committing step of the trust branch (07 §3.1.1 O6g → O6h → O6i).
//
// S0.6i is a review-and-fill over accounts that already exist (ADR
// 2026-09-09c §3, applied to the trust, the same reading U1d took for the
// family pool), so something has to create the trust book first. That is
// here, mirroring [FamilyOpeningHost] and [BusinessOpeningHost]: the S0.6g
// name/type answer is held by [OnboardingFlow], `createBook` runs once with
// `BookType.organization`, its seeded chart (ADR 2026-09-09d §2 — Cash A/c,
// the gollak as `cash_collection`, and the trust's four 🔒 category accounts,
// 07 §3.1 step 3) becomes the screen's rows, and the book id is remembered so
// a resumed step never creates a second book (07 §3.1.1: every branch step is
// resumable).
//
// S0.6g's [TrustType] is persisted as `book_config.organization_subtype`
// (07 §3.1.1 🔒). It is display-only today — every value is the same
// `tenant.type = organization`, and nothing branches on it — but it is the
// user's own answer, so the ledger keeps it rather than the wizard throwing it
// away. The two enums are mapped explicitly by [_subtypeOf] rather than being
// one type: 07 §3.1.1 calls its four an illustrative list, so the screen's
// choices and the stored vocabulary are free to diverge.
//
// The three states of 13 §4.3 that can happen here are all drawn: working
// (the ruled skeleton of 11 §4.5, never a spinner), error-with-retry (07 §1
// rule 12), and the screen itself.
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show OrganizationSubtype;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../onboarding_flow.dart';
import '../screens/s0_6b_business_opening_balances_screen.dart'
    show OpeningGroup, OpeningRow;
import '../screens/s0_6g_trust_name_screen.dart' show TrustType;
import '../screens/s0_6i_trust_accounts_screen.dart';

/// The stored subtype for a screen choice (07 §3.1.1's four 🔒). Exhaustive on
/// purpose: a fifth [TrustType] must be given a wire name here, not silently
/// stored as a gurudwara.
OrganizationSubtype _subtypeOf(TrustType type) => switch (type) {
  TrustType.gurudwara => OrganizationSubtype.gurudwara,
  TrustType.temple => OrganizationSubtype.temple,
  TrustType.society => OrganizationSubtype.society,
  TrustType.registeredTrust => OrganizationSubtype.registeredTrust,
};

/// Creates the trust book from [flow], then shows S0.6i over its chart.
class TrustOpeningHost extends StatefulWidget {
  /// Creates the host.
  const TrustOpeningHost({
    super.key,
    required this.flow,
    required this.startDate,
    this.onDone,
    this.onAddAccount,
  });

  /// The answer S0.6g collected.
  final OnboardingFlow flow;

  /// The day the book's books begin (ADR 2026-09-09d §4).
  final LocalDate startDate;

  /// Called once the balances are posted, or *Skip for now* is taken — the
  /// S0.7 checklist brings a skipped wizard back (07 §3.1 step 7).
  final VoidCallback? onDone;

  /// Opens *Add an account* (S3.1) — how a bank arrives, since no book seeds
  /// one (ADR 2026-09-09d §1/§2).
  final void Function(OpeningGroup group)? onAddAccount;

  @override
  State<TrustOpeningHost> createState() => _TrustOpeningHostState();
}

class _TrustOpeningHostState extends State<TrustOpeningHost> {
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
      final draft = flow.trust;
      if (draft == null) throw StateError('S0.6g has not been answered');
      final bookId =
          flow.trustBookId ??
          await ledger.createBook(
            name: draft.name,
            type: BookType.organization,
            organizationSubtype: _subtypeOf(draft.type),
            startDate: widget.startDate,
          );
      flow.trustBookId = bookId;
      final chart = await ledger.chartOf(bookId);
      // Only money accounts are reviewed here (ADR 2026-09-09d §2: the trust
      // seeds Cash A/c and the gollak as `cash_collection`, plus four
      // category accounts that carry no opening balance of their own — same
      // shape as [FamilyOpeningHost] / [BusinessOpeningHost]'s `_groupOf`).
      final rows = <OpeningRow>[
        for (final a in chart.accounts)
          if (a.accountClass == AccountClass.money)
            OpeningRow(
              accountId: a.id,
              name: a.name,
              group: OpeningGroup.have,
              isCollection: a.isCollection,
            ),
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
    final bookId = widget.flow.trustBookId;
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
        message: l10n.onboardingTrustAccountsCreateError,
        action: l10n.onboardingTrustAccountsRetry,
        onAction: _commit,
      );
    }
    final rows = _rows;
    if (rows == null) {
      return _CommitState(
        icon: Icons.hourglass_empty,
        message: l10n.onboardingTrustAccountsCreating,
      );
    }
    return TrustAccountsScreen(
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
