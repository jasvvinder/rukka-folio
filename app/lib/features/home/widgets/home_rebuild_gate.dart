// S1.4's gate (07 §28 🔒, ADR 2026-09-05c §3/§6): decides whether Home shows
// the book, or the determinate rebuild loader instead.
//
// Two inputs, both live:
//   • the progress seam ([RebuildProgressSource]) — non-null while a rebuild
//     is running;
//   • `books_p.integrity_ok` (via `BookHealth`), which **gates the return** to
//     the normal card: once a rebuild has been seen, the book is shown as
//     whole again only when integrity is ok (ADR 2026-09-05c §6). A rebuild
//     that ends with integrity still off leaves S1.4 up rather than showing
//     half a book.
//
// A book that never rebuilt is never gated: integrity off on its own is the
// verification card's business (07 §4), not S1.4's.
import 'dart:async';

import 'package:flutter/material.dart';

import '../home_rebuild.dart';

/// Shows [rebuilding] while the book is rebuilding, and [book] otherwise.
class HomeRebuildGate extends StatefulWidget {
  /// Creates the gate.
  const HomeRebuildGate({
    super.key,
    required this.progress,
    required this.integrityOk,
    required this.rebuilding,
    required this.book,
  });

  /// Live rebuild readings for the book; `null` events mean "not rebuilding".
  final Stream<RebuildProgress?> progress;

  /// Live `integrity_ok` for the same book.
  final Stream<bool> integrityOk;

  /// Builds S1.4 for the reading in hand.
  final Widget Function(BuildContext context, RebuildProgress progress)
  rebuilding;

  /// The normal Home body. A builder, not a widget: the body's projection
  /// stream is single-subscription, so coming back from S1.4 has to build a
  /// fresh one rather than re-listen to the cancelled stream.
  final WidgetBuilder book;

  @override
  State<HomeRebuildGate> createState() => _HomeRebuildGateState();
}

class _HomeRebuildGateState extends State<HomeRebuildGate> {
  StreamSubscription<RebuildProgress?>? _progressSub;
  StreamSubscription<bool>? _healthSub;
  RebuildProgress? _current;
  RebuildProgress? _last;
  bool _held = false;
  bool _ok = true;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(HomeRebuildGate old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress ||
        old.integrityOk != widget.integrityOk) {
      _cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _progressSub = widget.progress.listen((p) {
      setState(() {
        _current = p;
        if (p != null) {
          _last = p;
          _held = true;
        } else if (_ok) {
          _held = false;
        }
      });
    });
    _healthSub = widget.integrityOk.listen((ok) {
      setState(() {
        _ok = ok;
        if (ok && _current == null) _held = false;
      });
    });
  }

  // Deliberately synchronous: awaiting a drift query stream's cancel inside
  // disposal deadlocks flutter_test's fake-async zone (the U2a finding).
  void _cancel() {
    unawaited(_progressSub?.cancel());
    unawaited(_healthSub?.cancel());
    _progressSub = null;
    _healthSub = null;
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_held) return widget.book(context);
    final reading = _current ?? _last;
    if (reading == null) return widget.book(context);
    return widget.rebuilding(context, reading);
  }
}
