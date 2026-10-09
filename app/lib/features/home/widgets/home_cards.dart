// The Home surface's own components (07 §4; 13 §4.1 patterns P1 and P2;
// design-system §2). Home is a CONSUMER surface (02 §10 🔒, CLAUDE.md rule 9):
// *Money in / Money out*, plain words, never Dr/Cr — those live on the A/C
// statement and the trial balance the verification card links to.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../home_data.dart';
import '../home_paths.dart';
import '../../../shared/widgets/rk_ruled_card.dart';

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
          // Scale-to-fit, because `₹1,36,200` is one unbreakable word: at the
          // hero size it already needs 398 px of a 360 px phone's 328 px
          // column at 1.0×, and 794 px at 200 %. Left as a plain Text it did
          // not throw — it drew its last digits past the edge of the screen,
          // which is how a ledger comes to show a wrong number. Shrinking is
          // the only honest answer: the figure stays whole, and at 200 % it is
          // still drawn as large as the column can hold.
          //
          // ⚠️ SPEC: 07 §4 fixes the hero's type but says nothing about what
          // happens when the figure outgrows the phone. Shrinking is the
          // conservative reading — no digit is ever lost and no dead end is
          // created (07 §1) — but it does mean a 200 % reader gets roughly
          // 83 % of the hero size on a 7-figure total. If the intent is the
          // full 200 %, the answer is a shorter format (lakh/crore) or a
          // smaller hero token, both design calls: owner to rule.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              formatPaise(totalPaise, locale: locale),
              maxLines: 1,
              style: RkType.amountHero.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
                fontFeatures: RkType.tabular,
              ),
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
    this.onOpenReconciliation,
  });

  /// The live snapshot.
  final HomeSnapshot snapshot;

  /// Drills a position line into its list (S1.1).
  final void Function(PositionLine line)? onOpenPosition;

  /// Opens one money account's statement (S4).
  final void Function(String accountId)? onOpenAccount;

  /// Opens S8.3 Family reconciliation — the door 07 §10 🔒 gives the
  /// *In transit* pair ("the Family Reconciliation screen lists any non-zero
  /// pair with its composing entries"). Null in a host that has no route for
  /// it: the chip is then still drawn and still says what is happening, it
  /// simply does not travel (07 §1 rule 6 — an explanation is not a dead end).
  final VoidCallback? onOpenReconciliation;

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
          // 07 §4's *In transit* line: the figure is [Position.inTransitPaise]
          // and the row drills into its own list like every other line. The
          // 07 §10 🔒 label is a second thing and appears only while a pair is
          // actually in transit.
          row(
            l10n.homePositionInTransit,
            p.inTransitPaise,
            onTap: onOpenPosition == null
                ? null
                : () => onOpenPosition!(PositionLine.inTransit),
          ),
          // ⚠️ SPEC: 07 §4 gives every position line its S1.1 drill-down and
          // 07 §10 gives the pair the Family Reconciliation screen, and no doc
          // says which one a tap on this row means. The conservative reading
          // is taken: the row keeps the 07 §4 drill it shares with every other
          // line, and the 07 §10 door is the chip's own — one row, two
          // destinations, each labelled.
          if (snapshot.hasInTransitPair)
            HomeInTransitChip(
              key: HomeCardKeys.inTransitChip,
              onOpen: onOpenReconciliation,
            ),
          const SizedBox(height: RkSpace.s2),
        ],
      ),
    );
  }
}

/// Widget keys the Home cards' own tests drive them by.
abstract final class HomeCardKeys {
  /// The 07 §10 *In transit* chip under the position card's In transit line.
  static const inTransitChip = Key('home.position.in_transit.chip');
}

