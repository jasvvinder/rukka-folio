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

/// Which door the person came in by on S0.06 (ADR 2026-10-05c §1 🔒). The
/// door sets the S0.2 heading and the OTP purpose; it never changes what is
/// shown about a number **before** its code is accepted (§2, 06 §2).
enum SignInDoor {
  /// *I'm new · set up my books* — the fresh signup (06 §5).
  newBooks,

  /// *I already use Rukka · sign in* — a further phone of an existing
  /// account (06 §5 returning device).
  signIn,
}

/// The one-shot right to turn a verified code for a number with no account
/// into a signup, without a second code (ADR 2026-10-05c §2: *Set up new
/// books* on S0.2e). Opaque; held in memory only, never in a route.
final class SignupTicket {
  const SignupTicket(this.value, {this.expiresIn});

  /// Opaque server token.
  final String value;

  /// How long the server keeps it (`expires_in_s`), when it said.
  final Duration? expiresIn;
}

/// What a correct code says about the number (ADR 2026-10-05c §2) — answered
/// only after the code, never before (06 §2: no registered-number oracle).
sealed class OtpOutcome {
  const OtpOutcome();
}

/// The number's account is this install's own — new (`created`) or the
/// install's confirmed identity. [ticket] activates this device (06 §3).
final class OtpThisPhone extends OtpOutcome {
  const OtpThisPhone(this.ticket);

  final ActivationTicket ticket;
}

/// The number already has books under an account this phone is new to (ADR
/// 2026-10-04b §3). Nothing was stored and nothing is activated; the way on
/// is S0.2a / S0.2b (ADR 2026-10-05c §2–§3).
final class OtpHasBooks extends OtpOutcome {
  const OtpHasBooks();
}

/// The number has no account and the server did not sign it up (the sign-in
/// door). [signupTicket] makes it a signup only if the person chooses *Set up
/// new books* on S0.2e (ADR 2026-10-05c §2).
final class OtpNoBooks extends OtpOutcome {
  const OtpNoBooks(this.signupTicket);

  final SignupTicket signupTicket;
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

  /// The code was right, but the number already belongs to an account and
  /// this install's provisional identity is not that account's (ADR
  /// 2026-10-04b §3 🔒 — a further device of an existing user, 06 §5). Nothing
  /// was stored in the session and no device was registered; the ledger
  /// adopted the account's id before answering ([SignupIdentity
  /// .adoptExistingAccount], C-04b-4), and its UMK arrives only by link or
  /// recovery. Not an oracle: it is answered only after a correct code (ADR
  /// 04b §3, 06 §2).
  existingAccount,

  /// `signup/adopt` refused the [SignupTicket] (expired, spent or unknown):
  /// the flow restarts from the number with a plain message (ADR 2026-10-05c
  /// §2). Nothing was stored.
  signupTicketInvalid,
}

/// The install's first-run identity as signup sees it (ADR 2026-10-04b §2 🔒).
///
/// `LocalLedger` implements it (`shared/ledger`); `features/auth` drives it
/// from `POST /otp/verify`. The ids themselves are read from the ledger's
/// identity record, exactly as the device id is (ADR 2026-09-16 §3).
abstract interface class SignupIdentity {
  /// Whether `/otp/verify` has answered with this install's own user id — or
  /// the identity predates the guard (an install is never locked out of its
  /// own books). While false, nothing is authored under the identity.
  bool get identityConfirmed;

  /// Records that `/otp/verify` answered with [userId], which must be this
  /// install's own (an `ArgumentError` otherwise). Idempotent.
  Future<void> confirmIdentity(String userId);

  /// ADR 2026-10-04b §2 last bullet: the server answered `409
  /// user_id_taken`. Discards the provisional user id — with the tenant id
  /// and the UMK minted beside it — mints fresh ones and returns the new user
  /// id. Throws [IdentityNotProvisional] when the identity is confirmed or
  /// anything has been authored under it.
  Future<String> remintProvisionalIdentity();

  /// ADR 2026-10-04b §3 (C-04b-4): `/otp/verify` named [userId], an account
  /// the phone number already has. The install becomes a further device of
  /// that account **before anything is authored**: it drops its provisional
  /// user and tenant ids (and any UMK minted with them), keeps its device id
  /// and any device seeds, and stays provisional. A later `/otp/verify`
  /// echoing [userId] does not confirm it while [awaitingAccountUmk]: the
  /// device joins by link or recovery, whose registration mints device seeds
  /// only (ADR 2026-10-09 §2). Throws [IdentityNotProvisional]
  /// when the identity is confirmed or anything has been authored under it.
  Future<void> adoptExistingAccount(String userId);

  /// True while this install is a further device of an existing account
  /// ([adoptExistingAccount], C-04b-4) that holds none of that account's
  /// UMK yet. A later `/otp/verify` echoing the adopted id is then that
  /// account's sign-in on a new phone (06 §5 *New phone, has old device*:
  /// OTP → §3 → link), answered as *has books* — never confirmed, never
  /// registered and never sent into new-books onboarding, because the UMK
  /// arrives only through link, recovery or key sync (ADR 2026-10-04b §3).
  bool get awaitingAccountUmk;
}

