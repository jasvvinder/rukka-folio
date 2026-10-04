// S9.2's not-live state — *this phone can't show your code* (PLAN desk 113).
//
// When it shows. S9.2's QR carries the nonce of the invite that brought this
// user into the tenant, which the server relays on the invites GET (ADR
// 2026-09-25b §2). Since ADR 2026-10-03c §3 and ADR
// 2026-10-04-suspended-invites §1 that route refuses a phone that is not
// live — revoked **or** suspended, with one refusal the app cannot tell
// apart. The invite relay passes that refusal through
// (`InviteNonceRelay.nonce`), and the ceremony factory answers
// `ShowMyCodeDeviceNotLive`, which carries no repository: no session is
// opened and no QR is drawn.
//
// What it must be. Before desk 113 this phone saw S9.2's *no code yet*
// state, whose only way on is *Check again* — which cannot succeed while the
// phone is not live. So, as S0.9 does for the same refusal (desk 109): the
// reason in words true for both removed and paused, a door to *Devices &
// security* (S11, `DevicesPaths.devices`) where the state can be seen and a
// pause cancelled, *Check again* for after that, and *Close* (07 §1 rule 6).
// With no door bound the door is hidden, never shown disabled, as on S0.9.
//
// Colour is never alone (07 §1 rule 3): the `danger` icon (tokens.json
// `danger` role: "suspended device", as S0.9 and the suspended banner use)
// carries a semantics label, and the title says the state in words.
//
// ⚠️ SPEC — copy: 07 §12 / 13 §3.2 give S9.2 no state for this; the words
// follow S0.9's reviewed EN pattern and are a draft for the 07/13 design
// owner (reported, M13-INV113).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// S9.2 while the invite relay refuses this phone as not live.
class ShowMyCodeDeviceNotLiveScreen extends StatelessWidget {
  /// [onOpenDevices] opens *Devices & security*; [onCheckAgain] re-opens this
  /// side; [onClose] leaves S9.2.
  const ShowMyCodeDeviceNotLiveScreen({
    super.key,
    this.onOpenDevices,
    this.onCheckAgain,
    this.onClose,
  });

  /// *Devices & security* (S11). Null hides the door.
  final VoidCallback? onOpenDevices;

  /// *Check again*.
  final VoidCallback? onCheckAgain;

  /// *Close*.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final devices = onOpenDevices;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ceremonyShowTitle)),
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
                label: l10n.ceremonyShowDeviceNotLiveSemantics,
                child: Icon(
                  Icons.phonelink_erase_outlined,
                  size: RkSpace.s12,
                  color: status.danger,
                ),
              ),
              const SizedBox(height: RkSpace.s4),
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(
                  l10n.ceremonyShowDeviceNotLiveTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              Text(
                l10n.ceremonyShowDeviceNotLiveBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: RkSpace.s8),
              if (devices != null) ...[
                FilledButton(
                  onPressed: devices,
                  child: Text(l10n.ceremonyShowDeviceNotLiveDevices),
                ),
                const SizedBox(height: RkSpace.s3),
                OutlinedButton(
                  onPressed: onCheckAgain,
                  child: Text(l10n.ceremonyShowNoInviteRetry),
                ),
              ] else
                FilledButton(
                  onPressed: onCheckAgain,
                  child: Text(l10n.ceremonyShowNoInviteRetry),
                ),
              const SizedBox(height: RkSpace.s3),
              TextButton(
                onPressed: onClose,
                child: Text(l10n.ceremonyShowNoInviteClose),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
