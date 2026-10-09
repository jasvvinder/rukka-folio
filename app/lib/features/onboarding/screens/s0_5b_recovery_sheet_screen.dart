// S0.5b Recovery sheet (13 §3.2 row S0.5b, 07 §3.1 step 6, 04 §7.4 🔒;
// ADR 2026-10-06d ruling 3 🔒, ADR 2026-10-07 ruling 1). Laid out as canvas 1
// frame O5b *Recovery sheet · print or save*.
//
// Two modes over one layout:
//
// * **make** (the sign-up chain, or no sheet on the server yet): *Print or
//   save the sheet* makes the sheet — fresh RK, UMK sealed, blob published —
//   and only once the server holds it opens the page in the platform's print
//   sheet. *I've kept it safe* sleeps until the page has been opened once
//   (O5b's own rule) — printed or saved; a cancelled print sheet is not an
//   opened page. The step is required (ADR 2026-10-07 ruling 1): *Skip
//   for now* appears only when a publish failed, beside its reason, or when
//   this phone has no sheet maker at all (07 §1 rule 6 — never a dead end).
//   S0.5b is the Back target of the step after it: arriving with
//   [RecoverySheetScreen.printedEarlier] it opens on *opened* (the printed
//   page is still the live one), and *Print or save* warns before making a
//   new sheet — never a silent RK rotation (04 §7.4 🔒).
// * **check** (reopened from the S0.7 row once a sheet exists): scan the
//   printed square or type the code; only a code that opens the blob the
//   server holds to this account's key ticks the row (04 §7.4 verified-
//   storage nag). *Make a new sheet* warns first: it voids the printed page.
//
// The screen never shows key material: the A4 preview is a drawing of the
// page with its code masked, because the sheet is a printed document (04
// §7.4) and a real code on screen would outlive the paper in screenshots.
//
// States (13 §4.3): finding (loading) · find failed (retry) · intro · making
// (loading) · not made (error with reason + retry + skip) · opened · checking
// · check failed (reasons + retry) · verified.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../recovery_sheet/recovery_sheet_service.dart';

/// Which half of S0.5b the screen opens on.
enum RecoverySheetEntry {
  /// The sign-up chain: make and print.
  make,

  /// Reopened from S0.7: ask the server; check a sheet it holds, else make.
  checkIfMade,
}

/// What the screen is showing.
enum RecoverySheetStep {
  /// Asking the server whether a sheet exists ([RecoverySheetEntry.checkIfMade]).
  finding,

  /// That question could not be answered.
  findFailed,

  /// Nothing made yet — the explanation and *Print or save the sheet*.
  intro,

  /// Making and publishing (13 §4.3 loading).
  making,

  /// The publish failed; its reason, a retry and *Skip for now*.
  notMade,

  /// The page was opened in the print sheet at least once.
  opened,

  /// A sheet exists: scan or type it back.
  check,

  /// The printed sheet opened this account's blob — the nag stops.
  verified,
}

class RecoverySheetScreen extends StatefulWidget {
  const RecoverySheetScreen({
    super.key,
    this.service,
    this.entry = RecoverySheetEntry.make,
    this.printedEarlier = false,
    this.onPrintedChanged,
    this.onVerifiedChanged,
    this.onDone,
    this.onSkip,
    this.onBack,
  });

  /// Rung 3. Null: this phone cannot make a sheet here; the screen says so
  /// and keeps *Skip for now*.
  final RecoverySheetService? service;

  /// Where the screen starts.
  final RecoverySheetEntry entry;

  /// [RecoverySheetEntry.make] only: this chain already made a sheet and
  /// opened its page (the person came Back to this step). The screen opens
  /// on [RecoverySheetStep.opened] with nothing held, and *Print or save*
  /// asks before it makes a new sheet — the new one voids the printed page.
  final bool printedEarlier;

  /// `false` when a new sheet was made (its page not opened yet); `true`
  /// once its page was printed or saved.
  final ValueChanged<bool>? onPrintedChanged;

  /// `false` when a sheet was made (the nag starts — a new sheet is not yet
  /// checked); `true` when a printed sheet was checked back.
  final ValueChanged<bool>? onVerifiedChanged;

  /// The next step: *I've kept it safe*, or *Done* after a check.
  final VoidCallback? onDone;

