// S0.5 Keeping your books safe (13 §3.2 row S0.5, 07 §3.1 step 5 🔒,
// 04 §7.0 / §7.6, ADR 2026-09-05c §8, ADR 2026-09-05f §G).
//
// Backup is configured *here*, at signup, because backup found later mostly
// never happens (07 §3.1 step 5 🔒). One screen, three items:
//
//   (a) **Your key is kept in iCloud Keychain** — *stated, not asked*: there
//       is no switch, because 04 §7.0's default is on and the screen's job is
//       to say so honestly. Two plain lines go with it — Apple cannot read it,
//       and *a phone backup does not carry your books* (ADR 2026-09-05f §G,
//       the local store being excluded from platform backups per ADR
//       2026-09-05c §8; features/devices/at_rest.dart is where that is true).
//   (b) **Automatic backup** — on, destination shown, each artefact carrying
//       its own risk line, the readable copy's disclosure prominent and never
//       softened (04 §7.6 🔒), and a one-tap off on each.
//   (c) The **recovery sheet** action below, which opens S0.5b.
//
// When iCloud Keychain is unavailable or disabled the screen says so plainly
// and the sheet becomes the primary action (07 §3.1 step 5 🔒, last sentence).
//
// ⚠️ SPEC: 07 §3.1 step 5 names *one* item (b) "Automatic backup", while
// 04 §7.6's defaults table has **two** artefacts on by default — the encrypted
// vault file and the monthly readable export — and only the readable one
// carries a disclosure. The conservative reading is taken: one *Automatic
// backup* block, both artefacts shown as their own rows so each risk line sits
// beside the switch that turns that artefact off. Nothing is toggled in a
// pair, because turning off a switch the user cannot see would be the kind of
// silent behaviour 04 §7.6 forbids.
//
// ⚠️ SPEC: whether platform key sync is actually available on the device is a
// platform question no seam in this build answers — features/devices'
// [KeychainKeyStore] is the *device-key* store and deliberately
// `synchronizable: false`, i.e. never the §7.0 item. So availability arrives
// through [BooksSafeScreen.keySyncAvailable]; absent a host callback the
// screen takes 04 §7.0's default (on). The wanted seam is in the lane report.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../devices/devices_repository.dart';

/// Asks the host whether the platform's key sync (iOS iCloud Keychain,
/// Android Block Store — 04 §7.0) is available and enabled on this device.
typedef KeySyncAvailability = Future<bool> Function();

class BooksSafeScreen extends StatefulWidget {
  const BooksSafeScreen({
    super.key,
    this.keySyncAvailable,
    this.backupDestination,
    this.onContinue,
    this.onSheet,
    this.onSkip,
  });

  /// The seam to the platform check (04 §7.0). Null keeps 04 §7.0's default —
  /// on — rather than guessing that it is off.
  final KeySyncAvailability? keySyncAvailable;

  /// Where the automatic backup goes ("iCloud Drive" / "Google Drive",
  /// 04 §7.6). Null shows the generic line rather than naming the wrong cloud.
  final String? backupDestination;

  /// Primary action: the next step of 07 §3.1 — S0.5b, the recovery sheet.
  final VoidCallback? onContinue;

  /// Item (c): the sheet action, which also opens S0.5b. Becomes the primary
  /// action when key sync is unavailable.
  final VoidCallback? onSheet;

  /// Leaves the step for the setup checklist (07 §3.1.1: skippable and
  /// resumable). Shown only where the sheet is the primary action, so the
  /// screen never offers two ways past the same button.
  final VoidCallback? onSkip;

  @override
  State<BooksSafeScreen> createState() => _BooksSafeScreenState();
}

