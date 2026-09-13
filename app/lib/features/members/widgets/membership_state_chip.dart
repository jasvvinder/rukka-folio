// The 06 §7 invitation & membership state machine, drawn as one chip.
//
//   invited ──install+OTP──▶ joined_pending_verification ──ceremony ✓──▶ active
//      │ 7-day expiry                    │ ceremony ✗
//      ▼                                 ▼
//   expired (one-tap re-invite)       blocked + security event
//
// Colour is never alone (07 §1 rule 3): every state pairs its tint with an
// icon **and** the word. Tints are tokens only.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../members_repository.dart';

/// Whole days from [now] until [expiresOn], never negative — the countdown in
/// *"Invited · expires in 5 days"* (06 §7: the link lives 7 days).
int daysUntilExpiry(DateTime expiresOn, DateTime now) {
  final days = expiresOn.difference(now).inDays;
  return days < 0 ? 0 : days;
}

/// The state's word in the reader's language.
String membershipStateLabel(
  AppLocalizations l,
  MembershipState state, {
  DateTime? expiresOn,
  required DateTime now,
}) => switch (state) {
  MembershipState.invited => l.membersStateInvited(
    expiresOn == null ? 0 : daysUntilExpiry(expiresOn, now),
  ),
  MembershipState.joinedPendingVerification => l.membersStateJoined,
  MembershipState.active => l.membersStateActive,
  MembershipState.expired => l.membersStateExpired,
  MembershipState.blocked => l.membersStateBlocked,
};

IconData _icon(MembershipState state) => switch (state) {
  MembershipState.invited => Icons.schedule,
  MembershipState.joinedPendingVerification => Icons.how_to_reg_outlined,
  MembershipState.active => Icons.check_circle_outline,
  MembershipState.expired => Icons.hourglass_disabled,
  MembershipState.blocked => Icons.block,
};

/// One membership state, as an outlined chip: icon + word + tint.
class MembershipStateChip extends StatelessWidget {
  const MembershipStateChip({
    super.key,
    required this.state,
    required this.now,
    this.expiresOn,
  });

  final MembershipState state;
  final DateTime now;
  final DateTime? expiresOn;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final colour = switch (state) {
      MembershipState.invited => status.pending,
      MembershipState.joinedPendingVerification => status.pending,
      MembershipState.active => status.success,
      MembershipState.expired => status.locked,
      MembershipState.blocked => status.danger,
    };
    final text = membershipStateLabel(l, state, expiresOn: expiresOn, now: now);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s2,
        vertical: RkSpace.s1,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: colour),
        borderRadius: BorderRadius.circular(RkRadius.sm),
        color: scheme.surface,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(state), size: RkIcon.grid - RkSpace.s2, color: colour),
          const SizedBox(width: RkSpace.s1),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}