/// The 07 §10 🔒 **In transit** marker: drawn under the position card's
/// *In transit* line while a reconciliation pair touching this book still has
/// a half carrying an open review flag (02 §6 🔒).
///
/// ⚠️ SPEC: 07 §4 gives the position card a permanent *In transit* row and
/// 07 §10 says "the position lines show **In transit** until both halves
/// post" — the same two words for the row's name and for the pending state.
/// Printing them twice says nothing, so the row keeps the word and this
/// marker carries what the word cannot: the ⏳, the sentence and the door.
/// The conservative reading — a figure never loses its label, and the pending
/// state is only ever claimed when a pair really is in transit.
///
/// Colour is never alone (07 §1 rule 3 🔒): the ⏳ icon and the sentence both
/// carry the state and `pending` only tints them. The sentence is the one the
/// S8.3 report uses, so a member meets one vocabulary on both screens.
class HomeInTransitChip extends StatelessWidget {
  /// Creates the chip.
  const HomeInTransitChip({super.key, this.onOpen});

  /// Opens S8.3 Family reconciliation (07 §10 🔒). Null = no route here.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    // A Wrap, not a Row: ⏳ plus *In transit* plus the sentence in Gurmukhi at
    // 200 % does not fit one line on a 360 px phone (07 §1 rule 11).
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.cardPadding,
        RkSpace.s1,
        RkSpace.cardPadding,
        RkSpace.s1,
      ),
      child: Wrap(
        spacing: RkSpace.s2,
        runSpacing: RkSpace.s1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.hourglass_empty, size: 16, color: status.pending),
          Text(
            l10n.reportsReconciliationInTransitDetail,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: status.pending),
          ),
        ],
      ),
    );
    return Semantics(
      button: onOpen != null,
      hint: onOpen == null ? null : l10n.homePositionInTransitAction,
      child: onOpen == null ? body : InkWell(onTap: onOpen, child: body),
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
/// pre-chosen. Drawn as canvas 1 O8 and canvas 15 S1 draw them — four equal
/// tiles, the direction arrow over the word — in one row; when the widest
/// word of a label no longer fits a quarter of the width (Gurmukhi at 200 %,
/// a 360 px phone) they reflow to 2 × 2 rather than clip (07 §1 rule 11).
/// [HomeVerbBar] pins them above the tab bar.
class HomeVerbButtons extends StatelessWidget {
  /// Creates the buttons.
  const HomeVerbButtons({super.key, this.onVerb, this.blockedReason});

  /// The key of the disabled-with-reason line, for tests and for a screen
  /// reader's traversal checks.
  static const reasonKey = ValueKey('home.verb.blocked_reason');

  /// Opens S2 with [EntryKind] pre-chosen.
  final void Function(EntryKind kind)? onVerb;

  /// Why the verbs cannot be used right now (13 §4.3 *disabled-with-reason*).
  /// Non-null disables all four and draws the reason, with a lock icon, under
  /// them — the verbs never disappear (07 §1 rule 6) and the state never
  /// rides on colour alone (07 §1 rule 3). The way forward is the shell's
  /// S12.5 banner, which is drawn whenever this is (ADR 2026-09-24b §13).
  final String? blockedReason;

  /// A tile's side padding. Half the frame's 4 px: the type role is the
  /// 12 px caption where the frame draws 11.5 px, and at 390 px the frame's
  /// *Gave on credit* fits one line only with the extra 4 px.
  static const _tilePadX = RkSpace.s1 / 2;

  /// Columns for [labels] in [width]: four, two or one — the most for which
  /// the widest single word of any label, at the current text scale, still
  /// fits a tile. A word is never broken mid-letter (07 §1 rule 11).
  static int columnsFor(
    BuildContext context,
    double width,
    List<String> labels,
    TextStyle? style,
  ) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var widest = 0.0;
    for (final label in labels) {
      for (final word in label.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        if (painter.width > widest) widest = painter.width;
        painter.dispose();
      }
    }
    for (final columns in const [4, 2]) {
      final tile = (width - (columns - 1) * RkSpace.s2) / columns;
      // The tile's own side padding and its 1 px border, each side.
      if (widest <= tile - 2 * _tilePadX - 2) return columns;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    // The frame's 11.5 px medium label is the caption role (tokens.json).
    final label = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontWeight: FontWeight.w500);
    final reason = blockedReason;
    final onVerb = reason == null ? this.onVerb : null;
    // The frame's arrows: Money in ↓ and Money out ↑, the two credit verbs
    // → and ← in muted ink. The word under every arrow says the direction.
    //
    // ⚠️ SPEC (owner, open P1A): canvas 1 O8 and canvas 15 S1 tint the in/out
    // arrows with `var(--in)` / `var(--out)` — the credit/debit tokens — but
    // 07 §1 rule 3 🔒 keeps those for amounts only (icons take the
    // success/warning/info/danger family, ADR 2026-09-05f §H1), and neither
    // `success` nor `danger` (security/destructive, "never reads as money
    // out") means a direction. A frame never overrides a 🔒 line (CLAUDE.md
    // § Precedence), so until the owner rules, the two arrows are drawn in
    // full ink — stronger than the credit verbs' muted ink, never a money
    // tint (P1A review, finding 8).
    final verbs = <(EntryKind, String, IconData, Color)>[
      (
        EntryKind.moneyIn,
        l10n.homeVerbMoneyIn,
        Icons.arrow_downward,
        Theme.of(context).colorScheme.onSurface,
      ),
      (
        EntryKind.moneyOut,
        l10n.homeVerbMoneyOut,
        Icons.arrow_upward,
        Theme.of(context).colorScheme.onSurface,
      ),
      (
        EntryKind.gaveCredit,
        l10n.homeVerbGave,
        Icons.arrow_forward,
        status.muted,
      ),
      (EntryKind.tookCredit, l10n.homeVerbTook, Icons.arrow_back, status.muted),
    ];
    Widget tile((EntryKind, String, IconData, Color) v) => OutlinedButton(
      onPressed: onVerb == null ? null : () => onVerb(v.$1),
      style: OutlinedButton.styleFrom(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        minimumSize: const Size(0, RkSpace.rowMinHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: _tilePadX,
          vertical: RkSpace.s5,
        ),
        textStyle: label,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Disabled, the arrow takes the button's own disabled ink: a
          // direction tint on a verb that cannot be used would still read
          // as an invitation.
          Icon(v.$3, size: RkSpace.s5, color: reason == null ? v.$4 : null),
          const SizedBox(height: RkSpace.s1),
          Text(v.$2, textAlign: TextAlign.center),
        ],
      ),
    );
    Widget row(List<(EntryKind, String, IconData, Color)> part) =>
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < part.length; i++) ...[
                if (i > 0) const SizedBox(width: RkSpace.s2),
                Expanded(child: tile(part[i])),
              ],
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final columns = columnsFor(context, box.maxWidth, [
              for (final v in verbs) v.$2,
            ], label);
            if (columns == 4) return row(verbs);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < verbs.length; i += columns) ...[
                  if (i > 0) const SizedBox(height: RkSpace.s2),
                  row(verbs.sublist(i, i + columns)),
                ],
              ],
            );
          },
        ),
        if (reason != null) ...[
          const SizedBox(height: RkSpace.s2),
          Row(
            key: reasonKey,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 18, color: status.muted),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: Text(
                  reason,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: status.muted),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The bar that holds [child] (the gated [HomeVerbButtons]) pinned to the
/// bottom of Home's body, directly above the shell's tab bar, with the list
/// scrolling above it — canvas 1 O8 (*Setup checklist · Home, first run*) and
/// canvas 15 S1 (*Home · the baseline*) both draw it so, and 07 §1 rules 1–2
/// 🔒 (8-second entry, the verbs in thumb reach) ask the same. A hairline
/// separates it from the list; it never takes more than half the body — past
/// that (200 % text in a short window) its own content scrolls, so the list
/// above keeps room and nothing overflows (07 §1 rule 11).
class HomeVerbBar extends StatelessWidget {
  /// Creates the bar.
  const HomeVerbBar({super.key, required this.child, this.maxHeight});

  /// The key of the bar, for tests.
  static const barKey = ValueKey('home.verb.bar');

  /// The verbs.
  final Widget child;

  /// The most height the bar may take; unbounded when null.
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s3,
      ),
      child: child,
    );
    return DecoratedBox(
      key: barKey,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: status.hairline)),
      ),
      child: maxHeight == null
          ? content
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight!),
              child: SingleChildScrollView(child: content),
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

