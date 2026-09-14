// S6.3 — the structural approval card (07 §26 🔒; ADR 2026-09-05f §D's typed
// attention card; the quorum rule of 02 §7.2.1 🔒).
//
// What the card owes the reader, in this order:
//   · exactly what will change, in words with figures — the terms in force
//     beside the proposed ones (07 §26 🔒);
//   · quorum progress, *2 of 3*, read straight off the engine's outcome;
//   · **Approve** and **Veto with reason**, a veto cancelling and logging;
//   · the plain statement that nothing has been applied yet (02 §7.2.1 🔒).
//
// The numbers are never computed here. `evaluateStructural` counts the signed
// approvals against the owner-set version each names and hands back a
// threshold; a screen that divided owners by two would disagree with the
// engine the moment a book chose *majority* (⌊n/2⌋+1, ADR 2026-09-14
// ruling 1 🔒) or its owner set was re-versioned. See `structural_requests.dart`.
//
// Colour never alone (07 §1 rule 3): every state here is an icon **and** a
// word; the status hues only tint them.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../structural_requests.dart';

/// The title of one structural request, in the reader's language.
String structuralTitle(StructuralItem item, AppLocalizations l10n) {
  final subject = item.subject;
  return switch (item.action) {
    StructuralAction.ownershipRatio => l10n.inboxStructuralKindOwnershipRatio,
    StructuralAction.profitDistribution => l10n.inboxStructuralKindProfit,
    StructuralAction.interestOnCapital => l10n.inboxStructuralKindInterest,
    StructuralAction.ownerAddOrRemove => l10n.inboxStructuralKindOwner,
    StructuralAction.memberRemoval =>
      subject == null
          ? l10n.inboxStructuralKindMemberRemovalPlain
          : l10n.inboxStructuralKindMemberRemoval(subject),
    StructuralAction.yearReopen =>
      subject == null
          ? l10n.inboxStructuralKindYearReopenPlain
          : l10n.inboxStructuralKindYearReopen(subject),
    StructuralAction.fyStartChange => l10n.inboxStructuralKindFyStart,
    StructuralAction.bookArchiveOrDelete => l10n.inboxStructuralKindArchive(
      item.bookName,
    ),
    StructuralAction.quorumSetting => l10n.inboxStructuralKindQuorum,
  };
}

/// One term value in the reader's language: an amount formatted as money
/// (integer paise, CLAUDE.md rule 1), a day formatted per 07 §1 rule 5, plain
/// text as the book records it, and `null` rendered as *not recorded* — never
/// as a stand-in default (02 §7.1 🔒).
String structuralValueText(
  StructuralValue? value, {
  required AppLocalizations l10n,
  required Locale locale,
  required String whenAbsent,
}) => switch (value) {
  null => whenAbsent,
  StructuralText(:final text) => text,
  StructuralMoney(:final paise) => formatPaise(paise, locale: locale),
  StructuralDay(:final day) => formatLedgerDate(day, strings: l10n),
};

/// The S6.3 card.
class StructuralCard extends StatelessWidget {
  /// Creates the card.
  const StructuralCard({
    super.key,
    required this.item,
    required this.onApprove,
    required this.onVeto,
    this.onOpen,
    this.onReinitiate,
    this.busy = false,
    this.error = false,
    this.result,
    this.dense = false,
  });

  /// The request and the engine's verdict on it.
  final StructuralItem item;

  /// *Approve* — the caller confirms, then signs (07 §26 🔒).
  final VoidCallback onApprove;

  /// *Veto with reason* — the caller asks for the reason, then signs.
  final VoidCallback onVeto;

  /// Opens the review surface. Null where the route is not mounted.
  final VoidCallback? onOpen;

  /// *Raise it again* after a lapse (02 §7.2.1: lapsed, logged, re-initiable).
  final VoidCallback? onReinitiate;

  /// A write is in flight (13 §4.3 loading).
  final bool busy;

  /// The last write failed and nothing changed (13 §4.3 error).
  final bool error;

  /// What just landed, if anything — the approval or the veto.
  final StructuralResult? result;