/// S0.2's key step (ADR 2026-10-09 §2 🔒), run by `features/auth`
/// immediately before `POST /devices`. `LocalLedger` implements it: in one
/// idempotent ledger step it creates the device's signing and agreement
/// seeds and — for a **new** account only — the UMK and its local wrap, all
/// straight into the non-biometric device-key class (ADR 2026-10-06 §1). A
/// device signing in to an existing account gets seeds only (ADR 2026-10-04b
/// §3). A retried POST reuses the seeds already held, so no key exists that
/// the UMK was never wrapped to. The auth client never mints a seed itself.
abstract interface class DeviceKeyMint {
  /// Makes sure this device's registration keys rest in the key store, minting
  /// only what is missing. Throws when the ledger is not open.
  Future<void> mintForRegistration();
}

/// A re-mint was asked of an identity that is no longer provisional: it was
/// confirmed by signup, it predates the guard, or something was authored
/// under it (ADR 2026-10-04b §2 — a re-mint is safe only while nothing is).
final class IdentityNotProvisional implements Exception {
  /// Creates the refusal.
  const IdentityNotProvisional();

  @override
  String toString() => 'IdentityNotProvisional';
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

  /// Sends a 6-digit code to [phone] (06 §2). Moves to [OtpSent]. [door] picks
  /// the purpose (ADR 2026-10-05c §1): the answer is the same for every
  /// number either way (06 §2).
  Future<void> requestOtp(
    String phone, {
    SignInDoor door = SignInDoor.newBooks,
  });

  /// Checks [code]; yields the one-shot activation ticket (06 §2). A number
  /// with books under another account throws
  /// [AuthFailureKind.existingAccount]; one with no account (the sign-in
  /// door) throws [AuthFailureKind.unavailable] — callers that route on the
  /// answer use [checkOtp].
  Future<ActivationTicket> verifyOtp(String code);

  /// Checks [code] and says what the number is (ADR 2026-10-05c §2): this
  /// install's account, books under another account, or no account.
  Future<OtpOutcome> checkOtp(String code);

  /// Turns [ticket] into this install's signup — S0.2e *Set up new books*,
  /// with no second code (ADR 2026-10-05c §2). Throws
  /// [AuthFailureKind.signupTicketInvalid] when the server no longer honours
  /// it.
  Future<ActivationTicket> adoptSignup(SignupTicket ticket);

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

  /// Codes [verifyOtp] / [checkOtp] were called with, in order.
  final verifiedCodes = <String>[];

  /// Doors [requestOtp] was called with, in order (parallel to
  /// [requestedPhones]).
  final requestedDoors = <SignInDoor>[];

  /// E.164 numbers that already have books under another account: a correct
  /// code for one answers [OtpHasBooks] on either door (ADR 2026-10-05c §2).
  /// Every other number is new — this install's own on the *I'm new* door,
  /// [OtpNoBooks] on the sign-in door. [requestOtp] answers alike for both.
  final numbersWithBooks = <String>{};

  /// Signup tickets [adoptSignup] was called with, in order.
  final adoptedTickets = <String>[];

  String? _pendingPhone;
  SignInDoor _pendingDoor = SignInDoor.newBooks;
  int _signupSeq = 0;
  final _unusedSignups = <String>{};

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
  Future<void> requestOtp(
    String phone, {
    SignInDoor door = SignInDoor.newBooks,
  }) async {
    _maybeFail();
    requestedPhones.add(phone);
    requestedDoors.add(door);
    _pendingPhone = phone;
    _pendingDoor = door;
    _attempts = 0;
    _codePending = true;
    _set(OtpSent(phone));
  }

  @override
  Future<ActivationTicket> verifyOtp(String code) async =>
      switch (await checkOtp(code)) {
        OtpThisPhone(:final ticket) => ticket,
        OtpHasBooks() => throw const AuthFailure(
          AuthFailureKind.existingAccount,
        ),
        OtpNoBooks() => throw const AuthFailure(AuthFailureKind.unavailable),
      };

  @override
  Future<OtpOutcome> checkOtp(String code) async {
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
    if (numbersWithBooks.contains(_pendingPhone)) return const OtpHasBooks();
    if (_pendingDoor == SignInDoor.signIn) {
      final signup = 'fake-signup-${++_signupSeq}';
      _unusedSignups.add(signup);
      return OtpNoBooks(
        SignupTicket(signup, expiresIn: const Duration(minutes: 10)),
      );
    }
    return OtpThisPhone(_mint());
  }

  ActivationTicket _mint() {
    final ticket = 'fake-ticket-${++_ticketSeq}';
    _unusedTickets.add(ticket);
    return ActivationTicket(ticket);
  }

  @override
  Future<ActivationTicket> adoptSignup(SignupTicket ticket) async {
    _maybeFail();
    adoptedTickets.add(ticket.value);
    if (!_unusedSignups.remove(ticket.value)) {
      throw const AuthFailure(AuthFailureKind.signupTicketInvalid);
    }
    return _mint();
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
