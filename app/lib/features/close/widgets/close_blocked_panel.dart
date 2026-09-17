// S10.5 — *Close blocked — waiting on a device* (07 §28 🔒, 13 §3.2 row
// S10.5, ADR 2026-09-05b §3–4, ADR 2026-09-05f §B).
//
// It is not a screen of its own: it takes the place of step 4's lock action
// while the book has an open author-sequence gap or a `held` envelope. That
// is the honest shape — the closer is still inside the wizard, the first three
// steps are still worth doing, and the one thing that cannot happen is the
// lock. Sending them to a separate destination would be a dead end in the
// middle of a flow they can otherwise finish (07 §1 rule 6).
//
// Three things, in the order 07 §28 🔒 names them:
//   1. the **phone's name** — never a device id at a shopkeeper;
//   2. *entries from it have not arrived*, and what that means for the month;
//   3. *Remind {name}* — **disabled with its reason**, because 07 §17's
//      notification catalog has no reminder source on this device yet, so the
//      button would be a lie. The reason carries the thing the closer can
//      actually do instead.
// And the lock stays off, and says so.
import 'package:flutter/material.dart';

import '../../../shared/widgets/rk_fit_text.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import 'close_parts.dart';

/// The S10.5 panel.
class CloseBlockedPanel extends StatelessWidget {
  /// Creates the panel.
  const CloseBlockedPanel({
    super.key,
    required this.title,
    required this.body,
    required this.remindLabel,
    required this.remindReason,
    required this.lockOffText,
  });

  /// *Close blocked — waiting on a device*.
  final String title;

  /// The explanation, with the phone's name already substituted.
  final String body;

  /// *Remind {name}*, with the name already substituted.
  final String remindLabel;

  /// Why *Remind* is off (07 §17 has no reminder source on the device yet).
  final String remindReason;

  /// That the lock stays off until the gap closes.
  final String lockOffText;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return CloseCard(
      // `warning`, not `danger`: nothing is wrong and nothing is lost — the
      // phone simply has not synced yet (07 §1 rule 7 🔒, which owns this as
      // one of the six status states, and rule 3: the tint never travels
      // without the glyph and the words).
      rule: status.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.phonelink_ring_outlined,
                size: RkSpace.s5,
                color: status.warning,
              ),
              const SizedBox(width: RkSpace.s3),
              Expanded(child: RkFitText(title, style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: RkSpace.s2),
          RkFitText(body, style: text.bodyMedium),
          const SizedBox(height: RkSpace.s4),
          CloseDisabledAction(
            label: remindLabel,
            reason: remindReason,
            icon: Icons.notifications_none,
          ),
          const SizedBox(height: RkSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: RkSpace.s4, color: status.locked),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: RkFitText(
                  lockOffText,
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
