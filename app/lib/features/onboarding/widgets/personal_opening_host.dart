// The host of S0.6 *Opening balances · first run* (desk 172): finds — or, as
// a safety net, makes — the person's personal book (`personal_book.dart`,
// desk 164), watches its accounts, and shows "What do you have?" over them.
//
// Live, not one-shot: *Add an account* opens S3.1 over this book, and the
// account it adds (with the balance it asked for in the same breath, 02 §4 🔒)
// appears here as soon as it is projected.
//
// *Finish* posts the typed figures through `LocalLedger.openingBalances` —
// one `adjustment` per non-zero row against *Opening Balance* (02 §4; no
// posting logic here) — records the press for the S0.7 checklist
// ([OpeningSetupRecord]) and goes on. *Skip for now* goes on and records
// nothing, so the checklist row stays open as the way back (desk 172).
//
// States (13 §4.3): working (ruled skeleton shape, 11 §4.5 — never a spinner),
// error with retry (07 §1 rule 12), read-only refused (S12.5, ADR 2026-09-24b
// §13), the screen, and a failed save named on the screen with *Finish* still
// the way on.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_settings.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart' show AccountBalance;
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../entry/entry_restriction.dart';
import '../../ledger/screens/s3_1_quick_add_sheet.dart' show QuickAddSheet;
import '../onboarding_flow.dart';
import '../onboarding_gate.dart' show OnboardingBack;
import '../opening_figures.dart';
import '../opening_setup_record.dart';
import '../personal_book.dart';
import '../screens/s0_6_opening_balances_screen.dart';
import '../screens/s0_6b_business_opening_balances_screen.dart'
    show OpeningGroup;

/// S0.6 over the personal book.
class PersonalOpeningHost extends StatefulWidget {
  /// Creates the host.
  const PersonalOpeningHost({
    super.key,
    required this.flow,
    required this.startDate,
    required this.onDone,
    this.onBack,
  });

  /// The chain's answers — S0.4's name names the book if it must be made here.
  final OnboardingFlow flow;

  /// The day a book made here begins (ADR 2026-09-09d §4).
  final LocalDate startDate;

  /// *Finish* (after the post) or *Skip for now* — the hand-over to Home.
  final VoidCallback onDone;

  /// The back chevron and system Back (ADR 2026-10-06b ruling 3); held while
  /// the book is being made or a save is in flight.
  final VoidCallback? onBack;

  @override
  State<PersonalOpeningHost> createState() => _PersonalOpeningHostState();
}

