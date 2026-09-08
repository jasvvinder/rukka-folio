// The 24 h cancel window (ADR 2026-09-05d §1, §3): guardian recovery or a
// guardian-approved phone change while the owner still has a device, and a
// support-initiated device revocation. Pure with respect to time — every
// query takes `now` from the injected clock (rule 3), so ADR 2026-09-05i §9's
// clock-jump cases hold: completes at 24 h, cancel at 23 h 59 still works.
import 'package:flutter/foundation.dart';

/// Which kind of window is open (S11.9 recovery · S11.10 support action).
enum CancelWindowKind { recovery, support }

/// One pending, cancellable action.
@immutable
final class CancelWindow {
  const CancelWindow({
    required this.id,
    required this.kind,
    required this.openedAt,
    this.requesterName = '',
    this.newDeviceFingerprint = '',
    this.targetDeviceName = '',
    this.cancelled = false,
  });

  /// Length of every window (ADR 2026-09-05d §1, §3).
  static const duration = Duration(hours: 24);

  /// Server id of the request (recovery_requests / support action).
  final String id;
  final CancelWindowKind kind;

  /// UTC instant the window opened; it completes at [completesAt].
  final DateTime openedAt;

  /// S11.9: who asked, and the new phone's fingerprint to match (ADR 05d §1).
  final String requesterName;
  final String newDeviceFingerprint;

  /// S11.10: the device support is revoking (ADR 05d §3).
  final String targetDeviceName;

  /// True once a device on the account cancelled it.
  final bool cancelled;

  DateTime get completesAt => openedAt.add(duration);

  /// Time left; zero once complete.
  Duration remaining(DateTime now) {
    final d = completesAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  /// Exactly at 24 h the window is complete (ADR 2026-09-05i §9).
  bool isComplete(DateTime now) => !now.isBefore(completesAt);

  /// One-tap Cancel is available up to the last second (23 h 59 works).
  bool canCancel(DateTime now) => !cancelled && !isComplete(now);

  CancelWindow copyWith({bool? cancelled}) => CancelWindow(
    id: id,
    kind: kind,
    openedAt: openedAt,
    requesterName: requesterName,
    newDeviceFingerprint: newDeviceFingerprint,
    targetDeviceName: targetDeviceName,
    cancelled: cancelled ?? this.cancelled,
  );
}
