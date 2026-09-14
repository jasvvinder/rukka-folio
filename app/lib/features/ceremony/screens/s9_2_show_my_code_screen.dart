// S9.2 Show my code (13 §3.2, 07 §12 🔒, 04 §6.2) — the invitee's side.
//
// 🔒 A huge QR with the 8-digit code beneath it, rendered as eight separate
// character boxes with a visible expiry countdown (07 §12, owner-approved).
// Presentation only: both halves are derived in `core_crypto` (04 §6.1) and
// handed here as [MyCode]. Nothing on this screen is a password and nothing on
// it is generated in a widget.
//
// 🔒 **The boxes stand empty until the verifier begins** (04 §6.2, §6.1 as
// amended by ADR 2026-09-13d §5, ratified 13 Sep 2026). The code is a
// commitment-based SAS over *both* devices' randomness, so before the
// verifier's `r_V` has been relayed there are no digits to show — not hidden,
// not loading: they do not exist. The square does not wait for anyone, which
// is why it is drawn from the first frame and the waiting line sits under it
// rather than over the whole screen.
//
// 🔒 No share button, no copy affordance — 04 §6.4's channel rule. The code
// must travel over a channel where the verifier recognises the *person*; a
// forwarded message hands it to exactly the attacker the ceremony stops.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../ceremony_repository.dart';
import '../widgets/code_boxes.dart';
import '../widgets/qr_view.dart';

/// The states of S9.2 (13 §4.3).
enum ShowMyCodeState {
  /// Opening the session — drawing `r_S`, relaying the commitment.
  loading,

  /// The square is up and the session is live, but the verifier has not begun:
  /// the eight boxes are empty because the digits do not exist yet
  /// (ADR 2026-09-13d §5 🔒).
  waitingForVerifier,

  /// QR and digits are on screen.
  ready,

  /// Past the nonce's ten minutes (04 §6.3) — *Get a new code*.
  expired,

  /// The call failed; retry is the one next step.
  error,
}

/// S9.2.
class ShowMyCodeScreen extends StatefulWidget {
  /// [repository] derives the code; [now] is the injected clock (never
  /// `DateTime.now()` in a widget); [offline] draws the quiet chip of
  /// 07 §1 rule 7.
  const ShowMyCodeScreen({
    super.key,
    required this.repository,
    required this.now,
    this.offline = false,
    this.encode = QrModules.of,
  });

  /// The seam over `core_crypto` and the ceremony session on the server.
  final ShowMyCodeRepository repository;

  /// Injected clock.
  final DateTime Function() now;

  /// Quiet offline chip — the code keeps working, so this never blocks.
  final bool offline;

  /// How a payload becomes a module matrix; swapped in tests.
  final QrModules Function(String payload) encode;

  @override
  State<ShowMyCodeScreen> createState() => _ShowMyCodeScreenState();
}

class _ShowMyCodeScreenState extends State<ShowMyCodeScreen> {
  ShowMyCodeState _state = ShowMyCodeState.loading;
  MyCode? _code;
  QrModules? _modules;
  Timer? _tick;

  /// Which session's answers this screen still wants. *Regenerate* opens a new
  /// one (a new `r_S`, ADR 2026-09-13d §2), and the old session's `r_V` may
  /// still be in flight — it belongs to a commitment nobody will open, so it
  /// is dropped rather than shown.
  int _session = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Duration get _left {
    final code = _code;
    if (code == null) return Duration.zero;
    final left = code.expiresAt.difference(widget.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> _load({bool fresh = false}) async {
    final session = ++_session;
    setState(() => _state = ShowMyCodeState.loading);
    try {
      final code = fresh
          ? await widget.repository.regenerate()
          : await widget.repository.load();
      if (!mounted || session != _session) return;
      setState(() => _show(code));
      _startTicking();
      // The session is open and the commitment relayed; the digits arrive when
      // the verifier's contribution does (ADR 2026-09-13d §1 step 3).
      if (code.isWaiting) unawaited(_awaitVerifier(session));
    } on CeremonyFailure {
      if (!mounted || session != _session) return;
      setState(() => _state = ShowMyCodeState.error);
    }
  }

  /// Waits for `r_V`. The invitee does nothing while this runs: the square is
  /// already scannable, so this is the slow path staying out of the way of the
  /// fast one.
  Future<void> _awaitVerifier(int session) async {
    try {
      final code = await widget.repository.awaitVerifier();
      if (!mounted || session != _session) return;
      setState(() => _show(code));
      _startTicking();
    } on CeremonyFailure {
      if (!mounted || session != _session) return;
      setState(() => _state = ShowMyCodeState.error);
    }
  }

  /// Puts [code] on screen in the state its own contents imply — never a state
  /// the widget decided for itself.
  void _show(MyCode code) {
    _code = code;
    _modules = widget.encode(code.qrPayload);
    _state = _left == Duration.zero
        ? ShowMyCodeState.expired
        : code.isWaiting
        ? ShowMyCodeState.waitingForVerifier
        : ShowMyCodeState.ready;
  }

  /// One tick a second, only while a session is live — a countdown that stops
  /// at zero rather than a timer that outlives the screen. It runs while the
  /// screen waits too: the ten minutes are the commitment's, and they are
  /// already running (04 §6.3, ADR 2026-09-13d §3).
  void _startTicking() {
    _tick?.cancel();
    if (_state != ShowMyCodeState.ready &&
        _state != ShowMyCodeState.waitingForVerifier) {
      return;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_left == Duration.zero) {
          _state = ShowMyCodeState.expired;
          _tick?.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ceremonyShowTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter)
              .copyWith(top: RkSpace.s4, bottom: RkSpace.s8),
          child: switch (_state) {
            ShowMyCodeState.loading => const _ShowMyCodeSkeleton(),
            ShowMyCodeState.error => _ShowMyCodeError(onRetry: _load),
            ShowMyCodeState.waitingForVerifier ||
            ShowMyCodeState.ready ||
            ShowMyCodeState.expired => _ShowMyCodeBody(
              code: _code!,
              modules: _modules!,
              left: _left,
              expired: _state == ShowMyCodeState.expired,
              verifierName: widget.repository.verifierName,
              offline: widget.offline,
              onRegenerate: () => _load(fresh: true),
            ),
          },
        ),
      ),
    );
  }
}