  /// Leaves without a sheet — offered only when one could not be made.
  final VoidCallback? onSkip;

  /// The top bar's back chevron (O5b).
  final VoidCallback? onBack;

  @override
  State<RecoverySheetScreen> createState() => _RecoverySheetScreenState();
}

class _RecoverySheetScreenState extends State<RecoverySheetScreen> {
  late RecoverySheetStep _step;
  RecoverySheetNotMadeReason? _notMade;
  RecoverySheetCheckResult? _checked;
  RecoverySheetPrintout? _printout;

  /// A sheet made on an earlier visit was printed and is not held here:
  /// making another voids that page, so it is asked first.
  bool _printedEarlier = false;
  bool _openFailed = false;
  bool _busy = false;
  bool _typing = false;
  final _code = TextEditingController();
  final _scroll = ScrollController();

  /// A note appears under the preview, which at 390×844 is below the fold:
  /// bring it into view so a reason is never off-screen (13 §4.3).
  void _revealNotes() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: RkMotion.s,
        curve: RkMotion.easeBrand,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.entry == RecoverySheetEntry.checkIfMade &&
        widget.service != null) {
      _step = RecoverySheetStep.finding;
      _find();
    } else if (widget.printedEarlier && widget.service != null) {
      _printedEarlier = true;
      _step = RecoverySheetStep.opened;
    } else {
      _step = RecoverySheetStep.intro;
    }
  }

  @override
  void dispose() {
    // The rendered page carries RK; it goes when the screen does.
    _printout?.discard();
    _code.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final service = widget.service;
    if (service == null) return;
    setState(() => _step = RecoverySheetStep.finding);
    bool exists;
    try {
      exists = await service.sheetOnServer();
    } on Object {
      if (mounted) setState(() => _step = RecoverySheetStep.findFailed);
      return;
    }
    if (!mounted) return;
    setState(
      () => _step = exists ? RecoverySheetStep.check : RecoverySheetStep.intro,
    );
  }

  /// Asks before a new sheet voids a printed one (04 §7.4 🔒).
  Future<bool> _confirmMakeNew() async {
    final l10n = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.onboardingRecoverySheetCheckMakeNew),
        content: Text(l10n.onboardingRecoverySheetCheckMakeNewWarning),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.onboardingRecoverySheetCheckMakeNew),
          ),
        ],
      ),
    );
    return go == true && mounted;
  }

  /// [confirmed]: the person already agreed to void the printed page.
  Future<void> _printOrSave({bool confirmed = false}) async {
    final service = widget.service;
    if (service == null || _busy) return;
    var printout = _printout;
    if (printout == null && _printedEarlier && !confirmed) {
      if (!await _confirmMakeNew()) return;
    }
    if (printout == null) {
      setState(() {
        _busy = true;
        _step = RecoverySheetStep.making;
        _notMade = null;
        _openFailed = false;
      });
      try {
        printout = await service.make(Localizations.localeOf(context));
      } on RecoverySheetNotMade catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _step = RecoverySheetStep.notMade;
          _notMade = e.reason;
        });
        return;
      } on Object {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _step = RecoverySheetStep.notMade;
          _notMade = RecoverySheetNotMadeReason.server;
        });
        return;
      }
      if (!mounted) {
        printout.discard();
        return;
      }
      _printout = printout;
      // The earlier page is void now; this one is not opened yet.
      _printedEarlier = false;
      widget.onPrintedChanged?.call(false);
      // Made and held by the server, not yet checked back (04 §7.4 🔒).
      widget.onVerifiedChanged?.call(false);
    }
    setState(() {
      _busy = true;
      _openFailed = false;
    });
    var opened = false;
    var failed = false;
    try {
      // False: the person cancelled the print sheet — not an opened page.
      opened = await printout.open();
    } on Object {
      // Never logged: the page is the key (rule 4).
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _openFailed = failed;
      if (opened || _step == RecoverySheetStep.making) {
        _step = opened ? RecoverySheetStep.opened : RecoverySheetStep.intro;
      }
    });
    if (opened) widget.onPrintedChanged?.call(true);
  }

  Future<void> _runCheck(
    Future<RecoverySheetCheckResult> Function(RecoverySheetService) check,
  ) async {
    final service = widget.service;
    if (service == null || _busy) return;
    setState(() {
      _busy = true;
      _checked = null;
    });
    RecoverySheetCheckResult result;
    try {
      result = await check(service);
    } on Object {
      result = RecoverySheetCheckResult.couldNotCheck;
    }
    if (!mounted) return;
    final ok = result == RecoverySheetCheckResult.opens;
    setState(() {
      _busy = false;
      // Backing out of the scanner is not a verdict.
      _checked = result == RecoverySheetCheckResult.cancelled ? null : result;
      if (ok) _step = RecoverySheetStep.verified;
      if (result == RecoverySheetCheckResult.noCamera) _typing = true;
    });
    _revealNotes();
    if (ok) widget.onVerifiedChanged?.call(true);
  }

  Future<void> _makeNew() async {
    if (!await _confirmMakeNew()) return;
    setState(() {
      _step = RecoverySheetStep.intro;
      _checked = null;
      _typing = false;
    });
    await _printOrSave(confirmed: true);
  }

  bool get _checkMode =>
      _step == RecoverySheetStep.check || _step == RecoverySheetStep.verified;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
        automaticallyImplyLeading: false,
        // O5b's top bar sits on the page, title beside the chevron, no rule.
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const Border(),
        centerTitle: false,
        titleSpacing: widget.onBack == null ? null : 0,
        title: Text(l10n.onboardingRecoverySheetTitle),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s3,
            RkSpace.gutter,
            RkSpace.s4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  children: [
                    RkFitText(
                      _checkMode
                          ? l10n.onboardingRecoverySheetCheckHeading
                          : l10n.onboardingRecoverySheetWhyTitle,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: RkSpace.s3),
                    if (_checkMode)
                      Text(
                        l10n.onboardingRecoverySheetCheckBody,
                        style: text.bodyLarge,
                      )
                    else ...[
                      Text(
                        l10n.onboardingRecoverySheetWhyBody,
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: RkSpace.s3),
                      Text(
                        l10n.onboardingRecoverySheetWhyBody2,
                        style: text.bodyLarge,
                      ),
                    ],
                    const SizedBox(height: RkSpace.s5),
                    const RecoverySheetPreview(),
                    const SizedBox(height: RkSpace.s3),
                    Text(
                      l10n.onboardingRecoverySheetPreviewCaption,
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(color: status.muted),
                    ),
                    ..._notes(context, l10n),
                    if (_checkMode && _typing && !_verified) ...[
                      const SizedBox(height: RkSpace.s4),
                      TextField(
                        key: const ValueKey('s0_5b.code'),
                        controller: _code,
                        autofocus: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.characters,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText:
                              l10n.onboardingRecoverySheetCheckFieldLabel,
                          hintText: l10n.onboardingRecoverySheetCheckFieldHint,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              ..._actions(context, l10n),
            ],
          ),
        ),
      ),
    );
  }

  bool get _verified => _step == RecoverySheetStep.verified;

  List<Widget> _notes(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget gap(Widget w) => Padding(
      padding: const EdgeInsets.only(top: RkSpace.s4),
      child: w,
    );

    return [
      if (_step == RecoverySheetStep.making ||
          _step == RecoverySheetStep.finding ||
          (_busy && _checkMode))
        gap(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LinearProgressIndicator(
                minHeight: RkMotion.loaderTrackHeight,
              ),
              const SizedBox(height: RkSpace.s2),
              Text(switch (_step) {
                RecoverySheetStep.finding =>
                  l10n.onboardingRecoverySheetCheckLoading,
                RecoverySheetStep.making =>
                  l10n.onboardingRecoverySheetGenerating,
                _ => l10n.onboardingRecoverySheetCheckChecking,
              }, style: text.bodySmall?.copyWith(color: status.muted)),
            ],
          ),
        ),
      if (_step == RecoverySheetStep.findFailed)
        gap(
          _Note(
            icon: Icons.cloud_off_outlined,
            color: scheme.error,
            text: l10n.onboardingRecoverySheetCheckLoadFailed,
          ),
        ),
      if (_verified)
        gap(
          _Note(
            icon: Icons.check_circle_outline,
            color: status.success,
            text: l10n.onboardingRecoverySheetCheckVerified,
          ),
        ),
      if (_checkMode && !_verified && _checked != null)
        gap(_checkFailure(context, l10n, _checked!)),
    ];
  }

  Widget _checkFailure(
    BuildContext context,
    AppLocalizations l10n,
    RecoverySheetCheckResult r,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    switch (r) {
      case RecoverySheetCheckResult.didNotOpen:
        // R2.4b: never a blank error — both likely causes, newer sheet first.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Note(
              icon: Icons.error_outline,
              color: scheme.error,
              text: l10n.onboardingRecoverySheetCheckFailedTitle,
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              l10n.onboardingRecoverySheetCheckFailedNewer,
              style: text.bodyMedium,
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              l10n.onboardingRecoverySheetCheckFailedTypo,
              style: text.bodyMedium,
            ),
          ],
        );
      case RecoverySheetCheckResult.otherAccount:
        return _Note(
          icon: Icons.error_outline,
          color: scheme.error,
          text: l10n.onboardingRecoverySheetCheckOtherAccount,
        );
      case RecoverySheetCheckResult.noSheet:
        return _Note(
          icon: Icons.info_outline,
          color: status.pending,
          text: l10n.onboardingRecoverySheetCheckNoSheet,
        );
      case RecoverySheetCheckResult.couldNotCheck:
        return _Note(
          icon: Icons.cloud_off_outlined,
          color: scheme.error,
          text: l10n.onboardingRecoverySheetCheckCouldNotCheck,
        );
      case RecoverySheetCheckResult.noCamera:
        return _Note(
          icon: Icons.no_photography_outlined,
          color: status.pending,
          text: l10n.onboardingRecoverySheetCheckNoCamera,
        );
      case RecoverySheetCheckResult.opens:
      case RecoverySheetCheckResult.cancelled:
        return const SizedBox.shrink();
    }
  }

  static String _notMadeText(
    AppLocalizations l10n,
    RecoverySheetNotMadeReason r,
  ) => switch (r) {
    RecoverySheetNotMadeReason.offline =>
      l10n.onboardingRecoverySheetErrorOffline,
    RecoverySheetNotMadeReason.notSignedIn =>
      l10n.onboardingRecoverySheetErrorNotSignedIn,
    RecoverySheetNotMadeReason.tooMany =>
      l10n.onboardingRecoverySheetErrorTooMany,
    RecoverySheetNotMadeReason.needsUpdate =>
      l10n.onboardingRecoverySheetErrorNeedsUpdate,
    RecoverySheetNotMadeReason.server =>
      l10n.onboardingRecoverySheetErrorServer,
  };

  List<Widget> _actions(BuildContext context, AppLocalizations l10n) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final service = widget.service;
    Widget reason(String s) => Padding(
      padding: const EdgeInsets.only(top: RkSpace.s2),
      child: Text(
        s,
        textAlign: TextAlign.center,
        style: text.bodySmall?.copyWith(color: status.muted),
      ),
    );

    if (_step == RecoverySheetStep.finding ||
        _step == RecoverySheetStep.findFailed) {
      return [
        FilledButton(
          onPressed: _step == RecoverySheetStep.findFailed ? _find : null,
          child: Text(l10n.onboardingRecoverySheetRetry),
        ),
      ];
    }

    if (_checkMode) {
      if (_verified) {
        return [
          FilledButton(
            onPressed: widget.onDone,
            child: Text(l10n.onboardingRecoverySheetDone),
          ),
        ];
      }
      final typed = _code.text.trim().isNotEmpty;
      return [
        if (_typing)
          FilledButton(
            onPressed: _busy || !typed
                ? null
                : () => _runCheck((s) => s.checkTyped(_code.text)),
            child: Text(l10n.onboardingRecoverySheetCheckSubmit),
          )
        else ...[
          FilledButton(
            onPressed: _busy ? null : () => _runCheck((s) => s.scan()),
            child: Text(l10n.onboardingRecoverySheetCheckScan),
          ),
          const SizedBox(height: RkSpace.s3),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _typing = true);
                    _revealNotes();
                  },
            child: Text(l10n.onboardingRecoverySheetCheckType),
          ),
        ],
        TextButton(
          onPressed: _busy ? null : _makeNew,
          child: Text(l10n.onboardingRecoverySheetCheckMakeNew),
        ),
      ];
    }

    final opened = _step == RecoverySheetStep.opened;
    final failed = _step == RecoverySheetStep.notMade;
    final scheme = Theme.of(context).colorScheme;
    // ADR 2026-10-06d ruling 3 — a failed make *shows its reason*: pinned
    // directly above *Try again*, outside the scrolling page, so no text
    // size or screen height can push it below the fold (13 §4.3).
    final problem = failed && _notMade != null
        ? _notMadeText(l10n, _notMade!)
        : _openFailed
        ? l10n.onboardingRecoverySheetOpenFailed
        : null;
    return [
      if (problem != null)
        Padding(
          padding: const EdgeInsets.only(bottom: RkSpace.s3),
          child: _Note(
            icon: Icons.error_outline,
            color: scheme.error,
            text: problem,
          ),
        ),
      FilledButton(
        onPressed: service == null || _busy ? null : _printOrSave,
        child: Text(
          failed
              ? l10n.onboardingRecoverySheetRetry
              : l10n.onboardingRecoverySheetPrint,
        ),
      ),
      // 13 §4.3 disabled-with-reason: with no sheet maker on this phone the
      // reason sits directly under the sleeping button, as O5b sets its own.
      if (service == null) reason(l10n.onboardingRecoverySheetUnavailable),
      const SizedBox(height: RkSpace.s3),
      OutlinedButton(
        onPressed: opened && !_busy ? widget.onDone : null,
        child: Text(l10n.onboardingRecoverySheetKeptSafe),
      ),
      if (!opened) reason(l10n.onboardingRecoverySheetKeptSafeAsleep),
      // ADR 2026-10-07 ruling 1: required — *Skip for now* only beside a
      // failed publish (ADR 2026-10-06d ruling 3) or with no maker at all.
      if (failed || service == null)
        TextButton(
          onPressed: widget.onSkip,
          child: Text(l10n.onboardingRecoverySheetSkip),
        ),
    ];
  }
}

