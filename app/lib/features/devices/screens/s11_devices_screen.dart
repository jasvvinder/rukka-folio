// S11 Devices & security (13 §3.2, 07 §15, 06 §6). Order per 07 §15: cancel
// windows while open (S11.9/S11.10 cards) · Backup section first · linked
// devices (this phone, others: name, model, last active, added-on, certified
// state) with Remove and the "This phone was stolen" path (04 §9.2
// consequences before confirm) · keys & recovery rows · App PIN · permanent
// phone-integrity row once S19.5 fired. States: loading (ruled skeleton),
// populated, empty (only this phone → one action), error-with-retry, offline
// chip. Dates through the shared formatter (07 §1 rule 5).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../devices_repository.dart';
import '../widgets/window_card.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({
    super.key,
    this.onOpenBackup,
    this.onOpenWindow,
    this.onLinkDevice,
    this.onOpenRow,
  });

  final VoidCallback? onOpenBackup;
  final void Function(String windowId)? onOpenWindow;
  final VoidCallback? onLinkDevice;

  /// Rows not built by this lane (guardians, sheet, escrow, PIN) → placeholder.
  final void Function(String rowKey)? onOpenRow;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool _loading = false;
  bool _error = false;
  String? _revoking;
  bool _revokeError = false;
  String? _cancelling;
  bool _cancelError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && DevicesRepositoryScope.of(context).current == null) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    final repo = DevicesRepositoryScope.of(context);
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      await repo.refresh();
    } on Exception {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(LinkedDevice d, {required bool stolen}) async {
    final repo = DevicesRepositoryScope.of(context);
    setState(() {
      _revoking = d.id;
      _revokeError = false;
    });
    try {
      await repo.revoke(d.id, stolen: stolen);
    } on Exception {
      if (mounted) setState(() => _revokeError = true);
    } finally {
      if (mounted) setState(() => _revoking = null);
    }
  }

  Future<void> _cancelWindow(String id) async {
    final repo = DevicesRepositoryScope.of(context);
    setState(() {
      _cancelling = id;
      _cancelError = false;
    });
    try {
      await repo.cancelWindow(id);
    } on Exception {
      if (mounted) setState(() => _cancelError = true);
    } finally {
      if (mounted) setState(() => _cancelling = null);
    }
  }

  Future<void> _confirmRemove(LinkedDevice d) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _Sheet(
        title: l10n.devicesRevokeConfirmTitle(d.name),
        lines: [l10n.devicesRevokeConfirmBody],
        confirm: l10n.devicesRevokeConfirmAction,
        cancel: l10n.devicesCancel,
      ),
    );
    if (ok == true) await _revoke(d, stolen: false);
  }

  Future<void> _confirmStolen(LinkedDevice d) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _Sheet(
        title: l10n.devicesStolenTitle,
        intro: l10n.devicesStolenIntro,
        lines: [
          l10n.devicesStolenConsequenceRemoved(d.name),
          l10n.devicesStolenConsequenceBookKeys,
          l10n.devicesStolenConsequenceMasterKey,
          l10n.devicesStolenConsequenceCutoff,
        ],
        confirm: l10n.devicesStolenConfirm,
        cancel: l10n.devicesCancel,
      ),
    );
    if (ok == true) await _revoke(d, stolen: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = DevicesRepositoryScope.of(context);
    final scope = RkScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.devicesTitle)),
      body: SafeArea(
        child: StreamBuilder<DevicesSnapshot>(
          stream: repo.watch(),
          initialData: repo.current,
          builder: (context, snap) {
            final s = snap.data;
            if (s == null) {
              if (_error && !_loading) {
                return _ErrorState(
                  text: l10n.devicesListError,
                  retry: l10n.devicesListRetry,
                  onRetry: _refresh,
                );
              }
              return _Skeleton(label: l10n.devicesListSkeleton);
            }
            return StreamBuilder<SyncStatus>(
              stream: scope.sync.status,
              initialData: scope.sync.current,
              builder: (context, ss) => _list(
                context,
                s,
                offline: ss.data is Offline,
                now: scope.now(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    DevicesSnapshot s, {
    required bool offline,
    required DateTime now,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final openWindows = s.windows
        .where((w) => !w.cancelled && !w.isComplete(now))
        .toList();
    final others = s.devices.where((d) => !d.isThisDevice).toList();
    final thisDevice = s.devices.where((d) => d.isThisDevice).toList();

    String date(DateTime d) =>
        formatListDate(localDateOf(d), strings: l10n, now: now);

    Widget header(String t) => Padding(
      padding: const EdgeInsets.only(top: RkSpace.s6, bottom: RkSpace.s2),
      child: Text(t, style: text.titleLarge),
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(RkSpace.gutter),
        children: [
          if (offline)
            _Chip(icon: Icons.wifi_off, text: l10n.devicesListOffline),
          if (_error)
            _Chip(
              icon: Icons.error_outline,
              text: l10n.devicesListError,
              color: scheme.error,
              action: l10n.devicesListRetry,
              onAction: _refresh,
            ),
          if (openWindows.isNotEmpty) ...[
            header(l10n.devicesWindowSection),
            for (final w in openWindows)
              Padding(
                padding: const EdgeInsets.only(bottom: RkSpace.s3),
                child: WindowCard(
                  window: w,
                  now: now,
                  cancelling: _cancelling == w.id,
                  error: _cancelError && _cancelling == null,
                  onCancel: () => _cancelWindow(w.id),
                  onOpen: widget.onOpenWindow == null
                      ? null
                      : () => widget.onOpenWindow!(w.id),
                ),
              ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_outlined, color: scheme.primary),
            title: Text(l10n.devicesBackupRowTitle, style: text.bodyLarge),
            subtitle: Text(
              l10n.devicesBackupRowSubtitle,
              style: text.bodySmall,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenBackup,
          ),
          header(l10n.devicesListSection),
          for (final d in thisDevice)
            _DeviceRow(device: d, date: date, isThis: true),
          if (others.isEmpty)
            _Empty(
              text: l10n.devicesListEmpty,
              action: l10n.devicesListEmptyAction,
              onAction: widget.onLinkDevice,
            )
          else
            for (final d in others)
              _DeviceRow(
                device: d,
                date: date,
                isThis: false,
                busy: _revoking == d.id,
                onRemove: () => _confirmRemove(d),
                onStolen: () => _confirmStolen(d),
              ),
          if (_revokeError)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s2),
              child: Text(
                l10n.devicesRevokeError,
                style: text.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          header(l10n.devicesMoreSection),
          _Row(
            icon: Icons.group_outlined,
            title: l10n.devicesRowGuardians,
            subtitle: l10n.devicesRowGuardiansSubtitle,
            onTap: () => widget.onOpenRow?.call('guardians'),
          ),
          _Row(
            icon: Icons.description_outlined,
            title: l10n.devicesRowSheet,
            subtitle: l10n.devicesRowSheetSubtitle,
            onTap: () => widget.onOpenRow?.call('sheet'),
          ),
          _Row(
            icon: Icons.family_restroom,
            title: l10n.devicesRowEscrow,
            subtitle: l10n.devicesRowEscrowSubtitle,
            onTap: () => widget.onOpenRow?.call('escrow'),
          ),
          _Row(
            icon: Icons.pin_outlined,
            title: l10n.devicesRowPin,
            subtitle: l10n.devicesRowPinSubtitle,
            onTap: () => widget.onOpenRow?.call('pin'),
          ),
          if (s.integrityDetectedOn != null)
            _Row(
              icon: Icons.phonelink_erase,
              iconColor: status.pending,
              title: l10n.devicesIntegrityRow,
              subtitle: l10n.devicesIntegrityRowSubtitle(
                date(s.integrityDetectedOn!),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.date,
    required this.isThis,
    this.busy = false,
    this.onRemove,
    this.onStolen,
  });

  final LinkedDevice device;
  final String Function(DateTime) date;
  final bool isThis;
  final bool busy;
  final VoidCallback? onRemove;
  final VoidCallback? onStolen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final certified = device.status == DeviceStatus.certified;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: status.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smartphone, color: scheme.onSurface),
              const SizedBox(width: RkSpace.s2),
              Expanded(child: Text(device.name, style: text.bodyLarge)),
              if (isThis)
                _Badge(
                  text: l10n.devicesListThisPhone,
                  color: scheme.primary,
                  icon: Icons.check,
                ),
            ],
          ),
          const SizedBox(height: RkSpace.s1),
          Text(device.model, style: text.bodySmall),
          Text(
            '${l10n.devicesListAddedOn(date(device.addedOn))} · ${l10n.devicesListLastActive(date(device.lastActive))}',
            style: text.bodySmall,
          ),
          const SizedBox(height: RkSpace.s1),
          Row(
            children: [
              Icon(
                certified ? Icons.verified_outlined : Icons.hourglass_empty,
                size: RkIcon.grid - RkSpace.s2,
                color: certified ? scheme.primary : status.pending,
              ),
              const SizedBox(width: RkSpace.s1),
              Text(
                certified
                    ? l10n.devicesListCertified
                    : l10n.devicesListUncertified,
                style: text.bodySmall,
              ),
            ],
          ),
          if (!isThis)
            Row(
              children: [
                TextButton(
                  onPressed: busy ? null : onRemove,
                  child: Text(
                    busy ? l10n.devicesRevokeWorking : l10n.devicesRevokeAction,
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : onStolen,
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  child: Text(l10n.devicesStolenAction),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: RkSpace.s2,
      vertical: RkSpace.s1,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(RkRadius.sm),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: RkIcon.grid - RkSpace.s2, color: color),
        const SizedBox(width: RkSpace.s1),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: RkSpace.rowMinHeight,
      leading: Icon(
        icon,
        color: iconColor ?? Theme.of(context).colorScheme.onSurface,
      ),
      title: Text(title, style: text.bodyLarge),
      subtitle: Text(subtitle, style: text.bodySmall),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.text,
    this.color,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final c = color ?? status.muted;
    return Container(
      margin: const EdgeInsets.only(bottom: RkSpace.s3),
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s3,
        vertical: RkSpace.s2,
      ),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: RkIcon.grid - RkSpace.s1, color: c),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.action, this.onAction});

  final String text;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: RkSpace.s4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: RkSpace.s2),
        OutlinedButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add_link),
          label: Text(action),
        ),
      ],
    ),
  );
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
  Widget build(BuildContext context) => Padding(
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

/// Ruled skeleton rows (11 §4.5, ADR 2026-09-05f §D): static bars, no text.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      child: ListView.builder(
        padding: const EdgeInsets.all(RkSpace.gutter),
        itemCount: 4,
        itemBuilder: (context, i) => Container(
          height: RkSpace.rowMinHeight,
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: i.isEven
                  ? RkMotion.skeletonLabelWidthMax
                  : RkMotion.skeletonLabelWidthMin,
              child: Container(
                height: RkSpace.s3,
                decoration: BoxDecoration(
                  color: status.skeletonLabel,
                  borderRadius: BorderRadius.circular(RkRadius.sm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    this.intro,
    required this.lines,
    required this.confirm,
    required this.cancel,
  });

  final String title;
  final String? intro;
  final List<String> lines;
  final String confirm;
  final String cancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          0,
          RkSpace.gutter,
          RkSpace.s6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleLarge),
            if (intro != null) ...[
              const SizedBox(height: RkSpace.s2),
              Text(intro!, style: text.bodyLarge),
            ],
            const SizedBox(height: RkSpace.s3),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: RkSpace.s2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.arrow_right_alt,
                      size: RkIcon.grid - RkSpace.s1,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(child: Text(l, style: text.bodyMedium)),
                  ],
                ),
              ),
            const SizedBox(height: RkSpace.s4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirm),
            ),
            const SizedBox(height: RkSpace.s2),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancel),
            ),
          ],
        ),
      ),
    );
  }
}
