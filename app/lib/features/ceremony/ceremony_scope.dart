// What the ceremony routes need, handed down rather than constructed in a
// route builder: the two repositories (04 §6.2's two sides) and the camera.
//
// ⚠️ WIRE — the tenant lane (S9 Members) pushes S9.2/S9.3 with the invite
// already chosen, so it is the natural place to install this scope. Until it
// does, the routes below render nothing rather than inventing an invite: a
// ceremony with a made-up nonce would be worse than no screen.
import 'package:flutter/widgets.dart';

import 'camera_scanner.dart';
import 'ceremony_repository.dart';

/// The ceremony's dependencies for the current invite.
class CeremonyScope extends InheritedWidget {
  /// Installs the seams above the ceremony screens.
  const CeremonyScope({
    super.key,
    this.showMyCode,
    this.verifyMember,
    this.scanner,
    required super.child,
  });

  /// S9.2's side; null until an invite is in hand.
  final ShowMyCodeRepository? showMyCode;

  /// S9.3's side; null until an invite is in hand.
  final VerifyMemberRepository? verifyMember;

  /// The camera seam; [NoCameraScanner] when nothing supplies one.
  final CeremonyScanner? scanner;

  /// The nearest scope, or null.
  static CeremonyScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CeremonyScope>();

  @override
  bool updateShouldNotify(CeremonyScope old) =>
      showMyCode != old.showMyCode ||
      verifyMember != old.verifyMember ||
      scanner != old.scanner;
}