class _ShowMyCodeBody extends StatelessWidget {
  const _ShowMyCodeBody({
    required this.code,
    required this.modules,
    required this.left,
    required this.expired,
    required this.verifierName,
    required this.offline,
    required this.onRegenerate,
  });

  final MyCode code;
  final QrModules modules;
  final Duration left;
  final bool expired;
  final String verifierName;
  final bool offline;
  final VoidCallback onRegenerate;

  /// The square's side: the full column width, capped against the viewport
  /// height so nothing below it falls off the first screen.
  static double _qrSide(BuildContext context, {required bool expired}) {
    final media = MediaQuery.sizeOf(context);
    final width = media.width - RkSpace.gutter * 2;
    final cap = media.height * (expired ? 0.24 : 0.42);
    return width < cap ? width : cap;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final digits = code.digits;
    final waiting = digits == null && !expired;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.ceremonyShowBody, style: theme.textTheme.bodyLarge),
        const SizedBox(height: RkSpace.s4),
        // As big as the phone allows — the QR is the fast path, and a scan off
        // a video call (04 §6.4 remote) needs every module it can get — but
        // bounded by the height too, so the digits, the countdown and the one
        // next step stay on the first screen rather than one scroll below it.
        // Once the nonce is dead the square is dead with it, so it shrinks and
        // gives the room to *Get a new code*.
        Center(
          child: SizedBox.square(
            dimension: _qrSide(context, expired: expired),
            child: Opacity(
              opacity: expired ? 0.4 : 1,
              child: RkQrView(
                modules: modules,
                semanticsLabel: l10n.ceremonyShowQrSemantics,
              ),
            ),
          ),
        ),
        const SizedBox(height: RkSpace.s6),
        // Waiting is a state of the *code*, not of the screen: the square above
        // is live throughout, so only this block changes (ADR 2026-09-13d §5).
        Semantics(
          liveRegion: waiting,
          child: Text(
            waiting
                ? l10n.ceremonyShowWaitingTitle(verifierName)
                : l10n.ceremonyShowCodeLabel,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: RkSpace.s3),
        RkCodeBoxes(
          // Empty, because before the verifier's contribution arrives there is
          // no code — not a hidden one, not a loading one.
          digits: digits ?? '',
          muted: expired,
          semanticsLabel: digits == null
              ? l10n.ceremonyShowWaitingSemantics(verifierName)
              : l10n.ceremonyShowCodeSemantics(digits),
        ),
        if (waiting) ...[
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.ceremonyShowWaitingWhy,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
          ),
        ],
        const SizedBox(height: RkSpace.s3),
        RkCodeExpiry(left: left),
        if (expired) ...[
          const SizedBox(height: RkSpace.s4),
          FilledButton(
            onPressed: onRegenerate,
            child: Text(l10n.ceremonyShowRegenerate),
          ),
        ],
        const SizedBox(height: RkSpace.s6),
        // Why there is no share button, said out loud rather than left as an
        // absence (04 §6.4 🔒).
        DecoratedBox(
          decoration: BoxDecoration(
            color: status.sunk,
            borderRadius: BorderRadius.circular(RkRadius.md),
            border: Border(
              left: BorderSide(
                color: status.warning,
                width: RkRadius.ruleLeftWidth,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(RkSpace.cardPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: RkIcon.grid,
                  color: status.warning,
                ),
                const SizedBox(width: RkSpace.s3),
                Expanded(
                  child: Text(
                    l10n.ceremonyShowChannelRule,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (offline) ...[
          const SizedBox(height: RkSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: RkIcon.grid,
                color: status.muted,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: Text(
                  l10n.ceremonyShowOffline,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: status.muted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The ruled skeleton (11 §4.5): the square's footprint and the eight boxes,
/// at true size, so nothing moves when the code arrives.
class _ShowMyCodeSkeleton extends StatelessWidget {
  const _ShowMyCodeSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: status.skeletonLabel,
              borderRadius: BorderRadius.circular(RkRadius.md),
            ),
          ),
        ),
        const SizedBox(height: RkSpace.s6),
        const RkCodeBoxes(digits: ''),
        const SizedBox(height: RkSpace.s4),
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.ceremonyShowLoading,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
          ),
        ),
      ],
    );
  }
}

class _ShowMyCodeError extends StatelessWidget {
  const _ShowMyCodeError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RkSpace.s8),
        Icon(Icons.error_outline, size: RkSpace.s12, color: status.warning),
        const SizedBox(height: RkSpace.s4),
        Text(
          l10n.ceremonyShowError,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: RkSpace.s4),
        FilledButton(
          onPressed: () => unawaited(onRetry()),
          child: Text(l10n.ceremonyShowRetry),
        ),
      ],
    );
  }
}
