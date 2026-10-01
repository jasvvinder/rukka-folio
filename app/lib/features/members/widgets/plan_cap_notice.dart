// The plain-words line for a plan-cap refusal (ADR 2026-09-05g §2 / §6 🔒),
// and the one way on: S12.1 Plans.
//
// The server refuses an invite (or a membership record) when the plan has no
// room — `seat_cap`, `seat_rotation_cap`, `book_cap` (migration 0019). Each
// gets its own sentence, because "the plan is full" and "you have changed
// members too often this year" are different facts with the same way out
// (01 §3: blocked actions state the reason and the path; 07 §1 rule 6: no dead
// ends). The line is not an error in red: nothing went wrong, the plan said no.
// It is an icon + text (colour never alone, 07 §1), and the action under it
// opens Plans — never *Try again*, because asking again cannot make room and
// the server already holds the refused record.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/tokens.dart';
import '../../subscription/subscription_paths.dart';
import '../members_repository.dart';

/// The sentence for [reason] when it is a plan cap, or null when it is not.
String? planCapMessage(AppLocalizations l10n, MembersRefusal reason) =>
    switch (reason) {
      MembersRefusal.seatCap => l10n.inviteCapSeats,
      MembersRefusal.seatRotationCap => l10n.inviteCapRotation,
      MembersRefusal.bookCap => l10n.inviteCapBooks,
      _ => null,
    };

/// Shows [refusal]'s line and a *See plans* action. Renders nothing for a
/// refusal that is not a plan cap.
class PlanCapNotice extends StatelessWidget {
  const PlanCapNotice({super.key, required this.refusal, this.onOpenPlans});

  /// The refusal to explain.
  final MembersRefusal refusal;

  /// Opens S12.1. Null → push [SubscriptionPaths.plans] on the ambient router
  /// (the same door `entry_restriction.dart` uses), and nothing at all when
  /// there is no router — never a route the host has not mounted.
  final VoidCallback? onOpenPlans;

  void _open(BuildContext context) {
    if (onOpenPlans != null) {
      onOpenPlans!();
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router != null) unawaited(router.push<void>(SubscriptionPaths.plans));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = planCapMessage(l10n, refusal);
    if (message == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.group_off_outlined,
                size: RkIcon.grid - RkSpace.s1,
                color: scheme.onSurface,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(child: Text(message, style: text.bodyMedium)),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.workspace_premium_outlined),
              label: Text(l10n.inviteCapPlans),
            ),
          ),
        ],
      ),
    );
  }
}