/// O5b's drawing of the printed A4 page: the header, the square, two masked
/// code lines and the instruction rules. Never the person's own code.
class RecoverySheetPreview extends StatelessWidget {
  const RecoverySheetPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final pageWidth = _pageWidth;
    return Semantics(
      label: l10n.onboardingRecoverySheetPreviewSemantics,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: RkSpace.s4),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: status.hairline),
        ),
        alignment: Alignment.center,
        child: Container(
          width: pageWidth,
          height: pageWidth * _a4Ratio,
          padding: const EdgeInsets.fromLTRB(
            RkSpace.s3,
            RkSpace.s4,
            RkSpace.s3,
            RkSpace.s3,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: status.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.onboardingRecoverySheetPdfTitle.toUpperCase(),
                  maxLines: 1,
                  style: text.labelSmall?.copyWith(
                    color: status.muted,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              Center(
                child: Container(
                  width: _qrSide,
                  height: _qrSide,
                  color: scheme.onSurface.withValues(alpha: 0.86),
                ),
              ),
              const SizedBox(height: RkSpace.s3),
              for (var i = 0; i < 2; i++)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _masked,
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: text.bodyMedium?.copyWith(
                      letterSpacing: 1.5,
                      height: 1.4,
                    ),
                  ),
                ),
              const SizedBox(height: RkSpace.s3),
              for (final f in const [1.0, 0.92, 0.8])
                Padding(
                  padding: const EdgeInsets.only(bottom: RkSpace.s1),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: f,
                    child: Container(
                      height: RkIcon.stroke,
                      color: status.hairline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Drawing proportions of O5b's page (177 × 232 at 390 wide; A4 is √2).
  static const double _pageWidth = 178;
  static const double _a4Ratio = 1.31;
  static const double _qrSide = 74;
  static const String _masked = '••••  ••••';
}

/// A one-line note: icon **and** text, never colour alone (07 §1 rule 3).
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: RkIcon.grid - RkSpace.s2, color: color),
        const SizedBox(width: RkSpace.s2),
        Expanded(
          child: Text(text, style: theme.bodyMedium?.copyWith(color: color)),
        ),
      ],
    );
  }
}
