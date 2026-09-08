// The S11.9 / S11.10 card (ADR 2026-09-05d §1, §3): loud-warning panel with
// the requester or the removed device, the countdown atom and one-tap Cancel.
// States: open · cancelling · cancelled · completed · error-with-retry.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../cancel_window.dart';
import 'countdown.dart';

class WindowCard extends StatelessWidget {
  const WindowCard({
    super.key,
    required this.window,
    required this.now,
    required this.onCancel,
    this.cancelling = false,
    this.error = false,
    this.onOpen,
  });

  final CancelWindow window;
  final DateTime now;
  final VoidCallback onCancel;
  final bool cancelling;
  final bool error;

  /// On S11: opens the full-screen card. Null on the screen itself.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final title = switch (window.kind) {
      CancelWindowKind.recovery => l10n.devicesWindowRecoveryTitle,
      CancelWindowKind.support => l10n.devicesWindowSupportTitle,
    };
    final body = switch (window.kind) {
      CancelWindowKind.recovery => l10n.devicesWindowRecoveryBody(
        window.requesterName,
      ),
      CancelWindowKind.support => l10n.devicesWindowSupportBody(
        window.targetDeviceName,
      ),
    };
    final complete = window.isComplete(now);
    final canCancel = window.canCancel(now) && !cancelling;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        decoration: BoxDecoration(
          color: status.dangerSurface,
          borderRadius: BorderRadius.circular(RkRadius.lg),
          border: Border(
            left: BorderSide(
              color: scheme.error,
              width: RkRadius.ruleLeftWidth,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: scheme.error),
                const SizedBox(width: RkSpace.s2),
                Expanded(child: Text(title, style: text.titleLarge)),
              ],
            ),
            const SizedBox(height: RkSpace.s2),
            Text(body, style: text.bodyLarge),
            if (window.kind == CancelWindowKind.recovery &&
                window.newDeviceFingerprint.isNotEmpty) ...[
              const SizedBox(height: RkSpace.s2),
              Text(
                l10n.devicesWindowRecoveryFingerprint(
                  window.newDeviceFingerprint,
                ),
                style: text.bodyMedium?.copyWith(fontFeatures: RkType.tabular),
              ),
            ],
            const SizedBox(height: RkSpace.s3),
            if (window.cancelled)
              Text(l10n.devicesWindowCancelled, style: text.bodyMedium)
            else if (complete)
              Text(l10n.devicesWindowCompleted, style: text.bodyMedium)
            else
              CountdownLine(remaining: window.remaining(now)),
            if (error) ...[
              const SizedBox(height: RkSpace.s2),
              Text(
                l10n.devicesWindowError,
                style: text.bodyMedium?.copyWith(color: scheme.error),
              ),
            ],
            if (!window.cancelled && !complete) ...[
              const SizedBox(height: RkSpace.s3),
              FilledButton(
                onPressed: canCancel ? onCancel : null,
                child: Text(
                  cancelling
                      ? l10n.devicesWindowCancelling
                      : l10n.devicesWindowCancel,
                ),
              ),
            ],
            if (onOpen != null)
              TextButton(onPressed: onOpen, child: Text(l10n.devicesTitle)),
          ],
        ),
      ),
    );
  }
}
