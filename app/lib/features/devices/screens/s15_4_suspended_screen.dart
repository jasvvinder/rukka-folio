// S15.4 Device suspended (13 §3.2, 07 §5.6; ADR 2026-09-05b §2, 05d §3): the
// server asserted a revocation without a signed record → read-only, persistent
// banner, sync stopped, nothing wiped, Retry. Path to S11 (no dead end).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_restriction.dart';
import '../../../shared/widgets/rk_restriction_copy.dart';
import '../devices_repository.dart';

class SuspendedScreen extends StatefulWidget {
  const SuspendedScreen({super.key, this.onOpenDevices});

  final VoidCallback? onOpenDevices;

  @override
  State<SuspendedScreen> createState() => _SuspendedScreenState();
}

class _SuspendedScreenState extends State<SuspendedScreen> {
  bool _retrying = false;

  Future<void> _retry(DevicesRepository repo) async {
    setState(() => _retrying = true);
    try {
      await repo.retrySuspended();
    } on Exception {
      // Still suspended; the banner says so. Nothing to add.
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final repo = DevicesRepositoryScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // One banner atom, not a second implementation: 13 §4.2 lists
            // the persistent banner once and names *suspended* as one of the
            // states it carries. The copy stays owned by 07 §15 — the
            // `suspended.*` strings — and the way forward (Retry, Devices &
            // security) stays in the screen body below, so the banner states
            // the fact in the one line 07 §15 mints for it.
            RkRestrictionBanner(
              kind: RkRestrictionKind.suspended,
              copy: RkRestrictionKind.suspended.copy(context),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(RkSpace.s6),
                children: [
                  Icon(
                    Icons.pause_circle_outline,
                    size: RkSpace.s12,
                    color: status.locked,
                  ),
                  const SizedBox(height: RkSpace.s4),
                  Text(l10n.suspendedTitle, style: text.headlineMedium),
                  const SizedBox(height: RkSpace.s3),
                  Text(l10n.suspendedBody, style: text.bodyLarge),
                  const SizedBox(height: RkSpace.s8),
                  FilledButton(
                    onPressed: _retrying ? null : () => _retry(repo),
                    child: Text(
                      _retrying ? l10n.suspendedRetrying : l10n.suspendedRetry,
                    ),
                  ),
                  const SizedBox(height: RkSpace.s3),
                  TextButton.icon(
                    onPressed: widget.onOpenDevices,
                    icon: Icon(Icons.devices, color: scheme.primary),
                    label: Text(l10n.suspendedDevicesLink),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
