// The real [AuthClient] (06 §2–§4) over the auth-challenge function.
//
//   OTP request (WhatsApp first, SMS fallback surfaced as state)
//     → verify → activation ticket
//     → POST devices with the device's public keys → device_id
//     → POST challenge {device_id} → nonce
//     → sign nonce ‖ uuid16(device_id) ‖ i64be(unix_ts) with the device Ed25519 key
//     → access JWT (15 min) + rotating refresh token (30-day idle cap)
//
// Device keys are generated once through the injected [CryptoSuite] (libsodium
// CSPRNG, rule 7) and rest as 32-byte seeds in the [KeyStore] under
// [KeyIds.deviceSigningKey] / [KeyIds.deviceAgreementKey] — biometric-bound
// on the platform store (ADR 2026-09-05d §4). An existing seed is reused, so a
// reinstall on the same iPhone is the same device (06 §5 Keychain remnant).
//
// The clock is injected (rule 3). Nothing here logs a phone number, a code,
// a token or a body (rule 4): [log] receives fixed event names only.
//
// ⚠️ WIRE — the contract is the server function
// `server/supabase/functions/auth-challenge/index.ts` (route table in its
// file header; exact JSON in `_tests/auth_challenge.test.ts`). Everything
// marked ⚠️ WIRE below mirrors that file and must be changed in step with it:
//   • sub-routes under `auth-challenge/` — `otp/request`, `otp/verify`,
//     `devices`, `devices/certify`, `challenge`, `token`, `refresh`
//     ([AuthEndpoints]);
//   • `purpose` on both OTP calls (`PURPOSES` in index.ts) — [OtpPurpose];
//   • error bodies `{ "error": "otp_invalid", "attempts_left"? }`,
//     `ticket_invalid` (401), `device_cap` (409), `challenge_failed`,
//     `refresh_invalid` / `refresh_reused` (401), `too_many_requests` (429);
//   • 426 body `{ "error": "upgrade_required", "min_client_version" }` and
//     the request header `x-rukka-client-version`
//     (`_shared/http.ts` CLIENT_VERSION_HEADER);
//   • the signed message is nonce(32) ‖ uuid16(device_id) ‖ i64be(unix_ts
//     seconds), built from core_crypto's [Bytes] / [Uuid16] so both sides
//     derive identical bytes; nonce, keys, ticket and signature travel
//     base64url (the server emits unpadded base64url and accepts both
//     alphabets — `_shared/bytes.ts` b64any).
import 'dart:async';
import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/foundation.dart';
// The app declares sodium_libs (rule 7), which re-exports package:sodium.
// ignore: deprecated_member_use
import 'package:sodium_libs/sodium_libs.dart' show KeyPair;

import '../../shared/seams/auth_client.dart';
import '../../shared/seams/key_store.dart';
import 'auth_transport.dart';

/// Which channel carries the code (06 §2: WhatsApp first, SMS fallback).
enum OtpChannel {
  whatsapp('whatsapp'),
  sms('sms');

  const OtpChannel(this.wire);

  /// `channel` value on `otp/request` (⚠️ WIRE index.ts otpRequest).
  final String wire;
}

/// Why a code is being sent (06 §2: OTP fires only at signup, device
/// activation, phone-number change, account deletion). Wire values are the
/// server's `PURPOSES` set (⚠️ WIRE index.ts).
enum OtpPurpose {
  /// A new number / the first device (06 §5 "Fresh signup").
  signup('signup'),

  /// Adding a device to an existing account (06 §5 "Link").
  deviceActivation('device_activation'),

  phoneChange('phone_change'),
  accountDeletion('account_deletion');

  const OtpPurpose(this.wire);

  final String wire;
}

/// The API answered 426: this build is below the minimum client version for
/// the route group (06 §4.5). S19.1 shows it; there is no dismiss.
final class UpdateRequired implements Exception {
  const UpdateRequired({
    required this.currentVersion,
    required this.requiredVersion,
  });

  final String currentVersion;

  /// Empty when the server did not say (⚠️ WIRE `min_client_version`).
  final String requiredVersion;

  @override
  String toString() => 'UpdateRequired($currentVersion → $requiredVersion)';
}

/// The server rejected the refresh (rotated token reused → family revoked,
/// 06 §4.2) or the device is unknown. The client is now [SignedOut]; nothing
/// local was wiped (ADR 2026-09-05b §2 — a wipe needs a signed record).
final class SessionEnded implements Exception {
  const SessionEnded();

