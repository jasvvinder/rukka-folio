// The Home surface's own components (07 §4; 13 §4.1 patterns P1 and P2;
// design-system §2). Home is a CONSUMER surface (02 §10 🔒, CLAUDE.md rule 9):
// *Money in / Money out*, plain words, never Dr/Cr — those live on the A/C
// statement and the trial balance the verification card links to.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../home_data.dart';
import '../home_paths.dart';
import 'home_states.dart';

/// **Total money you have** 🔒 (owner-approved, 07 §4): the one hero figure —
/// every `money` account in scope summed, overdrafts subtracted — with the
/// per-account breakdown beneath it. Neutral ink: a total is a standing
/// position, not a movement, so it carries no credit/debit colour.
class HomeHero extends StatelessWidget {
  /// Creates the hero.
  const HomeHero({
    super.key,
    required this.totalPaise,
    required this.accounts,
    this.onOpenAccount,
  });

  /// Σ every money account, overdrafts subtracted (02 §9).
  final int totalPaise;

  /// The money accounts behind it, in the order the breakdown reads.
  final List<AccountBalance> accounts;

  /// Opens one account's statement (S4).
  final void Function(String accountId)? onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s5,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeHeroLabel,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s1),
          Text(
            formatPaise(totalPaise, locale: locale),
            style: RkType.amountHero.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontFeatures: RkType.tabular,
            ),
          ),
          const SizedBox(height: RkSpace.s2),
          if (accounts.isEmpty)
            Text(
              l10n.homeHeroEmpty,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: status.muted),
            )
          else
            // A Wrap, not a Row: at 200% on a 360 px phone the breakdown has
            // to fold rather than overflow (07 §1 rule 11).
            Wrap(
              spacing: RkSpace.s3,
              runSpacing: RkSpace.s1,
              children: [
                for (final a in accounts)
                  _BreakdownChip(
                    account: a,
                    onTap: onOpenAccount == null
                        ? null
                        : () => onOpenAccount!(a.account.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BreakdownChip extends StatelessWidget {
  const _BreakdownChip({required this.account, this.onTap});

  final AccountBalance account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${account.account.name} '),
          TextSpan(
            text: formatPaise(account.balancePaise, locale: locale),
            style: TextStyle(
              fontFeatures: RkType.tabular,
              color: account.balancePaise < 0 ? status.debit : null,
            ),
          ),
        ],
      ),
      style: Theme.of(context).textTheme.bodySmall,
    );
    if (onTap == null) return text;
    return InkWell(onTap: onTap, child: text);
  }
}

/// **Books-balanced verification card** 🔒 (owner-approved, 07 §4): the status
/// pill and the difference **in plain words**, and a way through to the trial
/// balance (S8.2) where Dr and Cr totals are shown. A trust artefact, not
/// decoration — at close every member's device recomputes the same vector
/// (02 §8).
///
/// While a book is rebuilding this card is replaced by **S1.4** (07 §4, ADR
/// 2026-09-05c §3/§6); [HomeScreen.rebuildingCard] is that slot and a later
/// lane fills it (F1-07-38).
class HomeVerificationCard extends StatelessWidget {
  /// Creates the card.
  const HomeVerificationCard({
    super.key,
    required this.balanced,
    required this.differencePaise,
    this.onOpenTrialBalance,
  });

  /// True when the books balance and integrity is intact.
  final bool balanced;

  /// Σ every account balance; nil when the books balance.
  final int differencePaise;

