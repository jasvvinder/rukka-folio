// S3 Ledger index (07 §6, 13 §3.2): A–Z list of every A/C in scope with live
// signed balance, search-as-header, filter chips (All · Parties · Categories
// · Money · System). Row tap → S4 A/C statement; `+ New A/C` → S3.1 quick-add
// sheet. Never truly empty (a seeded tree always exists) — a search miss is
// the only "empty" state, and it offers the create row (07 §6).
//
// ⚠️ SPEC: the design calls for a *sticky* alphabet rail; this build groups
// rows under a plain (non-pinned) letter header instead — logged as an open
// item, not a silent simplification.
import 'dart:math' as math;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../ledger_book.dart';
import '../widgets/opening_prompt.dart';
import '../widgets/text_metrics.dart';
import 's3_1_quick_add_sheet.dart';

/// Filter chips over the index (07 §6).
enum LedgerFilter { all, parties, categories, money, system }

bool _matchesFilter(AccountBalance a, LedgerFilter f) => switch (f) {
  LedgerFilter.all => true,
  LedgerFilter.parties => a.account.accountClass == AccountClass.party,
  LedgerFilter.categories =>
    a.account.accountClass == AccountClass.categoryIncome ||
        a.account.accountClass == AccountClass.categoryExpense,
  LedgerFilter.money => a.account.accountClass == AccountClass.money,
  LedgerFilter.system =>
    a.account.accountClass == AccountClass.equitySystem ||
        a.account.accountClass == AccountClass.advance ||
        a.account.accountClass == AccountClass.partner,
};

class LedgerIndexScreen extends StatefulWidget {
  const LedgerIndexScreen({
    super.key,
    this.bookId,
    this.onOpenAccount,
    this.onOpenSearch,
  });

  /// Explicit book; when null the solo book is resolved ([soloBookId]).
  final String? bookId;

  final void Function(String accountId)? onOpenAccount;
  final VoidCallback? onOpenSearch;

  @override
  State<LedgerIndexScreen> createState() => _LedgerIndexScreenState();
}

class _LedgerIndexScreenState extends State<LedgerIndexScreen> {
  LedgerFilter _filter = LedgerFilter.all;
  String _query = '';
  String? _bookId;
  Object? _resolveError;

  bool _resolveStarted = false;

  /// The accounts still waiting for their opening answer (ADR 2026-10-07b §1
  /// 🔒), memoised per book so a rebuild does not resubscribe.
  Stream<Set<String>>? _unanswered;
  String? _unansweredBook;

  Stream<Set<String>> _unansweredStream(LocalLedger ledger, String bookId) {
    if (_unansweredBook != bookId) {
      _unansweredBook = bookId;
      _unanswered = ledger.watchOpeningUnanswered(bookId);
    }
    return _unanswered!;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope is an InheritedWidget, so it may only be read from here on —
    // reading it in initState() throws, and a caught throw would pin the
    // screen to its error state forever.
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
    setState(() => _resolveError = null);
    _resolveBook();
  }