  /// The review surface draws the same card without its own *open* link.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final pending = item.status == StructuralStatus.pending;

    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(RkRadius.lg),
          border: Border(
            left: BorderSide(
              color: _ruleColour(status),
              width: RkRadius.ruleLeftWidth,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pending) _flagChip(context),
            if (pending) const SizedBox(height: RkSpace.s2),
            Text(
              structuralTitle(item, l10n),
              // The kind is a sentence, not a label: *"Change when the book's
              // year starts"* has no break opportunity inside its longest
              // word, and a 293 px card cannot hold that word at the section
              // size once the user is at 200 %. Above that the heading steps
              // down one rung — still fully scaled, never clipped and never
              // below body size (07 §1 rule 9, 13 §8).
              style:
                  MediaQuery.textScalerOf(context)
                          .scale(RkType.section.fontSize!) >
                      34
                  ? text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)
                  : text.titleLarge,
            ),
            const SizedBox(height: RkSpace.s1),
            Text(
              l10n.inboxStructuralRaisedBy(item.initiatorName, item.bookName),
              style: text.bodyMedium?.copyWith(color: status.muted),
            ),
            if (item.terms.isNotEmpty) ...[
              const SizedBox(height: RkSpace.s4),
              Text(l10n.inboxStructuralTermsTitle, style: text.titleMedium),
              const SizedBox(height: RkSpace.s2),
              for (final term in item.terms)
                Padding(
                  padding: const EdgeInsets.only(bottom: RkSpace.s3),
                  child: _TermLine(term: term, locale: locale),
                ),
              if (item.action == StructuralAction.ownershipRatio &&
                  item.terms.any((t) => t.current == null))
                Text(
                  l10n.inboxStructuralRatioUnrecorded,
                  style: text.bodyMedium?.copyWith(color: status.muted),
                ),
            ],
            const SizedBox(height: RkSpace.s4),
            _quorum(context),
            if (pending) ...[
              const SizedBox(height: RkSpace.s2),
              Text(
                l10n.inboxStructuralDeadline(
                  formatLedgerDate(localDateOf(item.deadline), strings: l10n),
                ),
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s2),
              // 02 §7.2.1 🔒 — nothing is applied early. Say it plainly.
              Text(
                l10n.inboxStructuralNothingApplied,
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
            ],
            ..._statusLines(context),
            if (error) ...[
              const SizedBox(height: RkSpace.s2),
              _IconLine(
                icon: Icons.error_outline,
                colour: scheme.error,
                child: Text(
                  l10n.inboxCardError,
                  style: text.bodyMedium?.copyWith(color: scheme.error),
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: RkSpace.s2),
              _IconLine(
                icon: result == StructuralResult.approved
                    ? Icons.check_circle_outline
                    : Icons.block,
                colour: result == StructuralResult.approved
                    ? status.success
                    : status.danger,
                child: Text(
                  result == StructuralResult.approved
                      ? l10n.inboxStructuralApproveRecorded
                      : l10n.inboxStructuralVetoRecorded,
                  style: text.bodyMedium?.copyWith(
                    color: result == StructuralResult.approved
                        ? status.success
                        : status.danger,
                  ),
                ),
              ),
            ],
            ..._actions(context),
          ],
        ),
      ),
    );
  }

  Color _ruleColour(RkStatusColors status) => switch (item.status) {
    StructuralStatus.pending => status.warning,
    StructuralStatus.approved => status.success,
    StructuralStatus.vetoed => status.danger,
    StructuralStatus.lapsed => status.locked,
  };

  Widget _flagChip(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    // Icon + word + hue, never hue alone (07 §1 rule 3).
    return _IconLine(
      icon: Icons.groups_outlined,
      colour: status.warning,
      child: Text(
        l10n.inboxStructuralFlag,
        style: text.labelLarge?.copyWith(color: status.warning),
      ),
    );
  }

  Widget _quorum(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final required = item.required;
    if (required == null) {
      // The engine could not count: say why rather than show a fake total.
      return _IconLine(
        icon: Icons.help_outline,
        colour: status.info,
        child: Text(
          l10n.inboxStructuralQuorumUnknown,
          style: text.bodyMedium?.copyWith(color: status.info),
        ),
      );
    }
    final progress = l10n.inboxStructuralQuorumProgress(
      item.approvals,
      required,
    );
    return Semantics(
      label: progress,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(RkRadius.sm),
            child: LinearProgressIndicator(
              value: required == 0
                  ? 0
                  : (item.approvals / required).clamp(0, 1).toDouble(),
              minHeight: RkSpace.s1,
              backgroundColor: status.loaderTrack,
              valueColor: AlwaysStoppedAnimation<Color>(status.success),
            ),
          ),
          const SizedBox(height: RkSpace.s2),
          Text(progress, style: text.titleMedium),
        ],
      ),
    );
  }

  List<Widget> _statusLines(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    Widget line(IconData icon, Color colour, String body, {TextStyle? style}) =>
        Padding(
          padding: const EdgeInsets.only(top: RkSpace.s2),
          child: _IconLine(
            icon: icon,
            colour: colour,
            child: Text(body, style: style ?? text.bodyMedium),
          ),
        );

    switch (item.status) {
      case StructuralStatus.vetoed:
        final by = item.vetoBy;
        final reason = item.vetoReason;
        return [
          line(
            Icons.block,
            status.danger,
            l10n.inboxStructuralVetoedTitle(by ?? item.initiatorName),
            style: text.titleMedium?.copyWith(color: status.danger),
          ),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s2),
              child: Text(
                l10n.inboxStructuralVetoedReason(reason),
                style: text.bodyLarge,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: RkSpace.s2),
            child: Text(
              l10n.inboxStructuralVetoedLogged,
              style: text.bodyMedium?.copyWith(color: status.muted),
            ),
          ),
        ];
      case StructuralStatus.lapsed:
        return [
          line(
            Icons.hourglass_disabled,
            status.locked,
            l10n.inboxStructuralLapsedTitle,
            style: text.titleMedium,
          ),
          Padding(
            padding: const EdgeInsets.only(top: RkSpace.s2),
            child: Text(
              l10n.inboxStructuralLapsedBody(item.initiatorName),
              style: text.bodyMedium?.copyWith(color: status.muted),
            ),
          ),
          if (!item.viewerCanInitiate)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s2),
              child: Text(
                l10n.inboxStructuralLapsedAsk(item.bookName),
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
            ),
        ];
      case StructuralStatus.approved:
        return [
          line(
            Icons.check_circle_outline,
            status.success,
            l10n.inboxStructuralDoneTitle,
            style: text.titleMedium?.copyWith(color: status.success),
          ),
          if (item.required != null)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s2),
              child: Text(
                l10n.inboxStructuralDoneBody(item.approvals, item.required!),
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
            ),
        ];
      case StructuralStatus.pending:
        final out = <Widget>[];
        // 02 §7.2.1 / the engine: raising a request is not approving it. The
        // initiator signs one like every other owner, and is told so.
        if (item.viewerIsInitiator && !item.viewerHasApproved) {
          out.add(
            line(
              Icons.info_outline,
              status.info,
              l10n.inboxStructuralYouRaised,
            ),
          );
        }
        switch (item.block) {
          case StructuralBlock.alreadyApproved:
            out.add(
              line(
                Icons.check_circle_outline,
                status.success,
                l10n.inboxStructuralYouApproved,
                style: text.bodyLarge?.copyWith(color: status.success),
              ),
            );
            final required = item.required;
            if (required != null && required > item.approvals) {
              out.add(
                Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s2),
                  child: Text(
                    l10n.inboxStructuralWaiting(required - item.approvals),
                    style: text.bodyMedium?.copyWith(color: status.muted),
                  ),
                ),
              );
            }
          case StructuralBlock.notAnOwner:
            out.add(
              line(
                Icons.visibility_outlined,
                status.muted,
                l10n.inboxStructuralNotOwner(item.bookName),
              ),
            );
          case StructuralBlock.unknownOwnerSet:
          case null:
            break;
        }
        return out;
    }
  }

  List<Widget> _actions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final out = <Widget>[];
    if (busy) {
      out
        ..add(const SizedBox(height: RkSpace.s3))
        ..add(
          _IconLine(
            icon: Icons.sync,
            colour: status.muted,
            child: Text(
              l10n.inboxCardWorking,
              style: text.bodyMedium?.copyWith(color: status.muted),
            ),
          ),
        );
    } else if (item.viewerMayDecide) {
      out
        ..add(const SizedBox(height: RkSpace.s4))
        ..add(
          FilledButton(
            onPressed: onApprove,
            child: Text(l10n.inboxStructuralApprove),
          ),
        )
        ..add(const SizedBox(height: RkSpace.s2))
        ..add(
          OutlinedButton(
            onPressed: onVeto,
            style: OutlinedButton.styleFrom(foregroundColor: status.danger),
            child: Text(l10n.inboxStructuralVeto),
          ),
        );
    } else if (item.status == StructuralStatus.lapsed &&
        item.viewerCanInitiate &&
        onReinitiate != null) {
      out
        ..add(const SizedBox(height: RkSpace.s4))
        ..add(
          FilledButton(
            onPressed: onReinitiate,
            child: Text(l10n.inboxStructuralLapsedAction),
          ),
        );
    }
    if (!dense && onOpen != null) {
      out
        ..add(const SizedBox(height: RkSpace.s2))
        ..add(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: onOpen,
              child: Text(l10n.inboxStructuralOpen),
            ),
          ),
        );
    }
    return out;
  }
}