class _PersonalOpeningHostState extends State<PersonalOpeningHost> {
  String? _bookId;
  LocalDate? _asOn;
  Stream<List<AccountBalance>>? _accounts;
  Stream<Map<String, int>>? _openings;
  Object? _error;
  bool _blocked = false;
  bool _running = false;
  bool _saving = false;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (_running || !mounted) return;
    setState(() {
      _running = true;
      _error = null;
      _blocked = false;
    });
    try {
      final ledger = LedgerScope.of(context);
      final l10n = AppLocalizations.of(context);
      final sources = entryRestrictionSourcesOf(context);
      var bookId = await personalBookIdOf(ledger);
      if (bookId == null) {
        // Making the book appends envelopes, so read-only refuses it with the
        // S12.5 sheet first (ADR 2026-09-24b §13), exactly as S0.6b does.
        if (!mounted) return;
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
        final name = widget.flow.yourName;
        bookId = await ensurePersonalBook(
          ledger,
          // ⚠️ SPEC: the S0.4 name lives only in the flow (ADR 2026-10-06b
          // ruling 2's conservative reading); after a cold start that lost
          // it, and a creation that failed at S0.4, the book still has to
          // exist, so it takes a plain placeholder the person can rename.
          name: name.isNotEmpty ? name : l10n.onboardingOpeningDefaultBookName,
          startDate: widget.startDate,
        );
      }
      final asOn = await ledger.startDateOf(bookId) ?? widget.startDate;
      if (!mounted) return;
      setState(() {
        _bookId = bookId;
        _asOn = asOn;
        _accounts = ledger.watchAccounts(bookId!);
        _openings = watchOpeningFigures(ledger, bookId);
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

  /// The rows, each carrying the account's **opening** figure — never its
  /// running balance (P1A review, finding 2: reopened from the checklist
  /// after an entry, a running balance would pose as the opening and lock
  /// the row). [openings] is [watchOpeningFigures]'s map.
  static List<FirstRunRow> _rowsOf(
    List<AccountBalance> accounts,
    Map<String, int> openings,
  ) => [
    for (final a in accounts)
      if (!a.archived)
        if (_groupOf(a, openings[a.account.id] ?? 0) case final group?)
          FirstRunRow(
            accountId: a.account.id,
            name: a.account.name,
            group: group,
            isCash: a.account.subtype == MoneySubtype.cash,
            postedPaise: openings[a.account.id] ?? 0,
          ),
  ];

  /// Money accounts are *what you have*; a party sits under the side its
  /// opening is on (02 §9: Dr = they will pay you). A party with no opening
  /// — added with no figure — has no side yet and is listed under *who owes
  /// you*. Categories, advances and the system accounts carry no opening
  /// here.
  static OpeningGroup? _groupOf(AccountBalance a, int opening) =>
      switch (a.account.accountClass) {
        AccountClass.money => OpeningGroup.have,
        AccountClass.party =>
          opening < 0 ? OpeningGroup.youOwe : OpeningGroup.owedToYou,
        _ => null,
      };

  Future<void> _addAccount() async {
    final bookId = _bookId;
    if (bookId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuickAddSheet(bookId: bookId),
    );
  }

  Future<void> _finish(Map<String, int> balances) async {
    final bookId = _bookId;
    if (bookId == null || _saving) return;
    final sources = entryRestrictionSourcesOf(context);
    final ledger = LedgerScope.of(context);
    final prefs = AppSettingsScope.read(context)?.prefs;
    setState(() {
      _saving = true;
      _saveFailed = false;
    });
    try {
      final toPost = {
        for (final e in balances.entries)
          if (e.value != 0) e.key: e.value,
      };
      if (toPost.isNotEmpty) {
        // Read-only blocks the post with the S12.5 sheet; the figures stay
        // typed underneath and *Skip for now* still leads on (no dead end).
        if (await refuseIfEntryRestricted(context, sources, [bookId])) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        await ledger.openingBalances(bookId, balances: toPost);
      }
      await OpeningSetupRecord.markFinished(prefs, bookId);
      if (!mounted) return;
      setState(() => _saving = false);
      widget.onDone();
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final back = widget.onBack;
    final busy = _running || _saving;
    final body = _body(context, back == null || busy ? null : back);
    if (back == null) return body;
    return OnboardingBack(
      onBack: () {
        if (!_running && !_saving) back();
      },
      child: body,
    );
  }

  Widget _body(BuildContext context, VoidCallback? back) {
    final l10n = AppLocalizations.of(context);
    if (_error != null) {
      return _HostState(
        icon: Icons.error_outline,
        message: l10n.onboardingOpeningCreateError,
        action: l10n.onboardingOpeningRetry,
        onAction: _open,
        // Never a dead end (07 §1 rule 6): the step can still be skipped.
        secondary: l10n.onboardingOpeningSkip,
        onSecondary: widget.onDone,
      );
    }
    if (_blocked) {
      return _HostState(
        icon: Icons.lock_outline,
        title: l10n.subscriptionBannerReadOnlyTitle,
        message: l10n.subscriptionBannerReadOnlyBody,
        action: l10n.onboardingOpeningRetry,
        onAction: _open,
        secondary: l10n.onboardingOpeningSkip,
        onSecondary: widget.onDone,
      );
    }
    final accounts = _accounts;
    final openings = _openings;
    final asOn = _asOn;
    if (accounts == null || openings == null || asOn == null) {
      return _HostState(
        icon: Icons.hourglass_empty,
        message: l10n.onboardingOpeningCreating,
      );
    }
    return StreamBuilder<List<AccountBalance>>(
      stream: accounts,
      builder: (context, snap) {
        if (snap.hasError) {
          return _HostState(
            icon: Icons.error_outline,
            message: l10n.onboardingOpeningCreateError,
            action: l10n.onboardingOpeningRetry,
            onAction: _open,
            secondary: l10n.onboardingOpeningSkip,
            onSecondary: widget.onDone,
          );
        }
        final data = snap.data;
        if (data == null) {
          return _HostState(
            icon: Icons.hourglass_empty,
            message: l10n.onboardingOpeningCreating,
          );
        }
        return StreamBuilder<Map<String, int>>(
          stream: openings,
          builder: (context, opened) {
            if (opened.hasError) {
              return _HostState(
                icon: Icons.error_outline,
                message: l10n.onboardingOpeningCreateError,
                action: l10n.onboardingOpeningRetry,
                onAction: _open,
                secondary: l10n.onboardingOpeningSkip,
                onSecondary: widget.onDone,
              );
            }
            final figures = opened.data;
            if (figures == null) {
              return _HostState(
                icon: Icons.hourglass_empty,
                message: l10n.onboardingOpeningCreating,
              );
            }
            return OpeningBalancesScreen(
              rows: _rowsOf(data, figures),
              asOn: asOn,
              busy: _saving,
              saveFailed: _saveFailed,
              onBack: back,
              onAddAccount: _addAccount,
              onFinish: (balances) => unawaited(_finish(balances)),
              onSkip: widget.onDone,
            );
          },
        );
      },
    );
  }
}

/// Working / error / blocked — the cause named and the way on offered
/// (07 §1 rule 12).
class _HostState extends StatelessWidget {
  const _HostState({
    required this.icon,
    this.title,
    required this.message,
    this.action,
    this.onAction,
    this.secondary,
    this.onSecondary,
  });

  final IconData icon;
  final String? title;
  final String message;
  final String? action;
  final VoidCallback? onAction;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
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
                if (action case final action?) ...[
                  const SizedBox(height: RkSpace.s4),
                  FilledButton(onPressed: onAction, child: Text(action)),
                ],
                if (secondary case final secondary?)
                  TextButton(onPressed: onSecondary, child: Text(secondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
