// S0.5b Recovery sheet (13 §3.2 row S0.5b, 07 §3.1 step 6, 04 §7.4 🔒).
//
// One screen that explains why there is no "forgot password", generates the
// sheet, offers print/save, and then carries the **verified-storage nag**
// until the user scans the *printed* sheet back (04 §7.4 🔒).
//
// ⚠️ SPEC: 04 §7.4 specifies the sheet itself — RK, the sealed blob, the QR
// payload, the Crockford Base32 fallback, the one-page PDF in English plus the
// user's language. None of that is invented here and none of it is rendered:
// this screen shows **no key material at all**, because 04 §7.4 describes a
// printed document, not an on-screen one, and a screen that displayed the key
// would defeat 07 §5.6's screenshot block. Generation, print/save and the
// scan-back check are seams ([onGenerate], [onShare], [onScanBack]) — the
// crypto and the PDF layout belong to a recovery module that does not exist in
// this build; the wanted interface is in the lane report.
//
// States (13 §4.3): intro (nothing generated) · loading (generating) · ready
// with the nag · error with retry · scan failure (retryable) · verified.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Generates the recovery sheet (04 §7.4). Throws on failure; returns nothing
/// the screen may display — the sheet is a document, not a screen.
typedef RecoverySheetGenerator = Future<void> Function();

/// Hands the generated sheet to the platform's print / share sheet.
typedef RecoverySheetSharer = Future<void> Function();

/// Scans the printed sheet back and reports whether it matched the sheet just
/// generated — the verified-storage check of 04 §7.4 🔒.
typedef RecoverySheetVerifier = Future<bool> Function();

/// What the screen is showing.
enum RecoverySheetStep {
  /// Nothing generated yet — the explanation and the generate action.
  intro,

  /// Generating (13 §4.3 loading).
  generating,

  /// Generated: print/save, the risk line, and the nag until it is scanned.
  ready,

  /// The printed sheet was read back and matched — the nag stops.
  verified,
}

class RecoverySheetScreen extends StatefulWidget {
  const RecoverySheetScreen({
    super.key,
    this.onGenerate,
    this.onShare,
    this.onScanBack,
    this.onVerifiedChanged,
    this.onDone,
    this.onSkip,
  });

  /// Makes the sheet (04 §7.4). Null leaves the action disabled rather than
  /// pretending a sheet exists.
  final RecoverySheetGenerator? onGenerate;

  /// Print / save (04 §7.4, 04 §7.6 "Recovery sheet as a file").
  final RecoverySheetSharer? onShare;

  /// Scan the printed sheet back. `false` means it did not match.
  final RecoverySheetVerifier? onScanBack;

  /// Told whether the verified-storage nag should still be showing, so the
  /// host can carry the badge to Menu (07 §3.1 step 6). `true` = still to be
  /// verified.
  final ValueChanged<bool>? onVerifiedChanged;

  /// The next step of 07 §3.1 (the branch step the purpose card chose).
  final VoidCallback? onDone;

  /// Leaves the sheet for later — skippable and resumable (07 §3.1.1); the nag
  /// is what brings it back.
  final VoidCallback? onSkip;

  @override
  State<RecoverySheetScreen> createState() => _RecoverySheetScreenState();
}

class _RecoverySheetScreenState extends State<RecoverySheetScreen> {
  RecoverySheetStep _step = RecoverySheetStep.intro;
  bool _generateFailed = false;
  bool _scanFailed = false;
  bool _busy = false;