  Future<void> _openQuickAdd(String bookId) async {
    // watchAccounts() is a live stream, so the new row appears on its own —
    // nothing to refresh here.
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
      appBar: AppBar(
        title: Text(l10n.ledgerTitle),
        // S21 (07 §25, 13 §3.2: reached from S3). The header field above the
        // list filters this index in place; the button opens the search that
        // also reaches parties' and entries' notes.
        actions: [
          if (widget.onOpenSearch != null)
            IconButton(
              tooltip: l10n.ledgerSearchTitle,
              icon: const Icon(Icons.search),
              onPressed: widget.onOpenSearch,
            ),
        ],
      ),
      body: SafeArea(
        child: _resolveError != null
            ? _ErrorState(text: l10n.ledgerListError, onRetry: _retry)
            : _bookId == null
            ? _Skeleton(label: l10n.ledgerListSkeleton)
            : _body(context, _bookId!),
      ),
      floatingActionButton: _bookId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openQuickAdd(_bookId!),
              icon: const Icon(Icons.add),
              label: Text(l10n.ledgerNewAccount),
            ),
    );
  }

  Widget _body(BuildContext context, String bookId) {
    final l10n = AppLocalizations.of(context);
    final ledger = LedgerScope.of(context);
    return StreamBuilder<List<AccountBalance>>(
      stream: ledger.watchAccounts(bookId),
      builder: (context, snap) {
        if (snap.hasError) {
          return _ErrorState(
            text: l10n.ledgerListError,
            onRetry: () => setState(() {}),
          );
        }
        final rows = snap.data;
        if (rows == null) return _Skeleton(label: l10n.ledgerListSkeleton);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s2,
                RkSpace.gutter,
                0,
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: l10n.ledgerSearchHint,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(RkRadius.md),
                  ),
                ),
              ),
            ),
            // The strip takes its height from its chips, so a label is never
            // cut at any text size (13 §8; 07 §1 rule 9). It was a fixed
            // 40 px box with 8 px padding, which left 24 px for a chip.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: RkSpace.gutter,
                vertical: RkSpace.s2,
              ),
              child: Row(
                children: [
                  for (final f in LedgerFilter.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        end: RkSpace.s2,
                      ),
                      child: ChoiceChip(
                        label: Text(_filterLabel(l10n, f)),
                        // c7 *Ledger index*: the selected pill carries no
                        // tick; selection is said by its fill and by
                        // Semantics' selected state.
                        showCheckmark: false,
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<Set<String>>(
                stream: _unansweredStream(ledger, bookId),
                builder: (context, unanswered) =>
                    _list(context, rows, unanswered.data ?? const <String>{}),
              ),
            ),
          ],
        );
      },
    );
  }

  String _filterLabel(AppLocalizations l10n, LedgerFilter f) => switch (f) {
    LedgerFilter.all => l10n.ledgerFilterAll,
    LedgerFilter.parties => l10n.ledgerFilterParties,
    LedgerFilter.categories => l10n.ledgerFilterCategories,
    LedgerFilter.money => l10n.ledgerFilterMoney,
    LedgerFilter.system => l10n.ledgerFilterSystem,
  };

  Widget _list(
    BuildContext context,
    List<AccountBalance> rows,
    Set<String> unansweredOpening,
  ) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final q = _query.trim().toLowerCase();
    final filtered =
        rows
            .where((a) => !a.archived)
            .where((a) => _matchesFilter(a, _filter))
            .where((a) => q.isEmpty || a.account.name.toLowerCase().contains(q))
            .toList()
          ..sort(
            (a, b) => a.account.name.toLowerCase().compareTo(
              b.account.name.toLowerCase(),
            ),
          );

    if (filtered.isEmpty) {
      return _SearchMiss(
        query: _query,
        onCreate: _bookId == null ? null : () => _openQuickAdd(_bookId!),
      );
    }

    // 07 §6: a *sticky* alphabet rail — each letter's header stays pinned
    // while its own accounts are on screen, so the A-Z position is never
    // lost mid-scroll.
    final groups = <String, List<AccountBalance>>{};
    final letters = <String>[];
    for (final row in filtered) {
      final letter = row.account.name.isEmpty
          ? '#'
          : row.account.name[0].toUpperCase();
      if (!groups.containsKey(letter)) {
        groups[letter] = [];
        letters.add(letter);
      }
      groups[letter]!.add(row);
    }

    // Name beside figure, or name above it — measured, never a text-scale
    // threshold (07 §1; see `widgets/text_metrics.dart`). An account name is
    // the user's own word and may not be shortened, and a balance may not be
    // shrunk to fit, so where the two cannot share a line the figure takes
    // the line below. One decision for the whole list, so the column does not
    // come and go row by row.
    final nameStyle = text.bodyLarge;
    final classStyle = text.bodySmall;
    final figureStyle = (text.labelLarge ?? RkType.amountRow).copyWith(
      fontFeatures: RkType.tabular,
    );
    var words = 0.0;
    var figures = 0.0;
    for (final row in filtered) {
      words = math.max(
        words,
        longestWordWidth(context, row.account.name, nameStyle),
      );
      words = math.max(
        words,
        longestWordWidth(
          context,
          _classLabel(l10n, row.account.accountClass),
          classStyle,
        ),
      );
      if (unansweredOpening.contains(row.account.id)) {
        // The marker's icon and gap sit before its first word.
        words = math.max(
          words,
          longestWordWidth(context, l10n.ledgerOpeningPromptTitle, classStyle) +
              (classStyle?.fontSize ?? RkSpace.s4) *
                  MediaQuery.textScalerOf(context).scale(1) +
              RkSpace.s1,
        );
      }
      figures = math.max(
        figures,
        textRunWidth(
          context,
          professionalFigure(context, row.balancePaise),
          figureStyle,
        ),
      );
    }
    // The line a `ListTile` has inside its own padding, less the gap the tile
    // keeps between its text and its trailing widget.
    final line =
        MediaQuery.sizeOf(context).width - RkSpace.gutter * 2 - RkSpace.s4;
    final beside = words + figures <= line;

    final band = _LetterHeader.extentFor(context);
    return CustomScrollView(
      slivers: [
        for (final letter in letters)
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _LetterHeader(letter: letter, extent: band),
              ),
              SliverList.builder(
                itemCount: groups[letter]!.length,
                itemBuilder: (context, i) {
                  final row = groups[letter]![i];
                  // S3 is a ledger — a professional surface — so the true
                  // side is written plainly after the figure (*₹2,450 Cr*):
                  // ADR 2026-10-10b §4 🔒, 02 §10. The tint by side is never
                  // the only signal (07 §1 rule 3 🔒).
                  final money = MoneyText(
                    row.balancePaise,
                    vocabulary: Vocabulary.professional,
                    showDirection: true,
                    favour: row.balancePaise >= 0
                        ? Favour.favourable
                        : Favour.unfavourable,
                  );
                  final kind = Text(
                    _classLabel(l10n, row.account.accountClass),
                    style: text.bodySmall,
                  );
                  // ADR 2026-10-07b §1 🔒: a quiet line under the name until
                  // the A/C's opening balance is answered — icon and words in
                  // ink, never colour alone (07 §1 rule 3 🔒).
                  final classLabel = unansweredOpening.contains(row.account.id)
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [kind, const OpeningMarker()],
                        )
                      : kind;
                  return ListTile(
                    minTileHeight: RkSpace.rowMinHeight,
                    title: Text(
                      row.account.name,
                      style: text.bodyLarge,
                      // 01 §1 rule 9 / design-system §3.1 rule 1: user-typed
                      // text carries its own language tag for the screen
                      // reader. Names are free text; we don't know the
                      // script, so this leaves the ambient locale — logged in
                      // the lane report.
                    ),
                    subtitle: beside
                        ? classLabel
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              classLabel,
                              const SizedBox(height: RkSpace.s1),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: money,
                              ),
                            ],
                          ),
                    trailing: beside ? money : null,
                    onTap: () => widget.onOpenAccount?.call(row.account.id),
                  );
                },
              ),
            ],
          ),
      ],
    );
  }

  String _classLabel(AppLocalizations l10n, AccountClass c) => switch (c) {
    AccountClass.money => l10n.ledgerFilterMoney,
    AccountClass.party => l10n.ledgerFilterParties,
    AccountClass.categoryIncome ||
    AccountClass.categoryExpense => l10n.ledgerFilterCategories,
    AccountClass.advance ||
    AccountClass.partner ||
    AccountClass.equitySystem => l10n.ledgerFilterSystem,
  };
}