/// The rows the S0.7 setup checklist can draw (ADR 2026-10-07 ruling 3).
enum SetupStep {
  /// *Opening balances* — S0.6 over the personal book.
  openingBalances,

  /// *Finish* + the joint fund's name — the family's skipped invite step (S0.6e).
  finishFamily,

  /// *Finish* + the trust's name — the trust's skipped invite step (S0.6h).
  finishTrust,

  /// *Write your first entry* — S2 on *Money out*.
  firstEntry,

  /// *Check your recovery sheet* — S0.5b, until the sheet is scanned back.
  recoverySheet,

  /// *Add your family* — optional; never holds the card open.
  addFamily,
}

/// The family's or trust's *Finish …* row (ADR 2026-10-07 ruling 3).
@immutable
final class SetupBranchRow {
  /// Creates the row.
  const SetupBranchRow({required this.step, required this.done, this.bookName})
    : assert(
        step == SetupStep.finishFamily || step == SetupStep.finishTrust,
        'only the family and trust branches have a row',
      );

  /// [SetupStep.finishFamily] or [SetupStep.finishTrust].
  final SetupStep step;

  /// Done from the checklist — ticked and struck through (canvas 1 O8d).
  final bool done;

  /// The branch book's own name; null until it can be read.
  final String? bookName;
}

