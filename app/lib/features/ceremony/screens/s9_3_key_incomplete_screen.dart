// S9.3's fail-closed state — *not ready to check yet* (ADR 2026-09-24b §2,
// 04 §6.3 🔒, 07 §12).
//
// When it shows. The server's `umk_public_keys` row for the person carries
// the Ed25519 half of their UMK and no X25519 half: their phone was installed
// before it offered that half, and has not been opened since. 04 §6.3 🔒
// compares the scanned keys byte-for-byte against the relayed keys, both
// halves (`Ceremony.verifyQr`), so there is nothing honest to compare against
// and no comparison runs — this screen is built from a
// `VerifyMemberKeyIncomplete`, which carries a name and no repository at all.
//
// What it must be (ADR 2026-09-24b §2, second bullet): the ceremony fails
// closed **and says so**. So it is neither the route's silent *Checking.*
// placeholder nor S9.3's generic *Couldn't check that just now.* — it names
// the one thing that fixes it (ask them to open the app once), says nothing
// was checked or shared, and has two ways on: *Check again* (re-reads what the
// server holds; compares nothing by itself) and *Close* (07 §1 rule 6 — no
// dead end). It is not S9.4: nothing mismatched, nobody lied.
//
// Colour is never alone (07 §1 rule 3): the icon carries a semantics label and
// the title says the state in words.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// S9.3 while the person's relayed UMK is missing its X25519 half.
class VerifyMemberKeyIncompleteScreen extends StatelessWidget {
  /// For [memberName]. [onCheckAgain] re-opens the verifier's side; [onClose]
  /// leaves with the person still unverified.
  const VerifyMemberKeyIncompleteScreen({
    super.key,
    required this.memberName,
    this.onCheckAgain,
    this.onClose,
  });

  /// Who to ask. User-typed (this phone's contact name).
  final String memberName;

  /// *Check again*.
  final VoidCallback? onCheckAgain;

  /// *Close*.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ceremonyVerifyTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: l10n.ceremonyVerifyKeyIncompleteSemantics,
                child: Icon(
                  Icons.phonelink_setup_outlined,
                  size: RkSpace.s12,
                  color: status.warning,
                ),
              ),
              const SizedBox(height: RkSpace.s4),
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(
                  l10n.ceremonyVerifyKeyIncompleteTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              Text(
                l10n.ceremonyVerifyKeyIncompleteBody(memberName),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: RkSpace.s3),
              Text(
                l10n.ceremonyVerifyKeyIncompleteWhy,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: status.muted,
                ),
              ),
              const SizedBox(height: RkSpace.s8),
              FilledButton(
                onPressed: onCheckAgain,
                child: Text(l10n.ceremonyVerifyKeyIncompleteRetry),
              ),
              const SizedBox(height: RkSpace.s3),
              TextButton(
                onPressed: onClose,
                child: Text(l10n.ceremonyVerifyKeyIncompleteClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
