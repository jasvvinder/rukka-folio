// S19.5 This phone has been modified (13 §3.2, 07 §24; ADR 2026-09-05 §6):
// root / debugger / instrumentation detected → one plain notice, once per app
// version, path to Devices & security, never blocks. Local only, never a push.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

class ModifiedDeviceScreen extends StatelessWidget {
  const ModifiedDeviceScreen({super.key, this.onOpenDevices, this.onDismiss});

  final VoidCallback? onOpenDevices;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.phonelink_erase,
                size: RkSpace.s12,
                color: status.pending,
              ),
              const SizedBox(height: RkSpace.s4),
              Text(l10n.modifiedTitle, style: text.headlineMedium),
              const SizedBox(height: RkSpace.s3),
              Text(l10n.modifiedBody, style: text.bodyLarge),
              const Spacer(),
              FilledButton(
                onPressed: onOpenDevices ?? () => Navigator.maybePop(context),
                child: Text(l10n.modifiedAction),
              ),
              const SizedBox(height: RkSpace.s3),
              TextButton(
                onPressed: onDismiss ?? () => Navigator.maybePop(context),
                child: Text(l10n.modifiedDismiss),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
