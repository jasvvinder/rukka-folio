// One QR read, full screen — what a recovery scan opens (S11.2 *Scan their
// screen*, S11.3 *Scan the square code*, S11.7 *Scan their new phone*;
// ADR 2026-09-19 ruling 1 🔒).
//
// It reads until the caller's `decode` accepts a code, and pops with that one
// value. Three rules make it safe to hand key-bearing text through:
//
//   * **A code `decode` refuses is not an answer.** A stray QR — a shop's
//     payment sticker, another app's code — draws a one-line notice and the
//     camera keeps looking. It can neither pass a check nor fail one; only a
//     code of the right *kind* reaches the comparison, which is `core_crypto`'s
//     and happens behind the seam after this screen has gone.
//   * **No camera is an answer, at once.** Denied, absent or busy, the screen
//     pops with [QrScanNoCamera] before anything is drawn over it, so the
//     calling screen renders its own stated way out — never a dead preview
//     (07 §1 rule 6 🔒).
//   * **Nothing is shown or kept.** The decoded value goes to [Navigator.pop]
//     and nowhere else: no text of it on screen, no log (CLAUDE.md rule 4).
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../camera_scanner.dart';
import '../widgets/viewfinder.dart';

/// How [QrScanScreen] ended, when it did not end with the person backing out
/// (which pops `null`).
sealed class QrScanResult<T extends Object> {
  const QrScanResult();
}

/// A code was read and accepted.
final class QrScanned<T extends Object> extends QrScanResult<T> {
  /// Wraps the decoded value.
  const QrScanned(this.value);

  /// What `decode` made of it.
  final T value;
}

/// The camera could not start — [status] says why.
final class QrScanNoCamera<T extends Object> extends QrScanResult<T> {
  /// Wraps the reason.
  const QrScanNoCamera(this.status);

  /// [CameraStatus.denied] or [CameraStatus.unavailable].
  final CameraStatus status;
}

/// The full-screen single read.
class QrScanScreen<T extends Object> extends StatefulWidget {
  /// Reads with [scanner] (which this screen disposes) until [decode] accepts
  /// a code. [decode] answers null for a code of the wrong kind; a throw is
  /// read the same way.
  const QrScanScreen({super.key, required this.scanner, required this.decode});

  /// The camera, owned by this screen from now on.
  final CeremonyScanner scanner;

  /// Turns scanned text into the value the caller wants, or null.
  final T? Function(String text) decode;

  @override
  State<QrScanScreen<T>> createState() => _QrScanScreenState<T>();
}

class _QrScanScreenState<T extends Object> extends State<QrScanScreen<T>> {
  StreamSubscription<String>? _reads;
  bool _wrongCode = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final status = await widget.scanner.start();
    if (!mounted || _done) return;
    if (status != CameraStatus.ready) {
      _finish(QrScanNoCamera<T>(status));
      return;
    }
    _reads = widget.scanner.codes.listen(_onRead);
  }

  void _onRead(String text) {
    if (_done) return;
    T? value;
    try {
      value = widget.decode(text);
    } on Object {
      value = null;
    }
    if (value == null) {
      if (!_wrongCode) setState(() => _wrongCode = true);
      return;
    }
    _finish(QrScanned<T>(value));
  }

  void _finish(QrScanResult<T>? result) {
    if (_done) return;
    _done = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    unawaited(_reads?.cancel());
    unawaited(widget.scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: l10n.ceremonyScanClose,
          onPressed: () => _finish(null),
        ),
        title: RkFitText(l10n.ceremonyScanTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s6,
            RkSpace.gutter,
            RkSpace.s8,
          ),
          children: [
            CeremonyViewfinder(child: widget.scanner.buildPreview(context)),
            const SizedBox(height: RkSpace.s4),
            Text(
              l10n.ceremonyScanHint,
              textAlign: TextAlign.center,
              style: text.bodyLarge,
            ),
            if (_wrongCode) ...[
              const SizedBox(height: RkSpace.s3),
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.qr_code_2_outlined, color: status.warning),
                    const SizedBox(width: RkSpace.s2),
                    Expanded(
                      child: Text(
                        l10n.ceremonyScanWrongCode,
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
