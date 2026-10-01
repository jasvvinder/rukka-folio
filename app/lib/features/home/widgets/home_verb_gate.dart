// S1's four verbs, gated on S12.5 read-only (ADR 2026-09-24b §13: read-only
// blocks every write that creates an envelope; 13 §4.3 disabled-with-reason).
//
// The verbs ask the public `entryRestrictionFor` (features/entry), through
// [RkEntryRestrictionBuilder] — the same gate S2's Save asks — so Home never
// offers an entry Save would refuse, and never refuses one Save would take.
//
// Read-only only. No book is passed, so book full (per book, ADR 2026-09-05b
// §7) cannot come back here: on Home a verb does not yet know which book it
// will post to, and S2's Save asks that question with the book in hand.
//
// What stays untouched: the 10-second Undo lives in S2's snackbar, not here
// (ADR 2026-09-24b §13's one exception), and the shell's centre (+) still
// opens S2, whose Save raises the S12.5 sheet with the draft kept.
//
// ⚠️ SPEC: DESIGN-PACK §11 (S12.5) describes *"the sheet shown when someone
// taps a verb"*. The sheet's own copy speaks to a draft (*"What you typed is
// kept"*, *"Back to my entry"*) that Home does not have, so on Home the
// verbs are drawn disabled-with-reason (13 §4.3) and the way forward is the
// global banner's *Renew*. Owner item — reported, not invented.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/widgets.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/widgets/rk_entitlement_banner.dart';
import '../../../shared/widgets/rk_restriction.dart';
import 'home_cards.dart';

/// [HomeVerbButtons], disabled with the reason while the tenant is
/// read-only, live otherwise.
class HomeVerbGate extends StatelessWidget {
  /// Creates the gate.
  const HomeVerbGate({super.key, this.onVerb});

  /// Opens S2 with [EntryKind] pre-chosen.
  final void Function(EntryKind kind)? onVerb;

  @override
  Widget build(BuildContext context) => RkEntryRestrictionBuilder(
    builder: (context, kind) => HomeVerbButtons(
      onVerb: onVerb,
      blockedReason: kind == RkRestrictionKind.readOnly
          ? AppLocalizations.of(context).homeVerbReadOnlyReason
          : null,
    ),
  );
}
