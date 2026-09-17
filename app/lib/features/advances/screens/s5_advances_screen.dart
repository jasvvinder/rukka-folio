// S5 Advances (07 §8 🔒, 13 §3.2 row S5; reached from S1's advances position
// row and from S6). Two sections, both read straight off 02 §7's `advance`
// account balances — there is no separate advance state anywhere, so the two
// dashboards cannot drift from the ledger or from each other:
//
//   *Advance with you*  — the holder's cards: purpose, taken date, spent-vs-
//                          remaining bar, `Add spend`, `Return remaining`.
//   *Advance out*       — the book's aged list, oldest unsettled first; the
//                          approver's `Remind` and `Write off (reason)` sit
//                          under each row in 13 §4.3's disabled-with-reason
//                          state, because neither has a mechanism yet.
//
// S5.1, the request form, is another lane's screen. Nothing here links to it:
// 07 §1 rule 6 says a blocked action explains itself and offers the path, and
// an action whose path does not exist yet is simply not drawn.
//
// ⚠️ SPEC: 13 §7 gives *Approve advance* to owner and admin only, but the app
// has no book-role source yet (members are another lane's). [canApprove]
// therefore defaults to true, which is exactly right for the pre-scope-
// switcher solo book — its only member is its owner — and is the parameter
// the shell will pass once roles land. Reported to the owner, not guessed at
// silently.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../advances_book.dart';
import '../widgets/advance_aged_row.dart';
import '../widgets/advance_card.dart';
import '../widgets/advance_entry_sheet.dart';

/// S5 — *Advance with you* and *Advance out*.
class AdvancesScreen extends StatefulWidget {
  /// Creates the screen.
  const AdvancesScreen({super.key, this.bookId, this.canApprove = true});

  /// Explicit book; when null the solo book is resolved
  /// ([advancesBookId]).
  final String? bookId;

  /// Whether this member may approve advances here (13 §7).
  final bool canApprove;

  @override
  State<AdvancesScreen> createState() => _AdvancesScreenState();
}

class _AdvancesScreenState extends State<AdvancesScreen> {
  String? _bookId;
  Object? _resolveError;
  bool _started = false;
  Stream<List<AdvanceView>>? _mine;
  Stream<List<AdvanceView>>? _given;
  Stream<List<AccountBalance>>? _accounts;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope is an InheritedWidget, so it may only be read from here on.
    if (_started) return;
    _started = true;
    _resolve();
  }

  Future<void> _resolve() async {
    final ledger = LedgerScope.of(context);
    try {
      final id = widget.bookId ?? await advancesBookId(ledger);
      if (!mounted) return;
      setState(() {
        _bookId = id;
        // Built once: rebuilding the stream on every frame would resubscribe
        // and replay the projection needlessly.
        _mine = ledger.watchMyAdvances();
        _given = ledger.watchOpenAdvances(id);
        // The sheets open over this list rather than reading for themselves:
        // one live source for the screen and both its sheets.
        _accounts = ledger.watchAccounts(id);
      });
    } catch (e) {
      if (mounted) setState(() => _resolveError = e);
    }
  }

  void _retry() {
    setState(() {
      _resolveError = null;
      _bookId = null;
    });
    _resolve();
  }

  Future<void> _open(
    AdvanceView advance,
    AdvanceSheetMode mode,
    List<AccountBalance> accounts,
  ) => showAdvanceEntrySheet(
    context,
    advance: advance,
    mode: mode,
    accounts: accounts,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.advancesTitle)),
      body: SafeArea(
        child: _resolveError != null
            ? _ErrorState(text: l10n.advancesError, onRetry: _retry)
            : _bookId == null
            ? _Skeleton(label: l10n.advancesSkeleton)
            : _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<AdvanceView>>(
      stream: _mine,
      builder: (context, mine) => StreamBuilder<List<AdvanceView>>(
        stream: _given,
        builder: (context, given) => StreamBuilder<List<AccountBalance>>(
          stream: _accounts,
          builder: (context, accounts) {
            if (mine.hasError || given.hasError || accounts.hasError) {
              return _ErrorState(text: l10n.advancesError, onRetry: _retry);
            }
            final held = mine.data;
            final out = given.data;
            final chart = accounts.data;
            if (held == null || out == null || chart == null) {
              return _Skeleton(label: l10n.advancesSkeleton);
            }
            if (held.isEmpty && out.isEmpty) return const _EmptyState();
            return ListView(
              padding: const EdgeInsets.only(bottom: RkSpace.s8),
              children: [
                _SectionHeader(l10n.advancesMineTitle),
                if (held.isEmpty)
                  _SectionEmpty(l10n.advancesMineEmpty)
                else
                  for (final a in held)
                    AdvanceCard(
                      advance: a,
                      onAddSpend: () => _open(a, AdvanceSheetMode.spend, chart),
                      onReturn: () =>
                          _open(a, AdvanceSheetMode.returnRemaining, chart),
                    ),
                _SectionHeader(l10n.advancesGivenTitle),
                if (out.isEmpty)
                  _SectionEmpty(l10n.advancesGivenEmpty)
                else
                  for (final a in out)
                    AdvanceAgedRow(advance: a, canApprove: widget.canApprove),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RkSpace.gutter,
      RkSpace.s5,
      RkSpace.gutter,
      RkSpace.s3,
    ),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: RkStatusColors.of(context).muted),
    ),
  );
}

/// The state this screen is in most of the time (07 §1 rule 12). It carries no
/// call to action on purpose: the one next action would be S5.1 *Request an
/// advance*, which this lane does not build, and 07 §1 rule 6 forbids offering
/// a door that leads nowhere. The slot is reserved for it.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: RkSpace.s8),
          Text(l10n.advancesEmptyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.advancesEmptyBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RkStatusColors.of(context).muted,
            ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: RkSpace.s8),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RkSpace.s3),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.advancesRetry)),
        ],
      ),
    );
  }
}

/// The ruled skeleton of 11 §4.5: true row pitch, no shimmer, announced as a
/// live region so a screen reader is told the screen is filling.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      liveRegion: true,
      child: ListView(
        padding: const EdgeInsets.all(RkSpace.gutter),
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s4),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: RkSpace.s3,
                      color: status.skeletonLabel,
                    ),
                  ),
                  const SizedBox(width: RkSpace.s4),
                  Expanded(
                    child: Container(
                      height: RkSpace.s3,
                      color: status.skeletonAmount,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