class _BooksSafeScreenState extends State<BooksSafeScreen> {
  /// Null while the platform check is running (loading state, 13 §4.3).
  bool? _keySync;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    final check = widget.keySyncAvailable;
    if (check == null) {
      _keySync = true;
      return;
    }
    // A check that throws is not proof the feature is off, but it is not proof
    // that it is on either — the conservative reading of 07 §3.1 step 5 is to
    // show the unavailable copy, which offers the sheet rather than promising
    // a recovery that may not exist.
    check()
        .then((v) {
          if (mounted) setState(() => _keySync = v);
        })
        .catchError((Object _) {
          if (mounted) setState(() => _keySync = false);
        });
  }

  Future<void> _set(
    DevicesRepository repo,
    BackupSetting setting,
    bool value,
  ) async {
    setState(() => _saveFailed = false);
    try {
      await repo.setBackup(setting, value);
    } on Object {
      // The switch reverts by itself: it renders from the repository's
      // snapshot, which a failed write never changed.
      if (mounted) setState(() => _saveFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final repo = DevicesRepositoryScope.of(context);
    final keySync = _keySync;
    final sheetIsPrimary = keySync == false;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StreamBuilder<DevicesSnapshot>(
                  stream: repo.watch(),
                  initialData: repo.current,
                  builder: (context, snap) {
                    final backup =
                        snap.data?.backup ?? const DevicesSnapshot().backup;
                    return ListView(
                      children: [
                        Text(
                          l10n.onboardingBooksSafeTitle,
                          style: text.headlineMedium,
                        ),
                        const SizedBox(height: RkSpace.s2),
                        Text(
                          l10n.onboardingBooksSafeIntro,
                          style: text.bodyLarge,
                        ),
                        const SizedBox(height: RkSpace.s6),

                        // (a) Key sync — stated, never asked.
                        if (keySync == null)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: RkSpace.s4),
                            child: LinearProgressIndicator(
                              minHeight: RkMotion.loaderTrackHeight,
                            ),
                          )
                        else if (keySync)
                          _Item(
                            icon: Icons.key_outlined,
                            title: l10n.onboardingBooksSafeKeysyncTitle,
                            state: l10n.onboardingBooksSafeKeysyncStateOn,
                            lines: [
                              l10n.onboardingBooksSafeKeysyncApple,
                              l10n.onboardingBooksSafeKeysyncPhoneBackup,
                            ],
                          )
                        else
                          _Item(
                            icon: Icons.key_off_outlined,
                            iconColor: status.pending,
                            title: l10n.onboardingBooksSafeKeysyncOffTitle,
                            lines: [l10n.onboardingBooksSafeKeysyncOffBody],
                            emphasisIndex: 0,
                          ),

                        const SizedBox(height: RkSpace.s6),

                        // (b) Automatic backup — on, destination, one-tap off.
                        _Item(
                          icon: Icons.cloud_upload_outlined,
                          title: l10n.onboardingBooksSafeBackupTitle,
                          state: l10n.onboardingBooksSafeBackupStateOn,
                          lines: [
                            widget.backupDestination == null
                                ? l10n.onboardingBooksSafeBackupDestinationUnset
                                : l10n.onboardingBooksSafeBackupDestination(
                                    widget.backupDestination!,
                                  ),
                          ],
                        ),
                        _BackupToggle(
                          title: l10n.onboardingBooksSafeBackupVaultTitle,
                          risk: l10n.onboardingBooksSafeBackupVaultBody,
                          // Encrypted: no readable-copy warning, so the muted
                          // lock pairing rather than the amber eye.
                          readable: false,
                          value: backup[BackupSetting.encryptedVault] ?? true,
                          onChanged: (v) =>
                              _set(repo, BackupSetting.encryptedVault, v),
                        ),
                        _BackupToggle(
                          title: l10n.onboardingBooksSafeBackupReadableTitle,
                          risk:
                              l10n.onboardingBooksSafeBackupReadableDisclosure,
                          readable: true,
                          value: backup[BackupSetting.readableMonthly] ?? true,
                          onChanged: (v) =>
                              _set(repo, BackupSetting.readableMonthly, v),
                        ),
                        const SizedBox(height: RkSpace.s2),
                        Text(
                          l10n.onboardingBooksSafeBackupOffHint,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                        if (_saveFailed) ...[
                          const SizedBox(height: RkSpace.s2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: RkIcon.grid - RkSpace.s2,
                                color: scheme.error,
                              ),
                              const SizedBox(width: RkSpace.s2),
                              Expanded(
                                child: Text(
                                  l10n.onboardingBooksSafeBackupSaveFailed,
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: RkSpace.s6),

                        // (c) The sheet action, below the other two.
                        _Item(
                          icon: Icons.description_outlined,
                          title: l10n.onboardingBooksSafeSheetTitle,
                          lines: [l10n.onboardingBooksSafeSheetBody],
                        ),
                        const SizedBox(height: RkSpace.s3),
                        if (sheetIsPrimary)
                          FilledButton(
                            onPressed: widget.onSheet,
                            child: Text(l10n.onboardingBooksSafeSheetAction),
                          )
                        else
                          OutlinedButton(
                            onPressed: widget.onSheet,
                            child: Text(l10n.onboardingBooksSafeSheetAction),
                          ),
                        const SizedBox(height: RkSpace.s4),
                        Text(
                          l10n.onboardingBooksSafeResumeNote,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              if (sheetIsPrimary)
                TextButton(
                  onPressed: widget.onSkip ?? widget.onContinue,
                  child: Text(l10n.onboardingBooksSafeSkip),
                )
              else
                FilledButton(
                  onPressed: widget.onContinue,
                  child: Text(l10n.onboardingBooksSafeContinueLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One stated item: icon + title, an optional state chip (icon *and* word —
/// colour never alone, 07 §1 rule 3) and the plain lines beneath it.
class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.title,
    required this.lines,
    this.state,
    this.iconColor,
    this.emphasisIndex,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final String? state;
  final Color? iconColor;

  /// Which line (if any) is rendered at body size rather than small — used for
  /// the unavailable-key-sync explanation, which is the screen's message then.
  final int? emphasisIndex;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: RkSpace.s1),
            child: Icon(
              icon,
              size: RkIcon.grid,
              color: iconColor ?? scheme.primary,
            ),
          ),
          const SizedBox(width: RkSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                if (state != null) ...[
                  const SizedBox(height: RkSpace.s1),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: RkIcon.grid - RkSpace.s2,
                        color: status.credit,
                      ),
                      const SizedBox(width: RkSpace.s1),
                      Text(
                        state!,
                        style: text.bodySmall?.copyWith(color: status.credit),
                      ),
                    ],
                  ),
                ],
                for (final (i, line) in lines.indexed) ...[
                  const SizedBox(height: RkSpace.s2),
                  Text(
                    line,
                    style: i == emphasisIndex ? text.bodyLarge : text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One automatic-backup artefact: its risk line beside the switch that turns
/// that artefact off (04 §7.6 — each states its risk at the moment of
/// choosing). [readable] takes the amber pairing (icon + amber text, never
/// colour alone) because the file can be read by whoever holds it.
class _BackupToggle extends StatelessWidget {
  const _BackupToggle({
    required this.title,
    required this.risk,
    required this.readable,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String risk;
  final bool readable;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final riskColor = readable ? status.pending : status.muted;
    return Container(
      constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: status.hairline)),
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
                      readable ? Icons.visibility_outlined : Icons.lock_outline,
                      size: RkIcon.grid - RkSpace.s2,
                      color: riskColor,
                    ),
                    const SizedBox(width: RkSpace.s1),
                    Expanded(
                      child: Text(
                        risk,
                        style: readable
                            ? text.bodyMedium?.copyWith(color: riskColor)
                            : text.bodySmall?.copyWith(color: riskColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: RkSpace.s3),
          Semantics(
            label: title,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
