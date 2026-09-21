// S17.4 Send diagnostics (13 §3.2 row S17.4: "user-triggered, financial
// values scrubbed, **shown before sending**"; 07 §22 🔒).
//
// CLAUDE.md rule 4 — no plaintext financial data in a diagnostics report —
// is *visible behaviour* on this screen, not an internal detail: the report
// is shown whole before it can go anywhere, and `diag.intro` promises the app
// has no second version of it. That promise is kept by building the payload
// exactly once, from [buildDiagnosticsReport]'s allow-list, and showing and
// sending the same [DiagnosticsReport.text].
//
// The state machine (13 §4.3), every state with a string already drafted:
//
//   collecting   → `diag.skeleton.label`, the ruled skeleton (11 §4.5)
//   collect fail → `diag.collect.error` + `diag.error.retry`
//   ready        → the report: included fields, the exclusions, the payload
//   sending      → `diag.sending`, both actions held
//   sent         → `diag.sent.title` / `.body`, payload still below
//   send fail    → `diag.error.title` / `.body` + retry, nothing sent
//   offline      → `diag.offline` chip, send disabled with
//                  `diag.send.reason.offline` — quiet, never blocking
//                  (07 §1 rule 7 🔒)
//   no channel   → send disabled with `diag.send.reason.channel`, which is
//                  the standing case: [DiagnosticsSender] has no production
//                  producer while ADR 2026-09-19 is unratified, so *Copy the
//                  report* is the way on (07 §1 rule 6 🔒).
//
// The report is rebuilt from the live `MediaQuery`, `Theme`, `Localizations`
// and sync status on every build, so what is on screen can never drift from
// what would be sent. Only the parts that need an await — the device facts —
// and the build time are held in state.
import 'package:data/data.dart' show ledgerSchemaVersion;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_banner.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../diagnostics_report.dart';
import '../diagnostics_seams.dart';
import '../widgets/help_widgets.dart';

/// How far the collection of the device facts has got.
enum DiagCollect {
  /// Reading them.
  loading,

  /// Read.
  ready,

  /// The read threw.
  failed,
}

/// How far a send has got.
enum DiagSend {
  /// Nothing sent yet.
  idle,

  /// Going now.
  sending,

  /// Gone.
  sent,

  /// The send threw; nothing left this phone.
  failed,
}

/// S17.4 — Send diagnostics.
class SendDiagnosticsScreen extends StatefulWidget {
  /// Creates the page.
  const SendDiagnosticsScreen({super.key, this.device, this.sender});

  /// Reads the app and phone facts. **Null in production**: reading them
  /// needs a platform plugin no lane owns this round, and a field the app
  /// cannot read is omitted from the report rather than guessed.
  final DiagnosticsDevice? device;

  /// Sends the payload. **Null in production** while ADR 2026-09-19 is
  /// unratified; the send action then states why it cannot go.
  final DiagnosticsSender? sender;

  @override
  State<SendDiagnosticsScreen> createState() => _SendDiagnosticsScreenState();
}

