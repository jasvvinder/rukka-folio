// S21 Search (07 §25 🔒 ⟦tests: F1-07-35⟧, 13 §3.2 row S21): one field across
// accounts, parties and notes in scope; results are P1 rows (13 §4.1), grouped
// by type — parties, then other accounts, then entries whose note matched
// (DESIGN-PACK S21: names first, because a name is usually what is wanted).
// Reached from S3 (the app-bar search button) and, per 13, from S1.
//
// States (13 §4.3): loading (ruled skeleton), error with retry, empty query
// (the one next action: type), no results (07 §6: a miss offers the create
// row, as S3's search miss does — never a dead end, 07 §1), results. Offline
// is not a state here: the index is the local projection (13 §8). Read-only
// is enforced by the S3.1 sheet itself (ADR 2026-09-24b §13, F1-24b-7).
//
// ⚠️ SPEC: DESIGN-PACK S21 / canvas 7 S21 also draw (a) an *Entries* group —
// the entries of a matched khata — and (b) *recent searches* kept on this
// phone before typing. Neither is in 07 §25 🔒 or 13 §3.2, and (b) stores the
// user's typed text, which wants its own ruling; both are left out and logged
// as open items rather than invented.
//
// ⚠️ SPEC: P1 says "no date column — dates group". Note hits come from many
// days and are ordered newest first; the date sits in the row's second line
// (as canvas 7 S21 draws it), not in a column and not as a group header.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../../../shared/widgets/rk_states.dart';
import '../ledger_book.dart';
import '../search_index.dart';
import '../widgets/text_metrics.dart';
import 's3_1_quick_add_sheet.dart';

/// S21 — search across the accounts, parties and notes of the book in scope.
class LedgerSearchScreen extends StatefulWidget {
  /// Creates the screen.
  const LedgerSearchScreen({
    super.key,
    this.bookId,
    this.initialQuery = '',
    this.onOpenAccount,
    this.onOpenEntry,
  });

  /// Explicit book; when null the solo book is resolved ([soloBookId]),
  /// exactly as S3 resolves its scope.
  final String? bookId;

  /// Text the field opens with.
  final String initialQuery;

  /// An account or party row → S4 A/C statement.
  final void Function(String accountId)? onOpenAccount;

  /// A note row → S4.1 entry detail.
  final void Function(String entryId)? onOpenEntry;

  @override
  State<LedgerSearchScreen> createState() => _LedgerSearchScreenState();
}

