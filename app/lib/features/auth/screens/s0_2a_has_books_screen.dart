// S0.2a This number already has books (13 §3.2 row S0.2a, ADR 2026-10-05c §2 🔒;
// canvas 1b L1). Shown by S0.2 on the *I'm new* door, only after a correct code
// for a number that already keeps books under another account (06 §2: no
// registered-number oracle — before the code every number gets the same
// answer). *Sign in to my books* goes on to S0.2b with **no second code**;
// *Use a different number* goes back to the number. Nothing is activated here
// (ADR 2026-10-04b §3).
//
// ⚠️ SPEC: canvas 1b L1 greets the person by name with their initials
// (*Welcome back, Harpreet*). ADR 2026-10-05c §2 allows the person's own
// display name after the code, but `otp/verify` does not carry it (server
// slice SIGNIN1B's contract has no name field), so the heading is the plain
// *Welcome back* and the avatar is a glyph. Owner / server desk item.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../widgets/sign_in_parts.dart';

/// The canvas's avatar on L1 (64 px).
const double _avatar = RkSpace.s12 + RkSpace.s4;

class HasBooksScreen extends StatelessWidget {
  const HasBooksScreen({
    super.key,
    required this.phone,
    required this.onSignIn,
    required this.onOtherNumber,
    this.onBack,
  });

  /// E.164 number the code went to.
  final String phone;

  /// → S0.2b, no second code.
  final VoidCallback onSignIn;

  /// → back to the number, same door.
  final VoidCallback onOtherNumber;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return AuthPage(
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: RkSpace.s4),
          const AuthAvatar(size: _avatar),
          const SizedBox(height: RkSpace.s5),
          Semantics(
            header: true,
            child: RkFitText(
              l10n.authHasBooksTitle,
              style: text.headlineMedium,
            ),
          ),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.authHasBooksBody(displayPhone(phone), l10n.appName),
            style: text.bodyLarge?.copyWith(color: status.muted),
          ),
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthPrimaryAction(
            label: l10n.authHasBooksSignIn,
            onPressed: onSignIn,
          ),
          const SizedBox(height: RkSpace.s3),
          AuthSecondaryAction(
            label: l10n.authExistingOtherNumber,
            onPressed: onOtherNumber,
          ),
        ],
      ),
    );
  }
}