  @override
  String toString() => 'SessionEnded';
}

/// `POST devices` answered 409 `device_cap` (06 §3: device cap per plan; the
/// server test E-06-3 pins 5 on Free). The ticket was consumed; the user
/// must remove a device before activating this one. Kept out of
/// [AuthFailureKind] because the seam (shared/seams) does not spell it.
final class DeviceCapReached implements Exception {
  const DeviceCapReached();

  @override
  String toString() => 'DeviceCapReached';
}

/// Exposes the min-version gate to screens (S0.2, S19.1) without widening
/// the sealed [AuthState].
abstract class MinVersionGate {
  ValueListenable<UpdateRequired?> get updateRequired;
}

/// Exposes the OTP channel to S0.2 without widening [AuthState].
abstract class OtpChannelSource {
  ValueListenable<OtpChannel?> get otpChannel;
}

/// Route table under the edge-functions root: every route is a sub-path of
/// the `auth-challenge` function (⚠️ WIRE index.ts `handler` switch).
final class AuthEndpoints {
  AuthEndpoints(Uri functionsRoot)
    : base = functionsRoot.path.endsWith('/')
          ? functionsRoot
          : functionsRoot.replace(path: '${functionsRoot.path}/');

  /// The edge-functions root (`…/functions/v1/`), always slash-terminated so
  /// `resolve` appends rather than replaces the last segment.
  final Uri base;

  static const String function = 'auth-challenge';

  Uri _sub(String path) => base.resolve('$function/$path');

  Uri get otpRequest => _sub('otp/request');
  Uri get otpVerify => _sub('otp/verify');
  Uri get devices => _sub('devices'); // 06 §3 step 2
  Uri get devicesCertify => _sub('devices/certify'); // 06 §3 step 3
  Uri get challenge => _sub('challenge'); // 06 §4 step 1
  Uri get token => _sub('token'); // 06 §4 step 2
  Uri get refresh => _sub('refresh'); // 06 §4 step 2
}

/// Non-secret-but-private items this client keeps in the [KeyStore] beside
/// the device seeds (there is no preferences seam, and the refresh token is a
/// secret in any case).
abstract final class SessionItems {
  /// Server-issued `device_id` (06 §3 step 2), UTF-8.
  static const deviceId = 'rk.device.id';

  /// `user_id` from the session response, UTF-8.
  static const userId = 'rk.session.user';

  /// The current refresh token (rotates on every refresh).
  static const refreshToken = 'rk.session.refresh';
}

/// 06 §4 step 2: access JWT lifetime.
const Duration accessTokenLifetime = Duration(minutes: 15);

/// Refresh this early so a request in flight never carries an expired token.
const Duration accessRefreshMargin = Duration(seconds: 60);

/// Request header carrying the build version (⚠️ WIRE `_shared/http.ts`
/// CLIENT_VERSION_HEADER).
const String clientVersionHeader = 'x-rukka-client-version';

