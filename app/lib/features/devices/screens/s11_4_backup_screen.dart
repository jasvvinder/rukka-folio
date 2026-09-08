// S11.4 Backup settings (13 §3.2, 07 §15, 04 §7.6, ADR 2026-09-05f §G): the
// three toggles + the explicit save-sheet action, each with its own risk line
// — amber (pending token, with an icon) where the artefact is readable or
// restorable by anyone holding it, muted otherwise. Read-only variant (S12.5
// pattern), error-with-retry, saved-offline chip, a failed save reverts.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../devices_repository.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.onSaveSheet});

  /// Share-sheet action for the recovery sheet (later lane).
  final VoidCallback? onSaveSheet;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _saveError = false;
  bool _savedOffline = false;
  bool _loadError = false;
  bool _loading = false;

  Future<void> _set(
    DevicesRepository repo,
    BackupSetting s,
    bool v,
    bool offline,
  ) async {
    setState(() {
      _saveError = false;
      _savedOffline = false;
    });
    try {
      await repo.setBackup(s, v);
      if (offline && mounted) setState(() => _savedOffline = true);
    } on Exception {
      if (mounted) setState(() => _saveError = true);
    }
  }

  Future<void> _retry(DevicesRepository repo) async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      await repo.refresh();
    } on Exception {
      if (mounted) setState(() => _loadError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final repo = DevicesRepositoryScope.of(context);
    final sync = RkScope.of(context).sync;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: SafeArea(
        child: StreamBuilder<DevicesSnapshot>(
          stream: repo.watch(),
          initialData: repo.current,
          builder: (context, snap) {
            final s = snap.data;
            if (_loadError || (s == null && !_loading && snap.hasError)) {
              return _ErrorState(
                text: l10n.backupError,
                retry: l10n.devicesListRetry,
                onRetry: () => _retry(repo),
              );
            }
            if (s == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(RkSpace.s6),
                  child: LinearProgressIndicator(
                    minHeight: RkMotion.loaderTrackHeight,
                  ),
                ),
              );
            }
            return StreamBuilder<SyncStatus>(
              stream: sync.status,
              initialData: sync.current,
              builder: (context, ss) {
                final offline = ss.data is Offline;
                final readOnly = s.readOnly;
                return ListView(
                  padding: const EdgeInsets.all(RkSpace.gutter),
                  children: [
                    Text(l10n.backupIntro, style: text.bodyLarge),
                    if (readOnly) ...[
                      const SizedBox(height: RkSpace.s3),
                      _Note(
                        icon: Icons.lock_outline,
                        text: l10n.backupReadonly,
                      ),
                    ],
                    if (_savedOffline) ...[
                      const SizedBox(height: RkSpace.s3),
                      _Note(
                        icon: Icons.phone_android,
                        text: l10n.backupSavedOffline,
                      ),
                    ],
                    if (_saveError) ...[
                      const SizedBox(height: RkSpace.s3),
                      _Note(
                        icon: Icons.error_outline,
                        text: l10n.backupSaveError,
                        color: scheme.error,
                      ),
                    ],
                    const SizedBox(height: RkSpace.s4),
                    BackupRow(
                      title: l10n.backupKeysyncTitle,
                      risk: l10n.backupKeysyncRisk,
                      restores: l10n.backupKeysyncRestores,
                      amber: true,
                      value: s.backup[BackupSetting.platformKeySync] ?? true,
                      onChanged: readOnly
                          ? null
                          : (v) => _set(
                              repo,
                              BackupSetting.platformKeySync,
                              v,
                              offline,
                            ),
                    ),
                    BackupRow(
                      title: l10n.backupVaultTitle,
                      risk: l10n.backupVaultRisk,
                      restores: l10n.backupVaultRestores,
                      amber: false,
                      value: s.backup[BackupSetting.encryptedVault] ?? true,
                      onChanged: readOnly
                          ? null
                          : (v) => _set(
                              repo,
                              BackupSetting.encryptedVault,
                              v,
                              offline,
                            ),
                    ),
                    BackupRow(
                      title: l10n.backupReadableTitle,
                      risk: l10n.backupReadableRisk,
                      restores: l10n.backupReadableRestores,
                      amber: true,
                      value: s.backup[BackupSetting.readableMonthly] ?? true,
                      onChanged: readOnly
                          ? null
                          : (v) => _set(
                              repo,
                              BackupSetting.readableMonthly,
                              v,
                              offline,
                            ),
                    ),
                    BackupRow(
                      title: l10n.backupSheetTitle,
                      risk: l10n.backupSheetRisk,
                      restores: l10n.backupSheetRestores,
                      amber: true,
                      action: l10n.backupSheetAction,
                      onAction: readOnly ? null : widget.onSaveSheet,
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// One S11.4 row: title, risk line (amber + icon where readable/restorable by
/// anyone holding it), "restores?" chip, and a switch or an action.
class BackupRow extends StatelessWidget {
  const BackupRow({
    super.key,
    required this.title,
    required this.risk,
    required this.restores,
    required this.amber,
    this.value,
    this.onChanged,
    this.action,
    this.onAction,
  });

  final String title;
  final String risk;
  final String restores;
  final bool amber;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final riskColor = amber ? status.pending : status.muted;
    return Container(
      constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: status.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.bodyLarge),
                const SizedBox(height: RkSpace.s1),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      amber ? Icons.visibility_outlined : Icons.lock_outline,
                      size: RkIcon.grid - RkSpace.s2,
                      color: riskColor,
                    ),
                    const SizedBox(width: RkSpace.s1),
                    Expanded(
                      child: Text(
                        risk,
                        style: text.bodySmall?.copyWith(color: riskColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RkSpace.s1),
                Text(restores, style: text.bodySmall),
                if (action != null) ...[
                  const SizedBox(height: RkSpace.s2),
                  OutlinedButton(onPressed: onAction, child: Text(action!)),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: RkSpace.s3),
            Switch(value: value!, onChanged: onChanged),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final c = color ?? status.muted;
    return Row(
      children: [
        Icon(icon, size: RkIcon.grid - RkSpace.s1, color: c),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.text,
    required this.retry,
    required this.onRetry,
  });

  final String text;
  final String retry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(RkSpace.s6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: RkSpace.s3),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RkSpace.s4),
          FilledButton(onPressed: onRetry, child: Text(retry)),
        ],
      ),
    );
  }
}
