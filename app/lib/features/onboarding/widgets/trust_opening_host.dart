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
import '../../../shared/app_settings.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../entry/entry_restriction.dart';
import '../onboarding_flow.dart';
import '../onboarding_gate.dart' show OnboardingBack;
import '../opening_setup_record.dart';
import '../screens/s0_3_purpose_screen.dart' show OnboardingPurpose;
import '../setup_progress.dart';
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
    this.onBack,
  });

  /// The answer S0.6g collected.
  final OnboardingFlow flow;

  /// The day the book's books begin (ADR 2026-09-09d §4).
  final LocalDate startDate;

  /// Called once the balances are saved (ADR 2026-10-07 ruling 1: there is
  /// no *Skip for now*; ₹0 everywhere is a valid answer).
  final VoidCallback? onDone;

  /// Opens *Add an account* (S3.1) — how a bank arrives, since no book seeds
  /// one (ADR 2026-09-09d §1/§2).
  final void Function(OpeningGroup group)? onAddAccount;

  /// System Back (ADR 2026-10-06b ruling 3): the chain's previous step. Held
  /// while the book is being created or the balances are being saved — a
  /// step mid-operation holds its place — and once the book exists the
  /// route resolves no previous step at all (`previousOnboardingStep`), so
  /// the answers fixed into the book are never reopened. Null leaves Back
  /// alone.
  final VoidCallback? onBack;

  @override
  State<TrustOpeningHost> createState() => _TrustOpeningHostState();
}

class _TrustOpeningHostState extends State<TrustOpeningHost> {
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
      final draft = flow.trust;
      // A step resumed over a book already made needs no answer: a cold start
      // lost [draft] but `branch_resume.dart` put the book back.
      if (draft == null && flow.trustBookId == null) {
        throw StateError('S0.6g has not been answered');
      }
      // Kept on the device so a cold start resumes over this book instead of
      // making a second (ADR 2026-10-06b ruling 2 🔒, 07 §3.1.1). Not in S9.5
      // (Menu → Add a business), which reuses this host on an onboarded
      // install. Read before the first await.
      final settings = AppSettingsScope.read(context);
      final keep = !(settings?.onboarded ?? false);
      final made = flow.trustBookId == null;
      // S12.5 (ADR 2026-09-24b §13): creating the book appends envelopes (its
      // book_config and the seeded chart), so read-only refuses it with the
      // same sheet **before** `createBook` runs. A resumed step whose book
      // already exists writes nothing here and is not asked. No book id is
      // passed: book full is a per-book answer (ADR 2026-09-05b §7) and a book
      // not yet created has none. The seams are read before the first await.
      if (flow.trustBookId == null) {
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
          flow.trustBookId ??
          await ledger.createBook(
            name: draft!.name,
            type: BookType.organization,
            organizationSubtype: _subtypeOf(draft.type),
            startDate: widget.startDate,
          );
      flow.trustBookId = bookId;
      if (made && keep) {
        await SetupProgress.recordBranchBook(
          settings?.prefs,
          SetupBranchBook(purpose: OnboardingPurpose.trust, bookId: bookId),
        );
      }
      // Mounted again after its balances were posted (a resume, a deep
      // link): the step is done, so it moves on rather than offering to post
      // a second set to the same book (07 §3.1.1 — never duplicated).
      if (widget.flow.trustOpeningPosted) {
        if (mounted) setState(() => _running = false);
        widget.onDone?.call();
        return;
      }
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
    if (_saving) return;
    _saving = true;
    try {
      // S12.5 (ADR 2026-09-24b §13): read-only blocks onboarding's opening
      // balances with the same sheet. The figures stay typed on the screen
      // underneath (drafts kept); ₹0 everywhere still saves, so the step is
      // never a dead end. Both seams are read before the first await.
      final sources = entryRestrictionSourcesOf(context);
      final ledger = LedgerScope.of(context);
      final bookId = widget.flow.trustBookId;
      if (bookId == null) return;
      // Posted once already: one set of opening adjustments per book.
      if (widget.flow.trustOpeningPosted) {
        widget.onDone?.call();
        return;
      }
      final prefs = AppSettingsScope.read(context)?.prefs;
      // ADR 2026-10-07 ruling 1: the step is required, and ₹0 everywhere is a
      // valid answer that posts nothing (02 §4) — so it is never refused as a
      // write: read-only cannot turn a required step into a dead end (07 §1
      // rule 6).
      final toPost = {
        for (final e in balances.entries)
          if (e.value != 0) e.key: e.value,
      };
      if (toPost.isNotEmpty &&
          await refuseIfEntryRestricted(context, sources, [bookId])) {
        return;
      }
      try {
        if (toPost.isNotEmpty) {
          await ledger.openingBalances(bookId, balances: toPost);
        }
        // Ruling 3: the S0.7 *Opening balances* row arrives ticked over this
        // book too, whatever was typed.
        await OpeningSetupRecord.markFinished(prefs, bookId);
        // ADR 2026-10-07 ruling 3: a skipped invite step's *Finish …* row
        // names this book.
        await SetupProgress.attachBook(prefs, OnboardingPurpose.trust, bookId);
        widget.flow.trustOpeningPosted = true;
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
    final back = widget.onBack;
    final body = _body(context);
    if (back == null) return body;
    // Read at the moment of the press: the two flags are not always set
    // through setState, so a value captured at build could be stale.
    return OnboardingBack(
      onBack: () {
        if (!_running && !_saving) back();
      },
      child: body,
    );
  }

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return _CommitState(
        icon: Icons.error_outline,
        message: l10n.onboardingTrustAccountsCreateError,
        action: l10n.onboardingTrustAccountsRetry,
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