class _SendDiagnosticsScreenState extends State<SendDiagnosticsScreen> {
  DiagCollect _collect = DiagCollect.loading;
  DiagSend _send = DiagSend.idle;
  DeviceFacts _facts = const DeviceFacts();
  DateTime? _builtAt;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // An InheritedWidget may only be read from here on, never from initState.
    if (_started) return;
    _started = true;
    _collectFacts();
  }

  Future<void> _collectFacts() async {
    // Read the scope *before* the await — an InheritedWidget may not be
    // reached for across an async gap.
    final now = RkScope.of(context).now();
    final device = widget.device;
    if (mounted) setState(() => _collect = DiagCollect.loading);
    if (device == null) {
      // No producer: the report is built from what the app knows about
      // itself, and the fields it cannot read are simply absent.
      if (mounted) {
        setState(() {
          _facts = const DeviceFacts();
          _builtAt = now;
          _collect = DiagCollect.ready;
        });
      }
      return;
    }
    try {
      final facts = await device.read();
      if (!mounted) return;
      setState(() {
        _facts = facts;
        _builtAt = now;
        _collect = DiagCollect.ready;
      });
    } on Object {
      // Never a red screen: the failure is a state with a retry (13 §4.3).
      if (mounted) setState(() => _collect = DiagCollect.failed);
    }
  }

  Future<void> _sendNow(String payload) async {
    final sender = widget.sender;
    if (sender == null) return;
    setState(() => _send = DiagSend.sending);
    try {
      await sender.send(payload);
      if (mounted) setState(() => _send = DiagSend.sent);
    } on Object {
      if (mounted) setState(() => _send = DiagSend.failed);
    }
  }

  Future<void> _copy(String payload, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: RkFitText(confirmation)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sync = RkScope.of(context).sync;
    return Scaffold(
      appBar: AppBar(title: RkFitText(l10n.diagTitle)),
      body: SafeArea(
        child: switch (_collect) {
          DiagCollect.loading => RkSkeleton(label: l10n.diagSkeletonLabel),
          DiagCollect.failed => RkErrorState(
            text: l10n.diagCollectError,
            retryLabel: l10n.diagErrorRetry,
            onRetry: _collectFacts,
          ),
          DiagCollect.ready => StreamBuilder<SyncStatus>(
            stream: sync.status,
            initialData: sync.current,
            builder: (context, snap) => _Report(
              facts: _facts,
              builtAt: _builtAt!,
              sync: snap.data ?? const Synced(),
              send: _send,
              canSend: widget.sender != null,
              onSend: _sendNow,
              onCopy: _copy,
            ),
          ),
        },
      ),
    );
  }
}

/// The report, whole — the only state in which anything can be sent.
class _Report extends StatelessWidget {
  const _Report({
    required this.facts,
    required this.builtAt,
    required this.sync,
    required this.send,
    required this.canSend,
    required this.onSend,
    required this.onCopy,
  });

  final DeviceFacts facts;
  final DateTime builtAt;
  final SyncStatus sync;
  final DiagSend send;
  final bool canSend;
  final Future<void> Function(String payload) onSend;
  final Future<void> Function(String payload, String confirmation) onCopy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final offline = sync is Offline;

    // Built from the live MediaQuery, Theme and Localizations, so the payload
    // on screen is the payload of *this* phone in *this* state.
    final report = buildDiagnosticsReport(
      device: facts,
      sync: sync,
      locale: Localizations.localeOf(context),
      textScale: MediaQuery.textScalerOf(context).scale(1),
      brightness: Theme.of(context).brightness,
      platform: Theme.of(context).platform,
      schemaVersion: ledgerSchemaVersion,
      now: builtAt,
    );
    final payload = report.text;