/// The setup checklist (S0.7) — canvas 1 frames O8 (*Home, first run*), O8b /
/// O8c (*family / trust, invites skipped*), O8d (*a branch finished*), O8e /
/// O8f (*Not needed*). A primary-ruled card, the one-line promise, then the
/// rows of ADR 2026-10-07 ruling 3:
///
/// 1. *Opening balances* — required, so it arrives ticked;
/// 2. *Finish* + the book's name — family / trust only, while the invite step was
///    skipped; ⋮ → *Not needed* hides it (the caller's toast offers Undo);
/// 3. *Write your first entry*;
/// 4. *Check your recovery sheet · Not scanned back yet* — amber, the one row
///    with a consequence, until the printed sheet is scanned back;
/// 5. *Add your family* — optional, on the *Myself* and *My business* paths
///    only (the family's branch row replaces it; a trust has none).
///
/// A finished row ticks and strikes through. Whether the card is drawn at all
/// is [isOpen] — the caller's decision, so the rule lives in one place.
class HomeSetupChecklist extends StatelessWidget {
  /// Creates the checklist.
  const HomeSetupChecklist({
    super.key,
    required this.openingBalancesDone,
    required this.firstEntryDone,
    this.recoverySheetVerified = false,
    this.branch,
    this.showAddFamily = true,
    this.onStep,
    this.onNotNeeded,
    this.doors = const {...SetupStep.values},
  });

  /// Row 1 complete.
  final bool openingBalancesDone;

  /// The first entry is in.
  final bool firstEntryDone;

  /// The printed sheet was scanned back (04 §7.4).
  final bool recoverySheetVerified;

  /// The *Finish …* row, or null when no invite step is open or done (and
  /// when it was set to *Not needed*).
  final SetupBranchRow? branch;

  /// Draws the optional *Add your family* row.
  final bool showAddFamily;

  /// Opens a row.
  final void Function(SetupStep step)? onStep;

  /// ⋮ → *Not needed* on the branch row; null draws no ⋮.
  final void Function(SetupStep step)? onNotNeeded;

  /// The rows that have somewhere to go. A row outside it is drawn without a
  /// chevron and does not answer a tap — information, never a door to
  /// nowhere (07 §1 rule 6).
  final Set<SetupStep> doors;

  /// ADR 2026-10-07 ruling 3: the card leaves when every row is ticked or set
  /// to *Not needed*; the optional *Add your family* row never holds it open.
  static bool isOpen({
    required bool openingBalancesDone,
    required bool firstEntryDone,
    required bool recoverySheetVerified,
    SetupBranchRow? branch,
  }) =>
      !openingBalancesDone ||
      !firstEntryDone ||
      !recoverySheetVerified ||
      (branch != null && !branch.done);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final roomy = MediaQuery.textScalerOf(context).scale(1) > 1.5;

