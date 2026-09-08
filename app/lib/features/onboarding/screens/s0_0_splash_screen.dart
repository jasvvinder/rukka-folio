// S0.0 Splash (13 §3.2, 07 §3.1 step 2, ADR 2026-09-03d). Sealed mark +
// stacked lockup on paper; OS launch frame and first app frame are meant to
// be pixel-identical (this widget IS that first frame). No spinner anywhere
// — the only loader is the 2px hairline rule, shown past 3s. By session
// state (ADR 2026-09-03d rule 3): locked → nothing plays; open session →
// sealed→open once; failed auth → sealed, shake; slow cold start (>3s) →
// loader rule fades in with "Opening your books." Jump cut under
// `prefers-reduced-motion`, never decoratively (07 §3.1 step 2).
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../widgets/sealed_mark.dart';

/// The session state the splash animates for (ADR 2026-09-03d rule 3).
enum RkSplashSession {
  /// No open session yet (fresh install, or the app lock is showing next) —
  /// the mark stays sealed and nothing plays.
  locked,

  /// A session is already open — the seal breaks once, then [onFinished].
  open,

  /// The unlock attempt that led here failed — sealed mark shakes, stays
  /// sealed; no [onFinished] (there is nowhere forward yet).
  failedAuth,
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.session = RkSplashSession.locked,
    this.onFinished,
    this.ready,
    this.reducedMotion = false,
    this.slowThreshold = RkMotion.splashSlowStart,
  });

  /// Which animation branch to play.
  final RkSplashSession session;

  /// Called once the splash has finished (locked: immediately once [ready]
  /// resolves; open: after the unlock animation). Never called for
  /// [RkSplashSession.failedAuth] — that branch has nowhere to go yet.
  final VoidCallback? onFinished;

  /// Resolves when the app has decided where to go next (auth/session
  /// check). Splash waits on this before animating away. Defaults to an
  /// already-resolved future, i.e. no artificial delay (ADR 2026-09-03d
  /// rule 3: "never an artificial delay to finish the animation").
  final Future<void>? ready;

  /// `prefers-reduced-motion` — jump cuts every animation.
  final bool reducedMotion;

  /// Past this, the loader rule fades in with a status line (default 3s).
  final Duration slowThreshold;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  double _sealOpacity = 1;
  bool _slow = false;
  bool _shaking = false;
  double _shakeOffset = 0;
  Timer? _slowTimer;
  Ticker? _shakeTicker;

  @override
  void initState() {
    super.initState();
    if (!widget.reducedMotion) {
      _slowTimer = Timer(widget.slowThreshold, () {
        if (mounted) setState(() => _slow = true);
      });
    }
    _run();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _shakeTicker?.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    await (widget.ready ?? Future<void>.value());
    if (!mounted) return;
    switch (widget.session) {
      case RkSplashSession.locked:
        _finish();
      case RkSplashSession.open:
        await _playUnlock();
        _finish();
      case RkSplashSession.failedAuth:
        await _playShake();
    }
  }

  void _finish() {
    _slowTimer?.cancel();
    if (mounted) setState(() => _slow = false);
    widget.onFinished?.call();
  }

  Future<void> _playUnlock() async {
    if (widget.reducedMotion) {
      if (mounted) setState(() => _sealOpacity = 0);
      return;
    }
    if (mounted) setState(() => _sealOpacity = 0);
    await Future<void>.delayed(RkMotion.markUnlockTotal);
  }

  Future<void> _playShake() async {
    _slowTimer?.cancel();
    if (mounted) setState(() => _slow = false);
    if (widget.reducedMotion) return;
    final completer = Completer<void>();
    setState(() => _shaking = true);
    final start = DateTime.now();
    final total = RkMotion.failShake * RkMotion.failShakeCycles.toDouble();
    _shakeTicker = createTicker((elapsed) {
      final t = DateTime.now().difference(start);
      if (t >= total) {
        _shakeTicker?.stop();
        setState(() {
          _shaking = false;
          _shakeOffset = 0;
        });
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final phase =
          t.inMicroseconds / RkMotion.failShake.inMicroseconds * 2 * math.pi;
      setState(
        () => _shakeOffset = math.sin(phase) * RkMotion.failShakeAmplitudeUnits,
      );
    })..start();
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final name = l10n.appName;
    final space = name.indexOf(' ');
    final first = space < 0 ? name : name.substring(0, space);
    final rest = space < 0 ? '' : name.substring(space);
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Semantics(
        label: l10n.appName,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(_shakeOffset, 0),
                child: SealedMark(sealOpacity: _sealOpacity),
              ),
              const SizedBox(height: RkSpace.s6),
              Text.rich(
                TextSpan(
                  style: text.displayLarge,
                  children: [
                    TextSpan(text: first),
                    TextSpan(
                      text: rest,
                      style: const TextStyle(fontWeight: FontWeight.w300),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              AnimatedOpacity(
                opacity: _slow ? 1 : 0,
                duration: widget.reducedMotion ? Duration.zero : RkMotion.m,
                child: Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s10),
                  child: Semantics(
                    liveRegion: true,
                    label: _slow ? l10n.splashOpening : null,
                    child: SizedBox(
                      width: 160,
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              RkMotion.loaderTrackHeight,
                            ),
                            child: LinearProgressIndicator(
                              minHeight: RkMotion.loaderTrackHeight,
                              backgroundColor: status.loaderTrack,
                              color: status.loaderSegment,
                              value: widget.reducedMotion ? 0.25 : null,
                            ),
                          ),
                          const SizedBox(height: RkSpace.s3),
                          Text(l10n.splashOpening, style: text.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