  /// Opens the S8.2 trial balance.
  final VoidCallback? onOpenTrialBalance;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final tint = balanced ? status.credit : status.pending;
    return RkRuledCard(
      ruleColor: tint,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Colour never alone: icon + word + the sentence below (07 §1 r3).
            Wrap(
              spacing: RkSpace.s2,
              runSpacing: RkSpace.s1,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  balanced ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: tint,
                ),
                Text(
                  balanced
                      ? l10n.homeVerifyPillBalanced
                      : l10n.homeVerifyPillCheck,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: tint),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              balanced
                  ? l10n.homeVerifyBalanced
                  : l10n.homeVerifyOff(
                      formatPaise(differencePaise.abs(), locale: locale),
                    ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onOpenTrialBalance != null) ...[
              const SizedBox(height: RkSpace.s2),
              TextButton(
                onPressed: onOpenTrialBalance,
                child: Text(l10n.homeVerifyAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// **Position card** — 02 §9 exactly (07 §4), pattern P2 (13 §4.1). Every line
/// drills into its list (S1.1).
class HomePositionCard extends StatelessWidget {
  /// Creates the card.
  const HomePositionCard({
    super.key,
    required this.snapshot,
    this.onOpenPosition,
    this.onOpenAccount,
  });

  /// The live snapshot.
  final HomeSnapshot snapshot;

  /// Drills a position line into its list (S1.1).
  final void Function(PositionLine line)? onOpenPosition;

  /// Opens one money account's statement (S4).
  final void Function(String accountId)? onOpenAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final p = snapshot.position;
    Widget row(
      String label,
      int paise, {
      VoidCallback? onTap,
      String? meta,
    }) => RkLabelAmountRow(
      label: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      meta: meta == null
          ? null
          : Text(
              meta,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: status.muted),
            ),
      // Consumer surface: signed amount, credit/debit colour on the numerals,
      // the row label is the word beside it — the direction words *Money in /
      // Money out* belong to a movement, not to a standing balance.
      amount: MoneyText(paise),
      onTap: onTap,
      semanticHint: onTap == null ? null : l10n.homePositionDrill,
    );

    return RkRuledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.cardPadding,
              RkSpace.s3,
              RkSpace.cardPadding,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.homePositionTitle,
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: status.muted),
                    ),
                  ),
                ),
                if (snapshot.provisional)
                  Flexible(
                    child: _ProvisionalBadge(text: l10n.homeVerifyProvisional),
                  ),
              ],
            ),
          ),
          row(
            l10n.homePositionCash,
            p.cashPaise,
            onTap: onOpenPosition == null
                ? null
                : () => onOpenPosition!(PositionLine.cash),
          ),
          for (final b in p.banks)
            row(
              b.account.name,
              b.balancePaise,
              onTap: onOpenAccount == null
                  ? null
                  : () => onOpenAccount!(b.account.id),
            ),
          row(
            l10n.homePositionYouWillGet,
            p.youWillGetPaise,
            onTap: onOpenPosition == null
                ? null
                : () => onOpenPosition!(PositionLine.youWillGet),
          ),
          row(
            l10n.homePositionYouWillGive,
            -p.youWillGivePaise,
            onTap: onOpenPosition == null
                ? null
                : () => onOpenPosition!(PositionLine.youWillGive),
          ),
          row(
            l10n.homePositionAdvancesOut,
            p.advancesOutPaise,
            onTap: onOpenPosition == null
                ? null
                : () => onOpenPosition!(PositionLine.advancesOut),
          ),
          row(
            l10n.homePositionInTransit,
            p.inTransitPaise,
            onTap: onOpenPosition == null
                ? null
                : () => onOpenPosition!(PositionLine.inTransit),
          ),
          const SizedBox(height: RkSpace.s2),
        ],
      ),
    );
  }
}

class _ProvisionalBadge extends StatelessWidget {
  const _ProvisionalBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.hourglass_empty, size: 16, color: status.pending),
        const SizedBox(width: RkSpace.s1),
        Flexible(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: status.pending),
          ),
        ),
      ],
    );
  }
}

/// The *This month In/Out* line 🔒 (owner-confirmed, 07 §4).
class HomeMonthLine extends StatelessWidget {
  /// Creates the line.
  const HomeMonthLine({
    super.key,
    required this.inPaise,
    required this.outPaise,
  });

  /// Income this month, positive paise.
  final int inPaise;

  /// Expense this month, positive paise.
  final int outPaise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    Widget figure(String label, int paise, bool positive) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: status.muted),
        ),
        MoneyText(
          positive ? paise : -paise,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Wrap(
        spacing: RkSpace.s4,
        runSpacing: RkSpace.s1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.homeMonthLabel,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: status.muted),
          ),
          figure(l10n.homeMonthIn, inPaise, true),
          figure(l10n.homeMonthOut, outPaise, false),
        ],
      ),
    );
  }
}

/// The four verb buttons (07 §4): they open the §5 entry flow with the verb
/// pre-chosen. A [Wrap], not a [Row] — four labels in Gurmukhi at 200% do not
/// fit one line on a 360 px phone (07 §1 rule 11).
class HomeVerbButtons extends StatelessWidget {
  /// Creates the buttons.
  const HomeVerbButtons({super.key, this.onVerb});

  /// Opens S2 with [EntryKind] pre-chosen.
  final void Function(EntryKind kind)? onVerb;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    Widget button(EntryKind kind, String label, IconData icon, Color tint) =>
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          child: OutlinedButton.icon(
            onPressed: onVerb == null ? null : () => onVerb!(kind),
            icon: Icon(icon, size: 18, color: tint),
            label: Text(label),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Wrap(
        spacing: RkSpace.s2,
        runSpacing: RkSpace.s2,
        children: [
          button(
            EntryKind.moneyIn,
            l10n.homeVerbMoneyIn,
            Icons.south_west,
            status.credit,
          ),
          button(
            EntryKind.moneyOut,
            l10n.homeVerbMoneyOut,
            Icons.north_east,
            status.debit,
          ),
          button(
            EntryKind.gaveCredit,
            l10n.homeVerbGave,
            Icons.call_made,
            status.debit,
          ),
          button(
            EntryKind.tookCredit,
            l10n.homeVerbTook,
            Icons.call_received,
            status.credit,
          ),
        ],
      ),
    );
  }
}

