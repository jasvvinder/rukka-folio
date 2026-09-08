// S19.1 Update required (13 §3.2, 07 §24, 06 §4.5): the API answered 426.
// Mandatory — no dismiss, no back. States: default · opening the store
// (loading) · offline (button stays, explains — no dead end, 07 §1 rule 6).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/tokens.dart';
import '../http_auth_client.dart';

class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key, required this.gate, this.onUpdate});

  final UpdateRequired gate;

  /// Opens the store listing. Integration supplies it (url_launcher is not
  /// declared here); null → the button shows its loading state only.
  final Future<void> Function()? onUpdate;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _opening = false;

  Future<void> _update() async {
    setState(() => _opening = true);
    try {
      await widget.onUpdate?.call();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sync = RkScope.of(context).sync;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Icon(
                  Icons.system_update_alt,
                  size: RkSpace.s12,
                  color: scheme.primary,
                ),
                const SizedBox(height: RkSpace.s4),
                Text(l10n.updateTitle, style: text.headlineMedium),
                const SizedBox(height: RkSpace.s3),
                Text(l10n.updateBody, style: text.bodyLarge),
                const SizedBox(height: RkSpace.s3),
                Text(
                  l10n.updateVersion(
                    widget.gate.currentVersion,
                    widget.gate.requiredVersion.isEmpty
                        ? '—'
                        : widget.gate.requiredVersion,
                  ),
                  style: text.bodySmall?.copyWith(fontFeatures: RkType.tabular),
                ),
                const Spacer(),
                StreamBuilder<SyncStatus>(
                  stream: sync.status,
                  initialData: sync.current,
                  builder: (context, snap) => snap.data is Offline
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: RkSpace.s3),
                          child: Row(
                            children: [
                              Icon(
                                Icons.wifi_off,
                                size: RkIcon.grid - RkSpace.s1,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: RkSpace.s2),
                              Expanded(
                                child: Text(
                                  l10n.updateOffline,
                                  style: text.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                FilledButton(
                  onPressed: _opening ? null : _update,
                  child: Text(
                    _opening ? l10n.updateOpening : l10n.updateAction,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