    Widget? notNeededMenu(SetupStep step) {
      final hide = onNotNeeded;
      if (hide == null) return null;
      final body = step == SetupStep.finishTrust
          ? l10n.homeSetupNotNeededTrustBody
          : l10n.homeSetupNotNeededFamilyBody;
      List<PopupMenuEntry<SetupStep>> items() => [
        PopupMenuItem<SetupStep>(
          value: step,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: RkSpace.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.close, color: status.muted),
                const SizedBox(width: RkSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.homeSetupNotNeeded, style: text.titleMedium),
                      const SizedBox(height: RkSpace.s1),
                      Text(
                        body,
                        style: text.bodyMedium?.copyWith(color: status.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ];

      final rowKey = ValueKey('home.setup.row.${step.name}');
      // Canvas 1 O8e: the menu hangs **under the row it acts on**, right
      // edge on the ⋮, so the row stays in view while the choice is made —
      // not Material's default over the button, which covered the row
      // (SETUP174 review, finding 3). Anchored on the row's own box, so the
      // gap holds at every text size.
      Element? rowOf(BuildContext button) {
        Element? row;
        button.visitAncestorElements((e) {
          if (e.widget.key == rowKey) {
            row = e;
            return false;
          }
          return true;
        });
        return row;
      }

      // A row in the lower half of the list is first brought up, so the
      // menu has room under it inside the list (O8e) rather than over the
      // pinned verbs.
      Future<void> raise(BuildContext button) async {
        final row = rowOf(button);
        if (row == null) return;
        final viewport = Scrollable.maybeOf(row)?.context.findRenderObject();
        final box = row.findRenderObject();
        if (viewport is! RenderBox || box is! RenderBox) return;
        final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (top <= viewport.size.height / 2) return;
        await Scrollable.ensureVisible(
          row,
          alignment: 0.25,
          duration: RkMotion.s,
        );
      }

      void present(BuildContext button) {
        final overlay =
            Overlay.of(button).context.findRenderObject()! as RenderBox;
        final buttonBox = button.findRenderObject()! as RenderBox;
        final anchor =
            (rowOf(button)?.findRenderObject() as RenderBox?) ?? buttonBox;
        final right = buttonBox
            .localToGlobal(
              buttonBox.size.topRight(Offset.zero),
              ancestor: overlay,
            )
            .dx;
        final bottom = anchor
            .localToGlobal(
              anchor.size.bottomLeft(Offset.zero),
              ancestor: overlay,
            )
            .dy;
        unawaited(
          showMenu<SetupStep>(
            context: button,
            position: RelativeRect.fromRect(
              Rect.fromLTWH(right, bottom, 0, 0),
              Offset.zero & overlay.size,
            ),
            // A paper card with a hairline, not the theme's heavy outline
            // (hairlines over shadows, tokens.dart).
            color: scheme.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RkRadius.lg),
              side: BorderSide(color: status.hairline),
            ),
            items: items(),
          ).then((chosen) {
            if (chosen != null) hide(chosen);
          }),
        );
      }

      return Builder(
        builder: (button) => IconButton(
          key: ValueKey('home.setup.more.${step.name}'),
          tooltip: l10n.homeSetupMore,
          icon: Icon(Icons.more_vert, color: status.muted),
          onPressed: () => unawaited(
            raise(button).then((_) {
              if (button.mounted) present(button);
            }),
          ),
        ),
      );
    }