class _LedgerSearchScreenState extends State<LedgerSearchScreen> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initialQuery,
  );
  String? _bookId;
  Object? _resolveError;
  Stream<LedgerSearchIndex>? _index;
  bool _resolveStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // LedgerScope is an InheritedWidget: readable from here, not initState.
    if (_resolveStarted) return;
    _resolveStarted = true;
    _resolveBook();
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _resolveBook() async {
    final ledger = LedgerScope.of(context);
    try {
      final id = widget.bookId ?? await soloBookId(ledger);
      if (!mounted) return;
      setState(() {
        _bookId = id;
        _index = watchSearchIndex(ledger, id);
      });
    } catch (e) {
      if (mounted) setState(() => _resolveError = e);
    }
  }

  void _retry() {
    setState(() {
      _resolveError = null;
      _bookId = null;
      _index = null;
    });
    _resolveBook();
  }

  Future<void> _openQuickAdd() async {
    final bookId = _bookId;
    if (bookId == null) return;
    // The index rebuilds on the projection change, so a new account appears
    // in the results by itself.
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => QuickAddSheet(bookId: bookId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ledgerSearchTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s2,
                RkSpace.gutter,
                RkSpace.s2,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final hintStyle = Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      );
                  // Measured, never thresholded (text_metrics.dart): the
                  // search glyph keeps its 48 px slot only while the hint's
                  // longest word still fits beside it. At 200 % on a 360 px
                  // phone `accounts,` alone can outgrow what is left; the
                  // word wins and the glyph goes — the app bar already says
                  // *Search*. The reserve (slot + both content paddings) is
                  // a few px more than the decorator takes, so this errs
                  // towards dropping the glyph, never towards a cut word.
                  final room =
                      constraints.maxWidth -
                      kMinInteractiveDimension -
                      RkSpace.s3 * 2;
                  final withGlyph =
                      longestWordWidth(
                        context,
                        l10n.ledgerSearchFieldHint,
                        hintStyle,
                      ) <=
                      room;
                  return TextField(
                    controller: _field,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: withGlyph ? const Icon(Icons.search) : null,
                      // A widget, not `hintText`: TextField caps `hintText`
                      // at its own one line with an ellipsis, which at 200 %
                      // cut the hint to its first word on both F1 phones
                      // (13 §8: 200 % without truncation). This hint wraps,
                      // and the field grows to hold it. Not kept laid out
                      // (invisible) once the reader types, so the clear
                      // button never squeezes a hint nobody can see.
                      hint: Text(l10n.ledgerSearchFieldHint, style: hintStyle),
                      maintainHintSize: false,
                      isDense: true,
                      suffixIcon: _field.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: l10n.ledgerSearchClear,
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(_field.clear),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(RkRadius.md),
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = RkErrorState(
      text: l10n.ledgerSearchError,
      retryLabel: l10n.ledgerListRetry,
      onRetry: _retry,
    );
    if (_resolveError != null) return error;
    final index = _index;
    if (index == null) return RkSkeleton(label: l10n.ledgerSearchSkeleton);
    return StreamBuilder<LedgerSearchIndex>(
      stream: index,
      builder: (context, snap) {
        if (snap.hasError) return error;
        final data = snap.data;
        if (data == null) return RkSkeleton(label: l10n.ledgerSearchSkeleton);
        final query = _field.text;
        if (normaliseQuery(query).isEmpty) return const _EmptyQuery();
        final results = searchLedger(data, query);
        if (results.isEmpty) {
          return _NoResults(query: query.trim(), onCreate: _openQuickAdd);
        }
        return _Results(
          results: results,
          chart: data.chart,
          onOpenAccount: widget.onOpenAccount,
          onOpenEntry: widget.onOpenEntry,
        );
      },
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.chart,
    this.onOpenAccount,
    this.onOpenEntry,
  });

  final LedgerSearchResults results;
  final Map<String, Account> chart;
  final void Function(String accountId)? onOpenAccount;
  final void Function(String entryId)? onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s6),
      children: [
        if (results.parties.isNotEmpty) ...[
          _SectionHeader(text: l10n.ledgerSearchSectionParties),
          for (final a in results.parties)
            _AccountRow(row: a, onOpen: onOpenAccount),
        ],
        if (results.accounts.isNotEmpty) ...[
          _SectionHeader(text: l10n.ledgerSearchSectionAccounts),
          for (final a in results.accounts)
            _AccountRow(row: a, onOpen: onOpenAccount),
        ],
        if (results.notes.isNotEmpty) ...[
          _SectionHeader(text: l10n.ledgerSearchSectionNotes),
          for (final n in results.notes)
            _NoteRow(hit: n, chart: chart, onOpen: onOpenEntry),
        ],
      ],
    );
  }
}

/// A result group's label. Announced as a header, so a screen reader can jump
/// between the groups.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s4,
          RkSpace.gutter,
          RkSpace.s1,
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: status.muted),
        ),
      ),
    );
  }
}

IconData _classIcon(AccountClass c) => switch (c) {
  AccountClass.party => Icons.person_outline,
  AccountClass.money => Icons.account_balance_wallet_outlined,
  AccountClass.categoryIncome ||
  AccountClass.categoryExpense => Icons.category_outlined,
  AccountClass.advance ||
  AccountClass.partner ||
  AccountClass.equitySystem => Icons.account_tree_outlined,
};

String _classLabel(AppLocalizations l10n, AccountClass c) => switch (c) {
  AccountClass.money => l10n.ledgerFilterMoney,
  AccountClass.party => l10n.ledgerFilterParties,
  AccountClass.categoryIncome ||
  AccountClass.categoryExpense => l10n.ledgerFilterCategories,
  AccountClass.advance ||
  AccountClass.partner ||
  AccountClass.equitySystem => l10n.ledgerFilterSystem,
};

