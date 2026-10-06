// S0.06 Start — new or already using Rukka (13 §3.2 row S0.06, 07 §3.1 step 1's
// ADR note, ADR 2026-10-05c §1 🔒; canvas 1b L0). The front door after the
// welcome slides: two full-width doors and the invite line. Both doors open
// the same S0.2 phone-and-code screens; the door only sets S0.2's heading and
// what happens when the number surprises us (§2). Nothing about any number is
// asked or shown here.
//
// The invite line is words, not a button: 07 §12 stays the invite path — the
// link the inviter sent opens S0.9 directly (a deep link), so there is nothing
// on this screen to press for it, and no dead end either.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../auth/widgets/sign_in_parts.dart';
import '../widgets/sealed_mark.dart';

/// [SealedMark]'s box for the canvas's 61 px book on L0 (the mark draws its
/// book inside a margin, so the box is larger than the book: 48 + 32 + 4).
const double _markSize = RkSpace.s12 + RkSpace.s8 + RkSpace.s1;

class StartScreen extends StatelessWidget {
  const StartScreen({super.key, this.onNew, this.onSignIn});

  /// *I'm new · set up my books* → S0.2 on the I'm-new door.
  final VoidCallback? onNew;

  /// *I already use Rukka · sign in* → S0.2 in its sign-in state.
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  authSide,
                  0,
                  authSide,
                  RkSpace.s4,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox.shrink(),
                    Semantics(
                      header: true,
                      label: l10n.appName,
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          const SealedMark(size: _markSize),
                          const SizedBox(height: RkSpace.s8),
                          Text(
                            l10n.appName,
                            textAlign: TextAlign.center,
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: RkSpace.s8),
                        AuthPrimaryAction(
                          label: l10n.onboardingStartNew,
                          onPressed: onNew,
                        ),
                        const SizedBox(height: RkSpace.s3),
                        AuthSecondaryAction(
                          label: l10n.onboardingStartSignIn,
                          onPressed: onSignIn,
                        ),
                        const SizedBox(height: RkSpace.s6),
                        Text(
                          l10n.onboardingStartInvited,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(color: status.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
