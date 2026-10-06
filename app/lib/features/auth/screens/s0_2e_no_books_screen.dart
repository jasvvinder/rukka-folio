// S0.2e No books on this number (13 §3.2 row S0.2e, ADR 2026-10-05c §2 🔒;
// canvas 1b L8). Shown by S0.2 on the *sign in* door, only after a correct
// code for a number with no account (06 §2: before the code every number gets
// the same answer). The server signed nothing up: *Set up new books* is the
// signup, made from the code already accepted (the signup ticket, **no second
// code**) and then on to S0.3; *Try another number* goes back to the number
// on the same door. Settles desk 129 for the sign-in path: a verified code for
// an unknown number becomes a signup only when the person chooses it.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../widgets/sign_in_parts.dart';

class NoBooksScreen extends StatelessWidget {
  const NoBooksScreen({
    super.key,
    required this.phone,
    required this.onSetUp,
    required this.onOtherNumber,
    this.onBack,
    this.busy = false,
    this.error,
  });

  /// E.164 number the code went to.
  final String phone;

  /// The signup, with no second code → S0.3.
  final VoidCallback onSetUp;

  /// → back to the number, sign-in door kept.
  final VoidCallback onOtherNumber;
  final VoidCallback? onBack;

  /// While the signup runs: both actions wait.
  final bool busy;

  /// A failed signup that can be retried in place (transport).
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final e = error;
    return AuthPage(
      onBack: busy ? null : onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: RkSpace.s4),
          Semantics(
            header: true,
            child: RkFitText(l10n.authNoBooksTitle, style: text.headlineMedium),
          ),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.authNoBooksLead(displayPhone(phone), l10n.appName),
            style: text.bodyLarge?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s5),
          Text(l10n.authNoBooksBody, style: text.bodyLarge),
          if (e != null) ...[
            const SizedBox(height: RkSpace.s5),
            AuthErrorLine(text: e),
          ],
        ],
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthPrimaryAction(
            label: busy ? l10n.authDeviceActivating : l10n.authNoBooksSetUp,
            onPressed: busy ? null : onSetUp,
          ),
          const SizedBox(height: RkSpace.s3),
          AuthSecondaryAction(
            label: l10n.authNoBooksOtherNumber,
            onPressed: busy ? null : onOtherNumber,
          ),
        ],
      ),
    );
  }
}
