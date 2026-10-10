// S1.1 Position line drill-down (07 §4 "every line drills into its list";
// 13 §3.2 row S1.1): one screen parameterised by [PositionLine] that shows
// the accounts standing behind a Home position row, with the line's total,
// each row tapping through to that account's A/C statement (S4).
//
// Consumer surface (02 §10 🔒, CLAUDE.md rule 9): signed amounts and plain
// words, never Dr/Cr — those start at the statement. Integer paise
// throughout; colour is never alone (the sign and the label carry it too).
//
// The membership rule of every line is [rowsFor], which mirrors
// `LocalLedger.watchPosition` exactly (02 §9) rather than inventing a second
// classification — if the two ever drift, the position card and its own
// drill-down would disagree, which is the one thing this screen must not do.
//
// The two party lines are 07 §7 🔒's drill-downs: *party list sorted by
// balance, ageing chips (`> 30 days` amber, `> 90 days` red — localised per
// 01 §2.0), total header*. Layout follows canvas c7 *S1.1 / You will give ·
// drill-down*: the total header (caption · line total · how many), then flat
// rows divided by hairlines, the chip under each name, a chevron into S4.
//
// ⚠️ SPEC (desk 193 (i), lane F193H open): no doc defines how a *party*
// balance is aged — 02 §7 ages advances (days since the oldest unsettled
// debit, FIFO), 02 §9 names "drill-down and ageing" for You-will-get/give
// without a rule, and neither packages/data nor core_ledger exposes a
// per-party age. The chips therefore stand behind [PositionDrilldownScreen.
// ageDaysOf], which production leaves null: no age known, no chip, no
// "oldest", no footnote. Applying 02 §7's FIFO rule to parties would be
// inventing behaviour (CLAUDE.md rule 11); the owner rules, then a source
// fills the seam.
import 'dart:math' as math;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../ledger/ledger_book.dart';
import '../home_paths.dart';
import '../../../shared/widgets/rk_ruled_card.dart' show RkLabelAmountRow;
import '../../../shared/widgets/rk_states.dart';

/// The accounts behind [line], in the order the position card reads them
/// (creation order — 02 §9) — except the two party lines, which 07 §7 🔒
/// sorts *by balance*: largest first, creation order breaking ties.
/// [accountId], when given, narrows the list to that one account: a Home bank
/// row names its own account.
///
/// ⚠️ SPEC: 07 §7 does not say which way the balance sort runs; largest first
/// is the reading the canvas's header ("You owe, in all") and the Home
/// position row (the biggest party named first) both suggest.
///
/// Pure, so the rule can be tested without a database.
List<AccountBalance> rowsFor(
  List<AccountBalance> accounts,
  PositionLine line, {
  String? accountId,
}) {
  final ordered = [
    for (final a in accounts)
      if (!a.archived) a,
  ]..sort((a, b) => a.account.createdOrder.compareTo(b.account.createdOrder));
  bool keep(AccountBalance r) {
    final a = r.account;
    switch (line) {
      case PositionLine.cash:
        return a.accountClass == AccountClass.money &&
            a.subtype == MoneySubtype.cash;
      case PositionLine.bank:
        return a.accountClass == AccountClass.money &&
            a.subtype != MoneySubtype.cash &&
            a.subtype != MoneySubtype.cashCollection;
      case PositionLine.youWillGet:
        return a.accountClass == AccountClass.party && r.balancePaise > 0;
      case PositionLine.youWillGive:
        return a.accountClass == AccountClass.party && r.balancePaise < 0;
      case PositionLine.advancesOut:
        return a.accountClass == AccountClass.advance && r.balancePaise != 0;
      case PositionLine.inTransit:
        return a.accountClass == AccountClass.equitySystem &&
            a.systemRole == SystemRole.dueToFrom;
    }
  }

  final rows = [
    for (final r in ordered)
      if (keep(r) && (accountId == null || r.account.id == accountId)) r,
  ];
  if (line.isParty) {
    // Equal balances keep their creation order: `rows` is creation-ordered,
    // and List.sort is not stable, so the order breaks the tie explicitly.
    rows.sort((a, b) {
      final byBalance = b.balancePaise.abs().compareTo(a.balancePaise.abs());
      return byBalance != 0
          ? byBalance
          : a.account.createdOrder.compareTo(b.account.createdOrder);
    });
  }
  return rows;
}

/// 07 §7 🔒's two ageing chips. Over 30 days is amber, over 90 days red;
/// a balance 30 days old or newer — or one whose age is not known — has none.
enum AgeingBucket {
  /// No chip.
  none,

  /// `> 30 days` (01 §2.0 🔒), amber.
  over30,