/// One Today row (13 §4.1 pattern P1): counter account, the user's own words,
/// the signed amount with its direction word, and — only when the review flag
/// is open — the small amber clock. The entry counts in every balance either
/// way (02 §3): the marker says who must look, never what the books say.
class HomeTodayRow extends StatelessWidget {
  /// Creates the row.
  const HomeTodayRow({
    super.key,
    required this.row,
    required this.accountsById,
    this.onTap,
  });

  /// The entry.
  final HomeEntryRow row;

  /// Account lookup for the labels.
  final Map<String, Account> accountsById;

  /// Opens the entry detail (S4.1).
  final VoidCallback? onTap;

  /// The line whose signed paise the row shows — the money account's own view
  /// (+ = money came in). A transfer has two money legs, so the destination
  /// (the debit) is the one shown; an entry with no money leg at all falls
  /// back to the party line, seen from the user's side.
  static HomeLine? amountLine(HomeEntryRow row, Map<String, Account> chart) {
    final money = [
      for (final l in row.lines)
        if (chart[l.accountId]?.accountClass == AccountClass.money) l,
    ];
    if (money.isNotEmpty) {
      if (row.kind == EntryKind.transfer) {
        return money.firstWhere(
          (l) => l.amountPaise > 0,
          orElse: () => money.first,
        );
      }
      return money.first;
    }
    for (final l in row.lines) {
      if (chart[l.accountId]?.accountClass == AccountClass.party) {
        return HomeLine(accountId: l.accountId, amountPaise: -l.amountPaise);
      }
    }
    return row.lines.isEmpty ? null : row.lines.first;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final line = amountLine(row, accountsById);
    final others = [
      for (final l in row.lines)
        if (l.accountId != line?.accountId)
          accountsById[l.accountId]?.name ?? l.accountId,
    ];
    final label = others.isEmpty
        ? accountsById[line?.accountId]?.name ?? ''
        : others.join(', ');
    return RkLabelAmountRow(
      label: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      meta: row.note == null && !row.underReview
          ? null
          : Wrap(
              spacing: RkSpace.s2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (row.note != null)
                  Text(
                    row.note!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: status.muted),
                  ),
                if (row.underReview)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 14, color: status.pending),
                      const SizedBox(width: RkSpace.s1),
                      Text(
                        l10n.homeTodayUnderReview,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: status.pending),
                      ),
                    ],
                  ),
              ],
            ),
      amount: MoneyText(line?.amountPaise ?? 0, showDirection: true),
      onTap: onTap,
    );
  }
}

/// The setup checklist (S0.7) the position card collapses to for a new user
/// (07 §4 empty state; 13 §8 "never a blank").
class HomeSetupChecklist extends StatelessWidget {
  /// Creates the checklist.
  const HomeSetupChecklist({
    super.key,
    required this.openingBalancesDone,
    required this.firstEntryDone,
    this.onStep,
  });

  /// Step 1 complete.
  final bool openingBalancesDone;

  /// Step 2 complete.
  final bool firstEntryDone;

  /// Opens step [index] (0-based); null leaves the step unactionable.
  final void Function(int index)? onStep;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    // ⚠️ SPEC: 07 §4 lists four steps (opening balances → first entry →
    // recovery sheet → add family) but no doc says where Home reads the last
    // two from — the recovery sheet is 06/S11.4 and members are S13. Rather
    // than invent a completion rule they are shown as not-yet-done, which is
    // the conservative reading; wiring them belongs to those lanes.
    Widget step(int index, String label, bool done) => RkLabelAmountRow(
      leading: Icon(
        done ? Icons.check_circle_outline : Icons.radio_button_unchecked,
        size: 20,
        color: done ? status.credit : status.muted,
      ),
      label: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      amount: done
          ? Text(
              l10n.homeSetupDone,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: status.credit),
            )
          : const SizedBox.shrink(),
      onTap: done || onStep == null ? null : () => onStep!(index),
    );
    return RkRuledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.cardPadding,
              RkSpace.s3,
              RkSpace.cardPadding,
              0,
            ),
            child: Semantics(
              header: true,
              child: Text(
                l10n.homeSetupTitle,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: status.muted),
              ),
            ),
          ),
          step(0, l10n.homeSetupOpeningBalances, openingBalancesDone),
          step(1, l10n.homeSetupFirstEntry, firstEntryDone),
          step(2, l10n.homeSetupRecoverySheet, false),
          step(3, l10n.homeSetupAddFamily, false),
          const SizedBox(height: RkSpace.s2),
        ],
      ),
    );
  }
}