  Future<void> _generate() async {
    final gen = widget.onGenerate;
    if (gen == null || _busy) return;
    setState(() {
      _step = RecoverySheetStep.generating;
      _generateFailed = false;
      _busy = true;
    });
    try {
      await gen();
    } on Object {
      if (!mounted) return;
      // Nothing was changed: the old sheet (if any) still stands, because
      // 04 §7.4's regeneration rotates RK only on success.
      setState(() {
        _step = RecoverySheetStep.intro;
        _generateFailed = true;
        _busy = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _step = RecoverySheetStep.ready;
      _busy = false;
    });
    // Generated but not yet scanned back: the nag starts here (04 §7.4 🔒).
    widget.onVerifiedChanged?.call(false);
  }

  Future<void> _share() async {
    final share = widget.onShare;
    if (share == null || _busy) return;
    setState(() => _busy = true);
    try {
      await share();
    } on Object {
      // A cancelled or failed share leaves the sheet exactly as it was; the
      // action stays available (07 §1 rule 6: no dead ends).
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _scanBack() async {
    final scan = widget.onScanBack;
    if (scan == null || _busy) return;
    setState(() {
      _busy = true;
      _scanFailed = false;
    });
    bool matched;
    try {
      matched = await scan();
    } on Object {
      matched = false;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _scanFailed = !matched;
      if (matched) _step = RecoverySheetStep.verified;
    });
    if (matched) widget.onVerifiedChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final generated =
        _step == RecoverySheetStep.ready || _step == RecoverySheetStep.verified;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      l10n.onboardingRecoverySheetTitle,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    Text(
                      l10n.onboardingRecoverySheetWhyTitle,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    Text(
                      l10n.onboardingRecoverySheetWhyBody,
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: RkSpace.s6),

                    if (_step == RecoverySheetStep.generating) ...[
                      const LinearProgressIndicator(
                        minHeight: RkMotion.loaderTrackHeight,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        l10n.onboardingRecoverySheetGenerating,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                    ],

                    if (_generateFailed)
                      _Note(
                        icon: Icons.error_outline,
                        color: scheme.error,
                        text: l10n.onboardingRecoverySheetError,
                        emphasise: true,
                      ),

                    if (generated) ...[
                      Text(
                        l10n.onboardingRecoverySheetReadyTitle,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        l10n.onboardingRecoverySheetReadyBody,
                        style: text.bodySmall,
                      ),
                      const SizedBox(height: RkSpace.s3),
                      _Note(
                        icon: Icons.visibility_outlined,
                        color: status.pending,
                        text: l10n.onboardingRecoverySheetRisk,
                        emphasise: true,
                      ),
                      const SizedBox(height: RkSpace.s4),
                      FilledButton.tonal(
                        onPressed: widget.onShare == null || _busy
                            ? null
                            : _share,
                        child: Text(l10n.onboardingRecoverySheetShare),
                      ),
                      const SizedBox(height: RkSpace.s4),
                    ],

                    // The verified-storage nag: it stays until the printed
                    // sheet is scanned back (04 §7.4 🔒).
                    if (_step == RecoverySheetStep.ready) ...[
                      _Note(
                        icon: Icons.pending_outlined,
                        color: status.pending,
                        text: l10n.onboardingRecoverySheetNagTitle,
                        emphasise: true,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        l10n.onboardingRecoverySheetNagBody,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                      if (_scanFailed) ...[
                        const SizedBox(height: RkSpace.s2),
                        _Note(
                          icon: Icons.error_outline,
                          color: scheme.error,
                          text: l10n.onboardingRecoverySheetScanFailed,
                          emphasise: true,
                        ),
                      ],
                      const SizedBox(height: RkSpace.s3),
                      OutlinedButton(
                        onPressed: widget.onScanBack == null || _busy
                            ? null
                            : _scanBack,
                        child: Text(l10n.onboardingRecoverySheetScan),
                      ),
                    ],

                    if (_step == RecoverySheetStep.verified)
                      _Note(
                        icon: Icons.check_circle_outline,
                        color: status.credit,
                        text: l10n.onboardingRecoverySheetVerified,
                        emphasise: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              if (!generated)
                FilledButton(
                  onPressed: widget.onGenerate == null || _busy
                      ? null
                      : _generate,
                  child: Text(
                    _generateFailed
                        ? l10n.onboardingRecoverySheetRetry
                        : l10n.onboardingRecoverySheetGenerate,
                  ),
                )
              else
                FilledButton(
                  onPressed: widget.onDone,
                  child: Text(l10n.onboardingRecoverySheetDone),
                ),
              TextButton(
                onPressed: widget.onSkip ?? widget.onDone,
                child: Text(l10n.onboardingRecoverySheetSkip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line note: icon **and** text, never colour alone (07 §1 rule 3).
class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.color,
    required this.text,
    this.emphasise = false,
  });

  final IconData icon;
  final Color color;
  final String text;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: RkIcon.grid - RkSpace.s2, color: color),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: Text(
            text,
            style: (emphasise ? theme.bodyMedium : theme.bodySmall)?.copyWith(
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