  /// `> 90 days` (01 §2.0 🔒), red.
  over90,
}

/// The chip for a balance [days] old; null days → [AgeingBucket.none].
AgeingBucket ageingBucketOf(int? days) {
  if (days == null) return AgeingBucket.none;
  if (days > 90) return AgeingBucket.over90;
  if (days > 30) return AgeingBucket.over30;
  return AgeingBucket.none;
}

extension on PositionLine {
  bool get isParty =>
      this == PositionLine.youWillGet || this == PositionLine.youWillGive;
}

/// The position row's own label — the S1.1 app-bar title (13 §3.2 row S1.1).
String positionLineLabel(AppLocalizations l10n, PositionLine line) =>
    switch (line) {
      PositionLine.cash => l10n.homePositionCash,
      PositionLine.bank => l10n.homePositionTitle,
      PositionLine.youWillGet => l10n.homePositionYouWillGet,
      PositionLine.youWillGive => l10n.homePositionYouWillGive,
      PositionLine.advancesOut => l10n.homePositionAdvancesOut,
      PositionLine.inTransit => l10n.homePositionInTransit,
    };

/// S1.1 — the list behind one Home position row.
class PositionDrilldownScreen extends StatefulWidget {
  /// Creates the screen.
  const PositionDrilldownScreen({
    super.key,
    required this.line,
    this.accountId,
    this.bookId,
    this.onOpenAccount,
    this.onRecordEntry,
    this.ageDaysOf,
  });

  /// Which position row was tapped.
  final PositionLine line;

  /// Narrows the list to one account (a Home bank row).
  final String? accountId;

  /// Explicit book; when null the solo book is resolved ([soloBookId]).
  final String? bookId;

  /// Opens an account's A/C statement (S4).
  final void Function(String accountId)? onOpenAccount;

  /// The empty state's one next action (13 §8): record an entry.
  final VoidCallback? onRecordEntry;

  /// How many days a party's balance has stood, or null when not known —
  /// the seam the ageing chips read (07 §7 🔒). Null (the shipped default)
  /// draws no chip: no doc yet defines how a party balance is aged (⚠️ SPEC
  /// in the file header).
  final int? Function(AccountBalance row)? ageDaysOf;

  @override
  State<PositionDrilldownScreen> createState() =>
      _PositionDrilldownScreenState();
}

class _PositionDrilldownScreenState extends State<PositionDrilldownScreen> {
  String? _bookId;
  Object? _resolveError;
  bool _resolveStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // LedgerScope is inherited: readable from here on, never in initState().
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
    });
    _resolveBook();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.homeDrilldownTitle(positionLineLabel(l10n, widget.line)),
        ),
      ),
      body: SafeArea(
        child: _resolveError != null
            ? RkErrorState(
                text: l10n.homeDrilldownError,
                retryLabel: l10n.homeRetry,
                onRetry: _retry,
              )
            : _bookId == null
            ? RkSkeleton(label: l10n.homeDrilldownSkeleton)
            : _body(context, _bookId!),
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
          return RkErrorState(
            text: l10n.homeDrilldownError,
            retryLabel: l10n.homeRetry,
            onRetry: () => setState(() {}),
          );
        }
        final all = snap.data;
        if (all == null) {
          return RkSkeleton(label: l10n.homeDrilldownSkeleton);
        }
        final rows = rowsFor(all, widget.line, accountId: widget.accountId);
        if (rows.isEmpty) return _empty(context);
        final total = rows.fold<int>(0, (s, r) => s + r.balancePaise);
        final ages = {
          for (final r in rows) r.account.id: widget.ageDaysOf?.call(r),
        };
        final known = [...ages.values.nonNulls];
        final oldest = known.isEmpty ? null : known.reduce(math.max);
        final anyChip = ages.values.any(
          (d) => ageingBucketOf(d) != AgeingBucket.none,
        );
        final status = RkStatusColors.of(context);
        return ListView(
          padding: const EdgeInsets.only(bottom: RkSpace.s10),
          children: [
            _TotalHeader(
              line: widget.line,
              totalPaise: total,
              count: rows.length,
              oldestDays: oldest,
            ),
            const SizedBox(height: RkSpace.s2),
            for (final (i, r) in rows.indexed) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: RkSpace.gutter,
                  endIndent: RkSpace.gutter,
                  color: status.hairline,
                ),
              RkLabelAmountRow(
                label: Text(
                  r.account.name,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                meta: _AgeingChip.of(ageingBucketOf(ages[r.account.id])),
                amount: MoneyText(r.balancePaise),
                onTap: widget.onOpenAccount == null
                    ? null
                    : () => widget.onOpenAccount!(r.account.id),
                semanticHint: widget.onOpenAccount == null
                    ? null
                    : l10n.homePositionDrill,
              ),
            ],
            if (anyChip)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.gutter,
                  RkSpace.s6,
                  RkSpace.gutter,
                  0,
                ),
                child: Text(
                  l10n.homeDrilldownAgeingNote,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: status.muted),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Empty, with the one next action (13 §4.3, 13 §8) — never a dead end.
  Widget _empty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        Text(
          l10n.homeDrilldownEmpty,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: status.muted),
        ),
        if (widget.onRecordEntry != null) ...[
          const SizedBox(height: RkSpace.s4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: widget.onRecordEntry,
              icon: const Icon(Icons.add),
              label: Text(l10n.homeDrilldownEmptyAction),
            ),
          ),
        ],
      ],
    );
  }
}