    Widget step(
      SetupStep id,
      String label,
      bool done, {
      String? hint,
      bool warn = false,
      bool hideable = false,
    }) {
      // A ticked row stays a door, as canvas 1 O8 draws it (chevron on the
      // struck *Opening balances*): guided setup is re-runnable until the
      // first lock (02 §4), and a chevron that answers no tap would be a
      // door to nowhere (07 §1 rule 6; P1A review, finding 5). The chevron
      // is drawn exactly when the row opens something.
      final open = onStep != null && doors.contains(id);
      // An open branch row carries ⋮ in the chevron's place (O8b/O8c); once
      // done it is an ordinary ticked row (O8d).
      final menu = hideable && !done ? notNeededMenu(id) : null;
      // The tick is a status icon — the `success` family, never the
      // numerals-only `credit` (07 §1 rule 3 🔒; P1A review, finding 8).
      final Widget mark = done
          ? Icon(Icons.check_circle, size: RkIcon.grid, color: status.success)
          : Icon(
              Icons.radio_button_unchecked,
              size: RkIcon.grid,
              color: warn ? status.pending : status.hairline,
            );
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: done
                ? text.bodyLarge?.copyWith(
                    color: status.muted,
                    decoration: TextDecoration.lineThrough,
                  )
                : text.bodyLarge,
          ),
          if (!done && hint != null)
            // Colour never alone (07 §1 rule 3): the warning
            // carries an icon as well as its tint.
            Row(
              children: [
                if (warn) ...[
                  Icon(
                    Icons.warning_amber_rounded,
                    size: RkSpace.s4,
                    color: status.pending,
                  ),
                  const SizedBox(width: RkSpace.s1),
                ],
                Flexible(
                  child: Text(
                    hint,
                    style: text.bodyMedium?.copyWith(
                      color: warn ? status.pending : status.muted,
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
      return Semantics(
        button: open,
        value: done ? l10n.homeSetupDone : null,
        child: InkWell(
          key: ValueKey('home.setup.row.${id.name}'),
          onTap: open ? () => onStep!(id) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: menu == null ? RkSpace.s4 : RkSpace.s2,
            ),
            // At large text the mark sits above the words, which then take
            // the card's whole width: a Gurmukhi or Devanagari word at 200 %
            // on a 360-wide phone needs it (07 §1 rule 11, 13 §8). The ⋮
            // stays beside the mark — *Not needed* must be reachable at any
            // size.
            child: roomy
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [mark, const Spacer(), ?menu]),
                      const SizedBox(height: RkSpace.s2),
                      body,
                    ],
                  )
                : Row(
                    children: [
                      mark,
                      const SizedBox(width: RkSpace.s4),
                      Expanded(child: body),
                      ?menu,
                      // At large text the chevron gives its width to the words —
                      // the whole row stays the button (07 §1 rule 11).
                      if (menu == null && open)
                        Icon(Icons.chevron_right, color: status.muted),
                    ],
                  ),
          ),
        ),
      );
    }

    final divider = Divider(height: 1, color: status.hairline);
    final branch = this.branch;
    final family = branch?.step == SetupStep.finishFamily;
    return RkRuledCard(
      ruleColor: scheme.primary,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: roomy ? RkSpace.s3 : RkSpace.cardPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: RkSpace.s4),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.homeSetupTitle,
                  style: text.bodyLarge?.copyWith(color: status.muted),
                ),
              ),
            ),
            divider,
            step(
              SetupStep.openingBalances,
              l10n.homeSetupOpeningBalances,
              openingBalancesDone,
            ),
            if (branch != null) ...[
              divider,
              step(
                branch.step,
                switch (branch.bookName) {
                  final name? when name.trim().isNotEmpty =>
                    l10n.homeSetupFinishBook(name),
                  _ =>
                    family
                        ? l10n.homeSetupFinishFamilyUnnamed
                        : l10n.homeSetupFinishTrustUnnamed,
                },
                branch.done,
                hint: family
                    ? l10n.homeSetupFinishFamilyHint
                    : l10n.homeSetupFinishTrustHint,
                hideable: true,
              ),
            ],
            divider,
            step(
              SetupStep.firstEntry,
              l10n.homeSetupFirstEntry,
              firstEntryDone,
              hint: l10n.homeSetupFirstEntryHint,
            ),
            divider,
            step(
              SetupStep.recoverySheet,
              l10n.homeSetupRecoverySheet,
              recoverySheetVerified,
              hint: l10n.homeSetupRecoverySheetHint,
              warn: true,
            ),
            if (showAddFamily) ...[
              divider,
              step(
                SetupStep.addFamily,
                l10n.homeSetupAddFamily,
                false,
                hint: l10n.homeSetupAddFamilyHint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