class _SearchMiss extends StatelessWidget {
  const _SearchMiss({required this.query, this.onCreate});

  final String query;

  /// Opens the quick-add sheet (S3.1). 07 §6: the search-miss state *is* the
  /// create row — a miss must never be a dead end (07 §1 rule 6).
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            query.isEmpty
                ? l10n.ledgerListEmpty
                : l10n.ledgerListEmptyQuery(query),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: RkSpace.s3),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              minTileHeight: RkSpace.rowMinHeight,
              leading: const Icon(Icons.add),
              title: Text(l10n.ledgerNewAccount),
              subtitle: query.isEmpty ? null : Text(query),
              onTap: onCreate,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: RkSpace.s3),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: RkSpace.s4),
            FilledButton(onPressed: onRetry, child: Text(l10n.ledgerListRetry)),
          ],
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      child: ListView.builder(
        padding: const EdgeInsets.all(RkSpace.gutter),
        itemCount: 6,
        itemBuilder: (context, i) => Container(
          height: RkSpace.rowMinHeight,
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: i.isEven
                  ? RkMotion.skeletonLabelWidthMax
                  : RkMotion.skeletonLabelWidthMin,
              child: Container(
                height: RkSpace.s3,
                decoration: BoxDecoration(
                  color: status.skeletonLabel,
                  borderRadius: BorderRadius.circular(RkRadius.sm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pinned letter of the alphabet rail (07 §6). Opaque, so the rows it
/// pins over do not read through it, and sized in text so it still fits its
/// own letter at 200% — [extent] is measured from the letter's own line at
/// the reader's text scale (it was a fixed 24 px, which cut the letter to
/// half its 46 px line at 200 %).
class _LetterHeader extends SliverPersistentHeaderDelegate {
  const _LetterHeader({required this.letter, required this.extent});

  final String letter;

  /// The band's height: the letter's line plus the band's own padding.
  final double extent;

  /// The band for [context]'s text style and scale, never under the token
  /// minimum the band was drawn at.
  static double extentFor(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge ?? RkType.amountRow;
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final line = painter.height;
    painter.dispose();
    return math.max(RkSpace.s6, line + RkSpace.s2);
  }

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final status = RkStatusColors.of(context);
    return Container(
      alignment: Alignment.centerLeft,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: status.muted),
      ),
    );
  }

  @override
  bool shouldRebuild(_LetterHeader old) =>
      old.letter != letter || old.extent != extent;
}