/// The total header (07 §7 🔒; canvas c7 S1.1): a caption naming the line,
/// the line's total — the same figure as the Home position row it came from
/// (02 §9) — and how many stand behind it, with the oldest age when known.
class _TotalHeader extends StatelessWidget {
  const _TotalHeader({
    required this.line,
    required this.totalPaise,
    required this.count,
    required this.oldestDays,
  });

  final PositionLine line;
  final int totalPaise;
  final int count;
  final int? oldestDays;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final theme = Theme.of(context);
    final caption = switch (line) {
      PositionLine.youWillGive => l10n.homeDrilldownHeaderYouWillGive,
      PositionLine.youWillGet => l10n.homeDrilldownHeaderYouWillGet,
      _ => l10n.homeDrilldownTotal,
    };
    // Who stands behind the line: the frame's "people and suppliers" is the
    // You-will-give list's (creditors); those who owe you are debtors —
    // people and customers (01 §2 Debtors — You will get).
    final howMany = switch (line) {
      PositionLine.youWillGive => l10n.homeDrilldownCountParties(count),
      PositionLine.youWillGet => l10n.homeDrilldownCountYouWillGet(count),
      _ => l10n.homeDrilldownCountAccounts(count),
    };
    final oldest = oldestDays;
    final meta = oldest == null
        ? howMany
        : '$howMany · ${l10n.homeDrilldownOldest(oldest)}';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: status.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s5,
          RkSpace.gutter,
          RkSpace.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The frame's small-caps caption. Uppercasing is a no-op in
            // Gurmukhi and Devanagari, which have no case.
            Text(
              caption.toUpperCase(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: status.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: RkSpace.s1),
            // Signed and tinted as every consumer amount is (07 §1 rule 3);
            // shrinks rather than lose a digit at 200 % (07 §1 rule 11).
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: MoneyText(
                totalPaise,
                style: RkType.page.copyWith(fontFeatures: RkType.tabular),
              ),
            ),
            const SizedBox(height: RkSpace.s1),
            Text(
              meta,
              style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// One 07 §7 🔒 ageing chip — outlined, its words in the tint, so the colour
/// is never the only signal (07 §1 rule 3). Shape per canvas c7 *S1.1 / You
/// will give · drill-down*: a square-cornered tag (no radius), 1 px tint
/// border, tight padding (the frame's 1/6 px on the 4pt grid: 1/2 · s1 by
/// s1 + s1/2) and a tight line; the type stays the caption role (12 px —
/// there is no 11 px role, and the tag text must stay readable at 200 %). Amber is the `warning` role; red
/// is `danger`, because the credit/debit reds colour numerals only (07 §1
/// rule 3 🔒, theme.dart) and a chip is not a numeral.
class _AgeingChip extends StatelessWidget {
  const _AgeingChip(this.bucket);

  /// The chip for [bucket], or null when it has none.
  static Widget? of(AgeingBucket bucket) =>
      bucket == AgeingBucket.none ? null : _AgeingChip(bucket);

  final AgeingBucket bucket;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final (text, tint) = switch (bucket) {
      AgeingBucket.over90 => (l10n.homeDrilldownAgeingOver90, status.danger),
      _ => (l10n.homeDrilldownAgeingOver30, status.warning),
    };
    return Padding(
      padding: const EdgeInsets.only(top: RkSpace.s1),
      child: DecoratedBox(
        // No borderRadius: the frame's tag is square (canvas c7 S1.1).
        decoration: BoxDecoration(border: Border.all(color: tint)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.s1 + RkSpace.s1 / 2,
            vertical: RkSpace.s1 / 4,
          ),
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tint, height: RkType.lineHeightTight),
          ),
        ),
      ),
    );
  }
}
