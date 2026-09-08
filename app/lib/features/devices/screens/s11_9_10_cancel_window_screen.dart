// S11.9 Recovery in progress — Cancel · S11.10 Support action pending — Cancel
// (13 §3.2; ADR 2026-09-05d §1, §3). Full-screen host for the window card,
// reached from the loud notification or from S11. The countdown ticks against
// the injected clock (rule 3): completes at 24 h, cancel at 23 h 59 works
// (ADR 2026-09-05i §9).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/tokens.dart';
import '../cancel_window.dart';
import '../devices_repository.dart';
import '../widgets/window_card.dart';

class CancelWindowScreen extends StatefulWidget {
  const CancelWindowScreen({super.key, required this.windowId});

  final String windowId;

  @override
  State<CancelWindowScreen> createState() => _CancelWindowScreenState();
}

class _CancelWindowScreenState extends State<CancelWindowScreen> {
  Timer? _tick;
  bool _cancelling = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _cancel(DevicesRepository repo) async {
    setState(() {
      _cancelling = true;
      _error = false;
    });
    try {
      await repo.cancelWindow(widget.windowId);
    } on Exception {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = DevicesRepositoryScope.of(context);
    final now = RkScope.of(context).now;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.devicesWindowSection)),
      body: SafeArea(
        child: StreamBuilder<DevicesSnapshot>(
          stream: repo.watch(),
          initialData: repo.current,
          builder: (context, snap) {
            final windows = snap.data?.windows ?? const <CancelWindow>[];
            final w = windows.where((x) => x.id == widget.windowId).firstOrNull;
            if (w == null) {
              return Padding(
                padding: const EdgeInsets.all(RkSpace.gutter),
                child: Text(
                  l10n.devicesWindowCompleted,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(RkSpace.gutter),
              children: [
                WindowCard(
                  window: w,
                  now: now(),
                  cancelling: _cancelling,
                  error: _error,
                  onCancel: () => _cancel(repo),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
