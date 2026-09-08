// S15.4 Device suspended (13 §3.2, 07 §5.6; ADR 2026-09-05b §2, 05d §3): the
// server asserted a revocation without a signed record → read-only, persistent
// banner, sync stopped, nothing wiped, Retry. Path to S11 (no dead end).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
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
            SuspendedBanner(text: l10n.suspendedBanner),
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

/// The persistent banner atom (13 §4.2): icon + word, never colour alone.
class SuspendedBanner extends StatelessWidget {
  const SuspendedBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        color: status.dangerSurface,
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s3,
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: scheme.error),
            const SizedBox(width: RkSpace.s2),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}