/// An account or party hit: the khata's name, its class in words, and its
/// live balance with its Dr/Cr side word (the figure S3 measures, 07 §6).
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.row, this.onOpen});

  final AccountBalance row;
  final void Function(String accountId)? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final account = row.account;
    return RkLabelAmountRow(
      leading: Icon(
        _classIcon(account.accountClass),
        size: 20,
        color: status.muted,
      ),
      label: Text(account.name, style: text.bodyLarge),
      // A party sits under the *Parties* header already; saying it again on
      // the row is noise. The other group mixes money, categories and system
      // accounts, so there the class in words is what tells them apart.
      meta: account.accountClass == AccountClass.party
          ? null
          : Text(
              _classLabel(l10n, account.accountClass),
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
      // The side word (Dr/Cr) is what says who owes whom; the tint alone
      // never does (07 §1 rule 3 🔒, 13 §8), and MoneyText's label then
      // announces it to a screen reader too. Canvas 7 S21 draws `₹3,600 Cr`.
      amount: MoneyText(
        row.balancePaise,
        vocabulary: Vocabulary.professional,
        favour: row.balancePaise >= 0 ? Favour.favourable : Favour.unfavourable,
        showDirection: true,
      ),
      onTap: onOpen == null ? null : () => onOpen!(account.id),
    );
  }
}

/// A note hit, as a P1 row (13 §4.1): the counter-account label, the user's
/// own words with the date, the status when the review flag is open, and the
/// amount with its direction word so colour is never alone (07 §1).
class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.hit, required this.chart, this.onOpen});

  final NoteHit hit;
  final Map<String, Account> chart;
  final void Function(String entryId)? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final line = amountLineOf(hit, chart);
    final others = [
      for (final l in hit.lines)
        if (l.accountId != line?.accountId)
          chart[l.accountId]?.name ?? l.accountId,
    ];
    final label = others.isEmpty
        ? chart[line?.accountId]?.name ?? ''
        : others.join(', ');
    final date = formatListDate(
      hit.date,
      strings: l10n,
      now: RkScope.of(context).now(),
    );
    return RkLabelAmountRow(
      leading: Icon(Icons.notes_outlined, size: 20, color: status.muted),
      label: Text(label, style: text.bodyLarge),
      meta: Wrap(
        spacing: RkSpace.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.ledgerSearchNoteMeta(date, hit.note),
            style: text.bodySmall?.copyWith(color: status.muted),
          ),
          if (hit.underReview)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 14, color: status.pending),
                const SizedBox(width: RkSpace.s1),
                Text(
                  l10n.ledgerSearchUnderReview,
                  style: text.bodySmall?.copyWith(color: status.pending),
                ),
              ],
            ),
        ],
      ),
      amount: MoneyText(line?.amountPaise ?? 0, showDirection: true),
      onTap: onOpen == null ? null : () => onOpen!(hit.entryId),
    );
  }
}

/// Nothing typed yet: the one next action is to type (13 §8 empty states).
class _EmptyQuery extends StatelessWidget {
  const _EmptyQuery();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.search, size: 20, color: status.muted),
            const SizedBox(width: RkSpace.s3),
            Expanded(
              child: Text(
                l10n.ledgerSearchEmptyQuery,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: status.muted),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A miss. 07 §6: the search-miss state *is* the create row, so the miss is
/// never a dead end (07 §1) — the same shape as S3's.
class _NoResults extends StatelessWidget {
  const _NoResults({required this.query, required this.onCreate});

  final String query;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        Text(
          l10n.ledgerSearchNoResults(query),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: RkSpace.s3),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            minTileHeight: RkSpace.rowMinHeight,
            leading: const Icon(Icons.add),
            title: Text(l10n.ledgerNewAccount),
            subtitle: Text(query),
            onTap: onCreate,
          ),
        ),
      ],
    );
  }
}