/// What just landed on a card, so the reader sees their own act (13 §4.3).
enum StructuralResult {
  /// The owner's approval was signed and recorded.
  approved,

  /// The owner's veto closed the request.
  vetoed,
}

/// One *what will change* line: the subject, the term in force, the term
/// proposed. Laid out as a [Wrap] so the pair stacks rather than clips when
/// the script is long or the text scale is 200 % (07 §1 rules 9 and 11).
class _TermLine extends StatelessWidget {
  const _TermLine({required this.term, required this.locale});

  final StructuralTerm term;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(term.subject, style: text.titleMedium),
        const SizedBox(height: RkSpace.s1),
        Wrap(
          spacing: RkSpace.s6,
          runSpacing: RkSpace.s2,
          children: [
            _Pair(
              label: l10n.inboxStructuralTermNow,
              value: structuralValueText(
                term.current,
                l10n: l10n,
                locale: locale,
                whenAbsent: l10n.inboxStructuralTermUnrecorded,
              ),
              style: text.bodyLarge?.copyWith(color: status.muted),
            ),
            _Pair(
              label: l10n.inboxStructuralTermProposed,
              value: structuralValueText(
                term.proposed,
                l10n: l10n,
                locale: locale,
                whenAbsent: l10n.inboxStructuralTermRemoved,
              ),
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.value, this.style});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: status.muted)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Icon + text on one baseline, wrapping rather than clipping.
class _IconLine extends StatelessWidget {
  const _IconLine({
    required this.icon,
    required this.colour,
    required this.child,
  });

  final IconData icon;
  final Color colour;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 20, color: colour),
      const SizedBox(width: RkSpace.s2),
      Expanded(child: child),
    ],
  );
}
