// Auto-lock, driven from the shell (06 §4.5 background default 2 min · ADR
// 2026-09-05 §7 foreground idle 5 min, both configurable in the one *Auto-lock*
// setting, 07 §15/§16).
//
// Two clocks, one destination (S15):
//   * **background** — the app leaves the foreground; after the timeout it is
//     locked, whether or not the timer survived the suspension (a phone that
//     froze our timers is checked against the injected clock on resume).
//   * **idle** — no touch anywhere in the app for the idle timeout.
//
// 🔒 07 §5.6: the idle lock is "suppressed while a draft has digits typed".
// ⚠️ SPEC: neither 07 §5.6, 06 §4.5 nor ADR 2026-09-05 §7 extends that
// suppression to the *background* timeout, and extending it would mean a phone
// put down mid-entry never locks at all — the conservative reading is that the
// background lock always fires. The draft is not lost either way (ADR
// 2026-09-05 §7: the lock never discards work), so nothing is at stake but the
// lock. [suppressBackgroundWhileDrafting] exists only so the owner can flip
// the reading without touching the timers.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'draft_activity.dart';

/// Whether the app is locked right now. The shell listens and pushes S15; the
/// lock screen calls [unlock] when the person is through.
class AppLockState extends ChangeNotifier {
  /// Starts unlocked; the shell locks it on cold start when a PIN is set.
  AppLockState();

  bool _locked = false;

  /// True while S15 should be covering the app.
  bool get locked => _locked;

  /// Locks; a no-op when already locked, so a timer racing a lifecycle change
  /// cannot push S15 twice.
  void lock() {
    if (_locked) return;
    _locked = true;
    notifyListeners();
  }

  /// Unlocked — the app returns exactly where it was (ADR 2026-09-05 §7).
  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }
}

/// Watches touches and the app lifecycle and locks [lock] when either timeout
/// runs out. Mount it once, above the app.
class RkAutoLock extends StatefulWidget {
  /// Wraps [child].
  const RkAutoLock({
    super.key,
    required this.child,
    required this.lock,
    required this.now,
    this.idleTimeout = const Duration(minutes: 5),
    this.backgroundTimeout = const Duration(minutes: 2),
    this.draft,
    this.enabled = true,
    this.suppressBackgroundWhileDrafting = false,
  });

  /// The app.
  final Widget child;

  /// The state this drives.
  final AppLockState lock;

  /// Injected clock (CLAUDE.md rule 3) — used to measure a suspension the
  /// timers slept through.
  final DateTime Function() now;

  /// No touch for this long in the foreground locks (ADR 2026-09-05 §7).
  final Duration idleTimeout;

  /// This long out of the foreground locks (06 §4.5).
  final Duration backgroundTimeout;

  /// The draft signal; null means nothing can suppress the idle lock.
  final DraftActivity? draft;

  /// False while no PIN is set — there is nothing to unlock with, and a lock
  /// screen that cannot be passed is a dead end (07 §1 rule 6).
  final bool enabled;

  /// See the file header: off by the conservative reading of 07 §5.6.
  final bool suppressBackgroundWhileDrafting;

  @override
  State<RkAutoLock> createState() => RkAutoLockState();
}

/// Public so a host or a test can read the timers' state.
class RkAutoLockState extends State<RkAutoLock> with WidgetsBindingObserver {
  Timer? _idle;
  Timer? _background;
  DateTime? _leftForeground;

  /// True while a draft is holding digits.
  bool get drafting => widget.draft?.hasDigits ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.lock.addListener(_onLockChanged);
    _restartIdle();
  }

  @override
  void didUpdateWidget(RkAutoLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (old.lock != widget.lock) {
      old.lock.removeListener(_onLockChanged);
      widget.lock.addListener(_onLockChanged);
    }
    if (old.idleTimeout != widget.idleTimeout ||
        old.enabled != widget.enabled) {
      _restartIdle();
    }
  }

  @override
  void dispose() {
    widget.lock.removeListener(_onLockChanged);
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    _background?.cancel();
    super.dispose();
  }

  void _onLockChanged() {
    if (widget.lock.locked) {
      _idle?.cancel();
      _idle = null;
    } else {
      _restartIdle();
    }
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = null;
    if (!widget.enabled || widget.lock.locked) return;
    if (_leftForeground != null) return;
    _idle = Timer(widget.idleTimeout, _onIdleElapsed);
  }

  void _onIdleElapsed() {
    // 🔒 07 §5.6: never while digits are waiting in a draft — the clock simply
    // starts again.
    if (drafting) {
      _restartIdle();
      return;
    }
    if (widget.enabled) widget.lock.lock();
  }

  void _onBackgroundElapsed() {
    if (widget.suppressBackgroundWhileDrafting && drafting) return;
    if (widget.enabled) widget.lock.lock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final left = _leftForeground;
      _leftForeground = null;
      _background?.cancel();
      _background = null;
      // The timer may have been frozen with the process; the clock was not.
      if (left != null &&
          widget.now().difference(left) >= widget.backgroundTimeout) {
        _onBackgroundElapsed();
      }
      _restartIdle();
      return;
    }
    // Anything that is not `resumed` counts as out of the foreground, and the
    // first such state starts the clock — `inactive` then `paused` is one
    // departure, not two.
    if (_leftForeground != null) return;
    _leftForeground = widget.now();
    _idle?.cancel();
    _idle = null;
    if (!widget.enabled) return;
    _background = Timer(widget.backgroundTimeout, _onBackgroundElapsed);
  }

  void _touched([PointerEvent? _]) {
    if (widget.lock.locked || _leftForeground != null) return;
    _restartIdle();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _touched,
      onPointerMove: _touched,
      onPointerUp: _touched,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
