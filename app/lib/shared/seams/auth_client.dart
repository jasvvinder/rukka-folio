// The app's seam to identity (06 §2–§4): OTP → activation ticket → device
// registration → session. UI lanes depend on this interface and the fake; the
// real client (auth-challenge function, hardware keys) plugs in at integration.
// No network here.
import 'dart:async';

/// A short-lived activation ticket (06 §2), consumable exactly once by
/// device registration (06 §3).
final class ActivationTicket {
  const ActivationTicket(this.value);

  /// Opaque server token.
  final String value;
}

/// An authenticated session (06 §4). Tokens themselves never leave the client.
final class AuthSession {
  const AuthSession({required this.userId, required this.deviceId});

  final String userId;
  final String deviceId;
}

/// Where identity stands.
sealed class AuthState {
  const AuthState();
}

/// No session on this phone.
final class SignedOut extends AuthState {
  const SignedOut();
}

/// A code was sent to [phone]; waiting for it (06 §2).
final class OtpSent extends AuthState {
  const OtpSent(this.phone);

  /// E.164 number the code went to.
  final String phone;
}

/// Signed in. [deviceCertified] is false until the device holds a certificate
/// under the user's UMK — then it sees nothing but itself (06 §3 step 3).
final class Active extends AuthState {
  const Active(this.session, {required this.deviceCertified});

  final AuthSession session;
  final bool deviceCertified;
}

/// Why an auth call failed. 06 §2: generic messages — no oracle on whether a
/// number is registered.
enum AuthFailureKind {
  /// Wrong code; [AuthFailure.attemptsLeft] says how many remain.
  invalidCode,

  /// Three wrong codes or 5 minutes elapsed — request a new code.
  codeExpired,

  /// Per-number or per-IP limit hit (5/hour, 10/day).
  rateLimited,

  /// Ticket already consumed or unknown.
  invalidTicket,

  /// No code was requested.
  noPendingCode,

  /// Transport failed; nothing changed.
  unavailable,
}

/// Thrown by [AuthClient] calls.
final class AuthFailure implements Exception {
  const AuthFailure(this.kind, {this.attemptsLeft});

  final AuthFailureKind kind;

  /// For [AuthFailureKind.invalidCode].
  final int? attemptsLeft;

  @override
  String toString() =>
      'AuthFailure($kind${attemptsLeft == null ? '' : ', attemptsLeft: $attemptsLeft'})';
}

/// What the app needs from identity.
abstract class AuthClient {
  /// Current state, then every change. Emits the current value on listen.
  Stream<AuthState> get state;

  /// The latest state without subscribing.
  AuthState get current;

  /// Sends a 6-digit code to [phone] (06 §2). Moves to [OtpSent].
  Future<void> requestOtp(String phone);

  /// Checks [code]; yields the one-shot activation ticket (06 §2).
  Future<ActivationTicket> verifyOtp(String code);

  /// Registers this device with [ticket] and opens a session (06 §3–§4).
  /// Moves to [Active]; certification comes later via the ceremony (04 §3.4).
  Future<AuthSession> activateDevice(ActivationTicket ticket);

  /// Ends the session locally. Moves to [SignedOut].
  Future<void> signOut();
}

/// In-memory fake. Accepts any 6-digit code unless [expectedCode] is set;
/// enforces the 3-attempt rule; failures and certification are configurable.
class FakeAuthClient implements AuthClient {
  FakeAuthClient({
    AuthState initial = const SignedOut(),
    this.deviceCertified = false,
    this.expectedCode,
    this.maxAttempts = 3,
  }) : _current = initial;

  final _controller = StreamController<AuthState>.broadcast();
  AuthState _current;
  int _attempts = 0;
  bool _codePending = false;
  int _ticketSeq = 0;
  final _unusedTickets = <String>{};

  /// Whether [activateDevice] reports a certified device.
  bool deviceCertified;

  /// If set, only this code verifies; otherwise any 6 digits do.
  String? expectedCode;

  /// Wrong codes allowed before a new code is required (06 §2: 3).
  final int maxAttempts;

  /// Next call to any method throws this once, then clears.
  AuthFailure? failNext;

  /// Phones [requestOtp] was called with, in order.
  final requestedPhones = <String>[];

  /// Codes [verifyOtp] was called with, in order.
  final verifiedCodes = <String>[];

  static final _sixDigits = RegExp(r'^[0-9]{6}$');

  @override
  AuthState get current => _current;

  void _set(AuthState s) {
    _current = s;
    _controller.add(s);
  }

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Stream<AuthState> get state async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> requestOtp(String phone) async {
    _maybeFail();
    requestedPhones.add(phone);
    _attempts = 0;
    _codePending = true;
    _set(OtpSent(phone));
  }

  @override
  Future<ActivationTicket> verifyOtp(String code) async {
    _maybeFail();
    verifiedCodes.add(code);
    if (!_codePending) throw const AuthFailure(AuthFailureKind.noPendingCode);
    final expected = expectedCode;
    final ok = expected == null ? _sixDigits.hasMatch(code) : code == expected;
    if (!ok) {
      _attempts++;
      if (_attempts >= maxAttempts) {
        _codePending = false;
        throw const AuthFailure(AuthFailureKind.codeExpired);
      }
      throw AuthFailure(
        AuthFailureKind.invalidCode,
        attemptsLeft: maxAttempts - _attempts,
      );
    }
    _codePending = false;
    final ticket = 'fake-ticket-${++_ticketSeq}';
    _unusedTickets.add(ticket);
    return ActivationTicket(ticket);
  }

  @override
  Future<AuthSession> activateDevice(ActivationTicket ticket) async {
    _maybeFail();
    if (!_unusedTickets.remove(ticket.value)) {
      throw const AuthFailure(AuthFailureKind.invalidTicket);
    }
    const session = AuthSession(userId: 'fake-user', deviceId: 'fake-device');
    _set(Active(session, deviceCertified: deviceCertified));
    return session;
  }

  @override
  Future<void> signOut() async {
    _maybeFail();
    _codePending = false;
    _set(const SignedOut());
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}