/// The production identity client. See the file comment.
final class HttpAuthClient
    implements AuthClient, MinVersionGate, OtpChannelSource {
  HttpAuthClient({
    required this._transport,
    required this._suite,
    required this._keys,
    required this._now,
    required Uri baseUrl,
    required this._clientVersion,
    this.deviceModel = '',
    this.deviceOs = '',
    this.defaultPurpose = OtpPurpose.signup,
    this.language,
    void Function(String event)? log,
  }) : endpoints = AuthEndpoints(baseUrl),
       _log = log ?? _noLog;

  final AuthTransport _transport;
  final CryptoSuite _suite;
  final KeyStore _keys;
  final DateTime Function() _now;
  final String _clientVersion;
  final void Function(String) _log;

  /// Resolved routes.
  final AuthEndpoints endpoints;

  /// `model` / `os` metadata for `POST devices` (06 §3 step 2); omitted from
  /// the body when empty.
  final String deviceModel;
  final String deviceOs;

  /// The `purpose` [requestOtp] sends when its caller does not say. The seam
  /// method has no purpose parameter, so a device-linking flow constructs (or
  /// calls) with [OtpPurpose.deviceActivation] explicitly.
  final OtpPurpose defaultPurpose;

  /// `language` on `otp/request` (`en` | `pa` | `hi`; the server ignores
  /// others). Null = not sent.
  final String? language;

  static void _noLog(String _) {}

  final _states = ValueNotifier<AuthState>(const SignedOut());
  final _gate = ValueNotifier<UpdateRequired?>(null);
  final _channel = ValueNotifier<OtpChannel?>(null);
  final _resendAfter = ValueNotifier<Duration?>(null);

  String? _pendingPhone;
  OtpPurpose? _pendingPurpose;
  String? _accessToken;
  DateTime? _accessExpiresAt;

  @override
  ValueListenable<UpdateRequired?> get updateRequired => _gate;

  @override
  ValueListenable<OtpChannel?> get otpChannel => _channel;

  /// `resend_after_s` from the last `otp/request` (200 or 429): how long the
  /// resend button stays disabled (06 §2 backoff 30 s → 60 s → 5 min).
  ValueListenable<Duration?> get resendAfter => _resendAfter;

  @override
  AuthState get current => _states.value;

  @override
  Stream<AuthState> get state => _listen(_states);

  static Stream<T> _listen<T>(ValueNotifier<T> n) async* {
    yield n.value;
    final ctrl = StreamController<T>();
    void push() => ctrl.add(n.value);
    n.addListener(push);
    ctrl.onCancel = () => n.removeListener(push);
    yield* ctrl.stream;
  }

  /// The current access token, refreshing it first when it is within
  /// [accessRefreshMargin] of expiry (06 §4 step 2: every refresh carries a
  /// fresh signature). Throws [SessionEnded] when the server refuses.
  Future<String> accessToken() async {
    final s = current;
    if (s is! Active) throw const SessionEnded();
    final exp = _accessExpiresAt;
    final tok = _accessToken;
    if (tok != null &&
        exp != null &&
        _now().isBefore(exp.subtract(accessRefreshMargin))) {
      return tok;
    }
    return _refresh(s.session.deviceId);
  }

  /// Restores an [Active] session from the store on cold start (device id +
  /// user id present). The first [accessToken] call refreshes.
  Future<void> restore() async {
    final dev = await _readText(SessionItems.deviceId);
    final user = await _readText(SessionItems.userId);
    if (dev == null || user == null) return;
    if (!await _keys.contains(SessionItems.refreshToken)) return;
    _states.value = Active(
      AuthSession(userId: user, deviceId: dev),
      deviceCertified: false,
    );
  }

  /// The ceremony / recovery lane calls this once the server has verified
  /// this device's certificate (ADR 2026-09-05d §2) — until then the device
  /// sees nothing but itself.
  void markCertified() {
    final s = current;
    if (s is Active && !s.deviceCertified) {
      _states.value = Active(s.session, deviceCertified: true);
    }
  }

  /// `POST devices/certify` (Bearer) — uploads this device's certificate
  /// under the user's UMK (04 §3.4; 06 §3 step 3). Body per ⚠️ WIRE
  /// index.ts `certify`: `{cert: {signature, issued_at_ms,
  /// issued_by_device?}, umk_key_version?, umk_pub_ed?}` → 200
  /// `{device_id, status: "certified"}` | 400 `cert_malformed` /
  /// `cert_invalid` / `umk_unknown`. Stub: the ceremony lane lands it with
  /// core_crypto/device_cert.dart and calls [markCertified] on 200.
  Future<void> certifyDevice() {
    throw UnimplementedError(
      'devices/certify lands with the ceremony lane (${endpoints.devicesCertify.path})',
    );
  }

  // --- 06 §2 OTP ----------------------------------------------------------

  /// Sends a code to [phone]. [purpose] defaults to [defaultPurpose];
  /// [channel] is the preference the server tries first (it falls back to
  /// SMS on its own and does not report which carried the code — ⚠️ WIRE
  /// the 200 body is `{ok, resend_after_s}`; a `channel` field, if the
  /// server ever adds one, is honoured).
  @override
  Future<void> requestOtp(
    String phone, {
    OtpPurpose? purpose,
    OtpChannel channel = OtpChannel.whatsapp,
  }) async {
    final p = purpose ?? defaultPurpose;
    // A 429 here carries `resend_after_s` too; _post records it before it
    // throws rateLimited.
    final r = await _post(endpoints.otpRequest, {
      'phone': phone,
      'purpose': p.wire,
      'channel': channel.wire,
      if (language != null) 'language': language,
    });
    _expectOk(r, 'otp_request');
    final body = _json(r);
    _noteResend(body);
    _channel.value = switch (body['channel']) {
      'sms' => OtpChannel.sms,
      'whatsapp' => OtpChannel.whatsapp,
      _ => channel,
    };
    _pendingPhone = phone;
    _pendingPurpose = p;
    _states.value = OtpSent(phone);
    _log('otp_requested');
  }

  void _noteResend(Map<String, Object?> body) {
    final s = body['resend_after_s'];
    _resendAfter.value = s is num ? Duration(seconds: s.ceil()) : null;
  }

  @override
  Future<ActivationTicket> verifyOtp(String code) async {
    final phone = _pendingPhone;
    final purpose = _pendingPurpose;
    if (phone == null || purpose == null) {
      throw const AuthFailure(AuthFailureKind.noPendingCode);
    }
    final r = await _post(endpoints.otpVerify, {
      'phone': phone,
      'purpose': purpose.wire,
      'code': code,
    });
    if (r.statusCode == 200) {
      final body = _json(r);
      final ticket = body['ticket'];
      if (ticket is! String || ticket.isEmpty) {
        throw const AuthFailure(AuthFailureKind.unavailable);
      }
      final userId = body['user_id'];
      if (userId is String && userId.isNotEmpty) {
        await _writeText(SessionItems.userId, userId);
      }
      _pendingPhone = null;
      _pendingPurpose = null;
      _log('otp_verified');
      return ActivationTicket(ticket);
    }
    final body = _json(r);
    switch (body['error']) {
      case 'otp_invalid':
        final left = body['attempts_left'];
        if (left is int && left > 0) {
          throw AuthFailure(AuthFailureKind.invalidCode, attemptsLeft: left);
        }
        // No `attempts_left`: no live challenge — expired, consumed or the
        // third wrong code already spent it (index.ts otpVerify). A new code
        // is needed either way.
        _pendingPhone = null;
        _pendingPurpose = null;
        throw const AuthFailure(AuthFailureKind.codeExpired);
      case 'bad_request':
        // Not six digits: the server never looked at the challenge.
        throw const AuthFailure(AuthFailureKind.invalidCode);
    }
    _throwGeneric(r, 'otp_verify');
  }

  // --- 06 §3 device registration -------------------------------------------

  @override
  Future<AuthSession> activateDevice(ActivationTicket ticket) async {
    final pair = await _deviceKeys();
    try {
      final r = await _post(endpoints.devices, {
        'ticket': ticket.value,
        'pub_ed': Bytes.base64Url(pair.ed.publicKey),
        'pub_x': Bytes.base64Url(pair.x.publicKey),
        if (deviceModel.isNotEmpty) 'model': deviceModel,
        if (deviceOs.isNotEmpty) 'os': deviceOs,
        // 06 §3 step 2: design the field now, enforce in v2 (server accepts
        // an object or nothing).
        'attestation': null,
      });
      if (r.statusCode != 200 && r.statusCode != 201) {
        final err = _json(r)['error'];
        if (err == 'ticket_invalid' || r.statusCode == 401) {
          throw const AuthFailure(AuthFailureKind.invalidTicket);
        }
        if (err == 'device_cap' || r.statusCode == 409) {
          _log('device_cap');
          throw const DeviceCapReached();
        }
        _throwGeneric(r, 'device_register');
      }
      final body = _json(r);
      final deviceId = body['device_id'];
      if (deviceId is! String || deviceId.isEmpty) {
        throw const AuthFailure(AuthFailureKind.unavailable);
      }
      await _writeText(SessionItems.deviceId, deviceId);
      final regUser = body['user_id'];
      if (regUser is String && regUser.isNotEmpty) {
        await _writeText(SessionItems.userId, regUser);
      }
      _log('device_registered');
      final opened = await _openSession(deviceId, pair.ed);
      final session = AuthSession(userId: opened.userId, deviceId: deviceId);
      // Registered but uncertified: sees nothing but itself (ADR 05d §2).
      // Only the server's word (`status` / `device_status: "certified"`)
      // says otherwise.
      _states.value = Active(
        session,
        deviceCertified: body['status'] == 'certified' || opened.certified,
      );
      return session;
    } finally {
      pair.dispose();
    }
  }

  @override
  Future<void> signOut() async {
    _accessToken = null;
    _accessExpiresAt = null;
    _pendingPhone = null;
    _pendingPurpose = null;
    await _keys.delete(SessionItems.refreshToken);
    await _keys.delete(SessionItems.userId);
    // Device keys and device_id stay: a sign-out is not a revocation
    // (04 §9.2 needs a signed record; ADR 2026-09-05b §2).
    _states.value = const SignedOut();
    _log('signed_out');
  }

  // --- 06 §4 sessions -------------------------------------------------------

  Future<_Opened> _openSession(String deviceId, KeyPair ed) async {
    final signed = await _signChallenge(deviceId, ed);
    final r = await _post(endpoints.token, signed);
    if (r.statusCode == 401 || r.statusCode == 403) {
      // `challenge_failed`: skewed clock, expired nonce, or the device was
      // revoked between the two calls. The device row exists; the ticket is
      // spent — the caller must request a new code (⚠️ no resume path yet).
      _log('session_open_refused');
      throw const AuthFailure(AuthFailureKind.unavailable);
    }
    _expectOk(r, 'session_open');
    return _storeSession(_json(r));
  }

  Future<String> _refresh(String deviceId) async {
    final pair = await _deviceKeys();
    try {
      final refresh = await _readText(SessionItems.refreshToken);
      if (refresh == null) {
        await signOut();
        throw const SessionEnded();
      }
      final signed = await _signChallenge(deviceId, pair.ed);
      final r = await _post(endpoints.refresh, {
        ...signed,
        'refresh_token': refresh,
      });
      if (r.statusCode == 401 || r.statusCode == 403) {
        // `refresh_reused` (family revoked), `refresh_invalid`, or
        // `challenge_failed`: the server ended it.
        await signOut();
        _log('session_ended');
        throw const SessionEnded();
      }
      _expectOk(r, 'session_refresh');
      final opened = await _storeSession(_json(r));
      if (opened.certified) markCertified();
      return _accessToken!;
    } finally {
      pair.dispose();
    }
  }

  /// `POST challenge {device_id}` → nonce; returns the signed fields
  /// `device_id`, `nonce`, `unix_ts`, `signature` (06 §4 steps 1–2).
  Future<Map<String, Object?>> _signChallenge(
    String deviceId,
    KeyPair ed,
  ) async {
    final r = await _post(endpoints.challenge, {'device_id': deviceId});
    _expectOk(r, 'challenge');
    final nonceB64 = _json(r)['nonce'];
    if (nonceB64 is! String) {
      throw const AuthFailure(AuthFailureKind.unavailable);
    }
    final Uint8List nonce;
    try {
      nonce = decodeBase64Any(nonceB64);
    } on FormatException {
      throw const AuthFailure(AuthFailureKind.unavailable);
    }
    final unixTs = _now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final message = challengeMessage(nonce, deviceId, unixTs);
    final sig = _suite.sodium.crypto.sign.detached(
      message: message,
      secretKey: ed.secretKey,
    );
    return {
      'device_id': deviceId,
      'nonce': nonceB64,
      'unix_ts': unixTs,
      'signature': Bytes.base64Url(sig),
    };
  }

  /// nonce(32) ‖ uuid16(device_id) ‖ i64be(unix_ts seconds) — 06 §4 step 2
  /// fixes the order; the encoding is ⚠️ WIRE with index.ts
  /// `verifyChallenge` (`concat([nonce, uuid16(device_id), i64be(ts)])`).
  static Uint8List challengeMessage(
    Uint8List nonce,
    String deviceId,
    int unixTs,
  ) => Bytes.concat([nonce, Uuid16.toBytes(deviceId), Bytes.i64be(unixTs)]);

  /// Decodes standard or URL-safe base64, padded or not (the server's
  /// `b64any`).
  static Uint8List decodeBase64Any(String s) =>
      Bytes.fromBase64Url(s.replaceAll('+', '-').replaceAll('/', '_'));

  Future<_Opened> _storeSession(Map<String, Object?> body) async {
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    if (access is! String || refresh is! String) {
      throw const AuthFailure(AuthFailureKind.unavailable);
    }
    final expiresIn = body['expires_in'];
    final life = expiresIn is int
        ? Duration(seconds: expiresIn)
        : accessTokenLifetime;
    _accessToken = access;
    _accessExpiresAt = _now().add(life);
    await _writeText(SessionItems.refreshToken, refresh);
    final userId = body['user_id'];
    final known = await _readText(SessionItems.userId);
    final resolved = userId is String && userId.isNotEmpty
        ? userId
        : (known ?? _jwtUserId(access) ?? '');
    if (resolved.isEmpty) throw const AuthFailure(AuthFailureKind.unavailable);
    if (known != resolved) await _writeText(SessionItems.userId, resolved);
    _log('session_open');
    return _Opened(resolved, certified: body['device_status'] == 'certified');
  }

  /// `user_id` claim of an unverified JWT payload — a fallback only; the
  /// server's `user_id` field wins when present.
  static String? _jwtUserId(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final v = (jsonDecode(payload) as Map<String, Object?>)['user_id'];
      return v is String ? v : null;
    } on FormatException {
      return null;
    }
  }

  // --- device keys (04 §3.3) ------------------------------------------------

  Future<_DeviceKeys> _deviceKeys() async {
    final s = _suite.sodium;
    var edSeed = await _keys.read(KeyIds.deviceSigningKey);
    var xSeed = await _keys.read(KeyIds.deviceAgreementKey);
    if (edSeed == null || xSeed == null) {
      if (edSeed != null) zeroise(edSeed);
      if (xSeed != null) zeroise(xSeed);
      edSeed = _suite.randomBytes(s.crypto.sign.seedBytes);
      xSeed = _suite.randomBytes(s.crypto.box.seedBytes);
      await _keys.write(KeyIds.deviceSigningKey, edSeed);
      await _keys.write(KeyIds.deviceAgreementKey, xSeed);
      _log('device_keys_generated');
    }
    final edSecure = s.secureCopy(edSeed);
    final xSecure = s.secureCopy(xSeed);
    zeroise(edSeed);
    zeroise(xSeed);
    try {
      return _DeviceKeys(
        s.crypto.sign.seedKeyPair(edSecure),
        s.crypto.box.seedKeyPair(xSecure),
      );
    } finally {
      edSecure.dispose();
      xSecure.dispose();
    }
  }

  // --- transport ------------------------------------------------------------

  Future<AuthHttpResponse> _post(Uri url, Map<String, Object?> body) async {
    final AuthHttpResponse r;
    try {
      r = await _transport.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          clientVersionHeader: _clientVersion,
        },
        body: jsonEncode(body),
      );
    } on Exception {
      _log('transport_failed');
      throw const AuthFailure(AuthFailureKind.unavailable);
    }
    if (r.statusCode == 426) {
      final min = _json(r)['min_client_version'];
      final gate = UpdateRequired(
        currentVersion: _clientVersion,
        requiredVersion: min is String ? min : '',
      );
      _gate.value = gate;
      _log('update_required');
      throw gate;
    }
    if (r.statusCode == 429) {
      final b = _json(r);
      if (b.containsKey('resend_after_s')) _noteResend(b);
      throw const AuthFailure(AuthFailureKind.rateLimited);
    }
    return r;
  }

  void _expectOk(AuthHttpResponse r, String event) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    _throwGeneric(r, event);
  }

  Never _throwGeneric(AuthHttpResponse r, String event) {
    _log('${event}_failed_${r.statusCode}');
    throw const AuthFailure(AuthFailureKind.unavailable);
  }

  static Map<String, Object?> _json(AuthHttpResponse r) {
    if (r.body.isEmpty) return const {};
    try {
      final v = jsonDecode(r.body);
      return v is Map<String, Object?> ? v : const {};
    } on FormatException {
      return const {};
    }
  }

  Future<String?> _readText(String id) async {
    final b = await _keys.read(id);
    if (b == null) return null;
    try {
      return utf8.decode(b);
    } finally {
      zeroise(b);
    }
  }

  Future<void> _writeText(String id, String value) async {
    final b = Uint8List.fromList(utf8.encode(value));
    try {
      await _keys.write(id, b);
    } finally {
      zeroise(b);
    }
  }

  /// Releases listeners. The device keys stay in the store.
  void dispose() {
    _states.dispose();
    _gate.dispose();
    _channel.dispose();
    _resendAfter.dispose();
  }
}

final class _Opened {
  const _Opened(this.userId, {required this.certified});

  final String userId;
  final bool certified;
}

final class _DeviceKeys {
  _DeviceKeys(this.ed, this.x);

  final KeyPair ed;
  final KeyPair x;

  void dispose() {
    ed.dispose();
    x.dispose();
  }
}