    // Why the primary action cannot go, in order of what the person can do
    // about it. No channel is the standing case; offline is the one they can
    // fix by waiting.
    final blocked = !canSend
        ? l10n.diagSendReasonChannel
        : offline
        ? l10n.diagSendReasonOffline
        : null;
    final sending = send == DiagSend.sending;

    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s10),
      children: [
        if (offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s4,
              RkSpace.gutter,
              0,
            ),
            child: Row(
              children: [
                // Icon plus word: the state is never the tint alone
                // (07 §1 rule 3).
                Icon(
                  Icons.cloud_off_outlined,
                  size: RkIcon.grid,
                  color: status.info,
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: RkFitText(
                    l10n.diagOffline,
                    style: text.labelLarge?.copyWith(color: status.muted),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            RkSpace.s2,
          ),
          child: RkFitText(l10n.diagIntro, style: text.bodyLarge),
        ),
        if (send == DiagSend.sent)
          RkBannerSurface(
            tone: RkBannerTone.info,
            icon: Icons.check_circle_outline,
            title: l10n.diagSentTitle,
            body: l10n.diagSentBody,
          ),
        if (send == DiagSend.failed)
          RkBannerSurface(
            tone: RkBannerTone.warning,
            icon: Icons.error_outline,
            title: l10n.diagErrorTitle,
            body: l10n.diagErrorBody,
            actions: [
              FilledButton(
                onPressed: () => onSend(payload),
                child: RkFitText(l10n.diagErrorRetry),
              ),
            ],
          ),
        HelpSectionHeading(l10n.diagIncludedHeading),
        for (final entry in report.values.entries)
          _FieldRow(label: _fieldLabel(l10n, entry.key), value: entry.value),
        // The heading lives on the card itself — a section heading above it
        // would say the same words twice.
        HelpLimitsCard(
          title: l10n.diagExcludedHeading,
          lines: [
            l10n.diagExcludedAmounts,
            l10n.diagExcludedNames,
            l10n.diagExcludedNotes,
            l10n.diagExcludedPeople,
          ],
          footnote: l10n.diagExcludedFootnote,
        ),
        HelpSectionHeading(l10n.diagPayloadHeading),
        _PayloadBlock(label: l10n.diagPayloadLabel, payload: payload),
        if (sending)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s4,
              RkSpace.gutter,
              0,
            ),
            child: Semantics(
              liveRegion: true,
              child: RkFitText(l10n.diagSending, style: text.bodyLarge),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s5,
            RkSpace.gutter,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton(
                onPressed: blocked != null || sending
                    ? null
                    : () => onSend(payload),
                child: RkFitText(l10n.diagActionSend),
              ),
              if (blocked != null)
                Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: RkSpace.s4 - 2,
                        color: status.muted,
                      ),
                      const SizedBox(width: RkSpace.s1),
                      Expanded(
                        child: RkFitText(
                          blocked,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: RkSpace.s3),
              OutlinedButton(
                onPressed: sending
                    ? null
                    : () => onCopy(payload, l10n.diagCopied),
                child: RkFitText(l10n.diagActionCopy),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One included field: its label in the reader's language, its value as the
/// report spells it.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s3,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RkFitText(
                  label,
                  style: text.bodyMedium?.copyWith(color: status.muted),
                ),
              ),
              const SizedBox(width: RkSpace.s3),
              Expanded(
                child: RkFitText(
                  value,
                  style: text.bodyLarge?.copyWith(fontFeatures: RkType.tabular),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The payload exactly as it will be sent, one line per field. Drawn as
/// fit-measured lines rather than one long run so that a 200 % Gurmukhi or
/// Devanagari screen still shows every line whole — the values themselves are
/// ASCII, but the block sits in a column shared with translated labels.
class _PayloadBlock extends StatelessWidget {
  const _PayloadBlock({required this.label, required this.payload});

  final String label;
  final String payload;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      label: '$label. $payload',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s2,
          ),
          padding: const EdgeInsets.all(RkSpace.cardPadding),
          decoration: BoxDecoration(
            color: status.sunk,
            borderRadius: BorderRadius.circular(RkRadius.md),
            border: Border.all(color: status.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in payload.split('\n'))
                RkFitText(
                  line,
                  style: text.bodyMedium?.copyWith(
                    fontFeatures: RkType.tabular,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reader's label for [field]. The report itself prints
/// [DiagField.wire]; this is what the *person* sees beside the value.
String _fieldLabel(AppLocalizations l10n, DiagField field) => switch (field) {
  DiagField.appVersion => l10n.diagFieldAppVersion,
  DiagField.platform => l10n.diagFieldPlatform,
  DiagField.osVersion => l10n.diagFieldOsVersion,
  DiagField.language => l10n.diagFieldLanguage,
  DiagField.textScale => l10n.diagFieldTextScale,
  DiagField.theme => l10n.diagFieldTheme,
  DiagField.syncState => l10n.diagFieldSyncState,
  DiagField.outboxDepth => l10n.diagFieldOutboxDepth,
  DiagField.schemaVersion => l10n.diagFieldSchemaVersion,
  DiagField.generatedAt => l10n.diagFieldGeneratedAt,
  DiagField.codes => l10n.diagFieldCodes,
};
