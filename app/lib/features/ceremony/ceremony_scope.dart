// What the ceremony routes need, handed down rather than constructed in a
// route builder: the factory that opens a session (04 §6.2's two sides) and
// the camera.
//
// **Why this changed.** The scope used to carry two *finished* repositories,
// which are per-invite — so it could not be installed at the composition
// root, and nothing that held an invite installed it either. The result was a
// scope that existed nowhere and two screens that rendered a placeholder for
// three milestones. It now carries a [CeremonySessions] instead: a factory
// installs once, fabricates nothing, and mints a repository only when a real
// subject, a real server-generated nonce and a real 0007 session are in hand.
// The old rule survives intact — "a ceremony with a made-up nonce would be
// worse than no screen" — but as a type rather than a warning.
//
// The two direct repositories remain, and win when present: a caller that
// already holds one side (a test, or a flow that built it itself) hands it
// down as before.
import 'package:flutter/widgets.dart';

import 'camera_scanner.dart';
import 'ceremony_repository.dart';
import 'ceremony_sessions.dart';

/// The ceremony's dependencies.
class CeremonyScope extends InheritedWidget {
  /// Installs the seams above the ceremony screens.
  const CeremonyScope({
    super.key,
    this.sessions,
    this.showMyCode,
    this.verifyMember,
    this.scanner,
    required super.child,
  });

  /// Opens a side of the ceremony for a real subject. Null falls back to
  /// [NoCeremonySessions] — the routes then keep their placeholder, which is
  /// the honest state, never a red screen (07 §1 rule 6).
  final CeremonySessions? sessions;

  /// S9.2's side, when a caller already built it. Wins over [sessions].
  final ShowMyCodeRepository? showMyCode;

  /// S9.3's side, when a caller already built it. Wins over [sessions].
  final VerifyMemberRepository? verifyMember;

  /// The camera seam; [NoCameraScanner] when nothing supplies one.
  final CeremonyScanner? scanner;

  /// The factory to use, never null: an absent one opens nothing.
  CeremonySessions get openings => sessions ?? const NoCeremonySessions();

  /// The nearest scope, or null.
  static CeremonyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CeremonyScope>();

  @override
  bool updateShouldNotify(CeremonyScope old) =>
      sessions != old.sessions ||
      showMyCode != old.showMyCode ||
      verifyMember != old.verifyMember ||
      scanner != old.scanner;
}
