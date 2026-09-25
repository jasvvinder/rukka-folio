// The real [AuthClient] (06 §2–§4) over the auth-challenge function.
//
//   OTP request (WhatsApp first, SMS fallback surfaced as state)
//     → verify → activation ticket
//     → POST devices with the LEDGER's device_id + the device's public keys
//       → the server records that id or refuses (ADR 2026-09-16 §2); it is
//       never issued by the server and never adopted from it
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
//   • `devices` carries `device_id` (the ledger's) and answers 409
//     `device_id_taken` when another key pair holds it — ADR 2026-09-16 §6
//     names the server change; until it lands the server ignores the field
//     and mints its own, which this client refuses (§3);
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

import '../../shared/ledger/device_certification.dart';
import '../../shared/ledger/ledger_identity.dart';
import '../../shared/records/device_added_record.dart';
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

/// Why `devices/certify` did not certify this device (06 §3 step 3). Typed
/// rather than a string so a screen can branch: [umkUnknown] and
/// [certInvalid] are *this* install's UMK against the one the server holds —
/// a recovery question — while [unavailable] is a retry.
enum CertRefusal {
  /// No ledger is bound, or it is not open: nothing can be signed.
  noKeyMaterial,

  /// The certificate names a device the session does not (ADR 2026-09-16 §1).
  deviceIdMismatch,

  /// 400 `cert_malformed` or `umk_pub_malformed` — the server could not
  /// read the certificate, or the UMK public half offered beside it.
  certMalformed,

  /// 400 `cert_invalid` — it does not verify under the UMK the server holds
  /// for this user — or 400 `umk_pub_conflict`, the server holding a
  /// different X25519 half for it. Either way a different UMK is on this
  /// device than the one this account is registered with (04 §7 recovery,
  /// not a retry).
  certInvalid,

  /// 400 `umk_unknown` — the server holds no UMK public key for this version
  /// and the request offered none.
  umkUnknown,

  /// 401, 5xx, transport: nothing is known about the certificate's fate.
  unavailable,
}

/// `POST devices/certify` refused. The device stays **registered but
/// uncertified** (06 §3 step 3): it sees nothing but itself, nothing was
/// filed locally, and [HttpAuthClient.certifyDevice] can be called again.
final class CertificationRefused implements Exception {
  /// Creates the refusal.
  const CertificationRefused(this.reason);

  /// Which link failed.
  final CertRefusal reason;

  @override
  String toString() => 'CertificationRefused(${reason.name})';
}

/// `activateDevice` was called on an install whose ledger has never run:
/// there is no device id to register (ADR 2026-09-16 §3). The ledger is
/// bootstrapped before any screen (`bootstrap.dart`), so this is an ordering
/// bug surfaced — never a state to mint a second id around.
final class NoDeviceIdentity implements Exception {
  const NoDeviceIdentity();

  @override
  String toString() =>
      'NoDeviceIdentity: LocalLedger.bootstrapSolo() must run before activateDevice()';
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
  /// The registered `device_id`, UTF-8 — always the ledger's
  /// (`rk.ledger.identity`), written at activation so `restore()` and the
  /// signed-record author read the one id (ADR 2026-09-16 §1, §4).
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
    Future<String?> Function()? deviceIdSource,
    this.certifier,
  }) : endpoints = AuthEndpoints(baseUrl),
       _log = log ?? _noLog,
       _deviceIdSource =
           deviceIdSource ??
           (() async => (await readStoredIdentity(_keys))?.deviceId);

  final AuthTransport _transport;
  final CryptoSuite _suite;
  final KeyStore _keys;

  /// The ledger, which issues this device's certificate under the user's UMK
  /// and files the one the server accepts (04 §3.4; `shared/ledger`). The UMK
  /// secret never crosses this seam — [DeviceCertifier] hands over a
  /// signature and a public key.
  ///
  /// Settable because the composition root builds this client *before* the
  /// ledger (a session is restored before any screen) and binds it straight
  /// after — `bootstrap.dart`. Null ⇒ [certifyDevice] refuses with
  /// [CertRefusal.noKeyMaterial] and activation never reaches for it.
  DeviceCertifier? certifier;

  /// Files the `device_added` signed record once this device has been
  /// certified (06 §5 🔒 final paragraph; ADR 2026-09-05d §6 — *the record is
  /// the certificate itself*). `shared/records` owns the payload and the
  /// route; this client owns only the moment.
  ///
  /// Settable for the same reason [certifier] is: the composition root builds
  /// the record author and the members client after this one
  /// (`bootstrap.dart`). Null ⇒ nothing is announced and certification is
  /// unaffected — which is also what happens when the post fails, so the two
  /// cases behave alike rather than one of them being special.
  DeviceAddedAnnouncer? announcer;

  /// Where this device's id comes from: the ledger identity in the same key
  /// store by default (ADR 2026-09-16 §1). Injected only so a test can pin
  /// one; production never passes it.
  final Future<String?> Function() _deviceIdSource;
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

  /// The refresh in flight, shared by every caller that needs a token while
  /// it runs (see [accessToken]).
  Future<String>? _refreshing;

  /// The current access token, refreshing it first when it is within
  /// [accessRefreshMargin] of expiry (06 §4 step 2: every refresh carries a
  /// fresh signature). Throws [SessionEnded] when the server refuses.
  ///
  /// **One refresh at a time.** The refresh token rotates, and 06 §4 step 2
  /// 🔒 has the server treat a rotated token's reuse as theft: it revokes the
  /// whole family and this client signs out. So two callers that both find
  /// the token stale — at cold start the launch re-offer
  /// ([reofferUmkPublic]) and a sync cycle, say — must not each post their
  /// own `/refresh` with the same stored token. The second joins the first's
  /// refresh and gets the same answer, token or [SessionEnded].
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
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;
    final started = _refresh(s.session.deviceId);
    _refreshing = started;
    try {
      return await started;
    } finally {
      if (identical(_refreshing, started)) _refreshing = null;
    }
  }

  /// Restores an [Active] session from the store on cold start (device id +
  /// user id present). The first [accessToken] call refreshes.
  Future<void> restore() async {
    final dev = await _readText(SessionItems.deviceId);
    final user = await _readText(SessionItems.userId);
    if (dev == null || user == null) return;
    if (!await _keys.contains(SessionItems.refreshToken)) return;
    // ADR 2026-09-16 §4: a session stored under any id but the ledger's is
    // not restored (a pre-ratification install that took a server-issued
    // id). Nothing is deleted — a wipe needs a signed record (ADR 05b §2);
    // the next activation registers the one true id.
    final mine = await _deviceIdSource();
    if (mine != null && mine != dev) {
      _log('device_id_stale');
      return;
    }
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
  /// issued_by_device?}, umk_key_version?, umk_pub_ed?, umk_pub_x?}` → 200
  /// `{device_id, status: "certified"}` | 400 `cert_malformed` /
  /// `cert_invalid` / `umk_unknown` / `umk_pub_malformed` /
  /// `umk_pub_conflict`.
  ///
  /// **When this runs.** Once, at the end of [activateDevice], on every path
  /// that registers a device, and when a screen retries after a refusal
  /// (S0.9 *Devices & security*). A certified device does not *certify*
  /// again on launch — it already holds its certificate and nothing here
  /// signs a second one — but it does *re-offer* the filed one once per
  /// launch, for the UMK's X25519 half: see [reofferUmkPublic]
  /// (ADR 2026-09-24b §2).
  ///
  /// ⚠️ SPEC: 04 §3.4 has the first device self-certify *at signup*, and
  /// index.ts will do it inline inside `POST /devices` when that call carries
  /// a `umk` object. This client does not send one — it registers, opens a
  /// session, then certifies over the authenticated route, so first device
  /// and later devices take one code path. Same certificate, same bytes, one
  /// extra round trip.
  ///
  /// The certified id is the ledger's, because the certificate is issued over
  /// the ledger's own device public (ADR 2026-09-16 §1) — and it is checked
  /// against the session's id before anything is sent. Every refusal is
  /// closed: nothing is filed, [markCertified] is not called, and the device
  /// stays *registered but uncertified*.
  Future<void> certifyDevice() async {
    final s = current;
    if (s is! Active) throw const SessionEnded();
    final ledger = certifier;
    if (ledger == null) {
      throw const CertificationRefused(CertRefusal.noKeyMaterial);
    }
    final DeviceCertOffer offer;
    try {
      offer = ledger.issueOwnCert();
    } on Object {
      _log('device_cert_unissuable');
      throw const CertificationRefused(CertRefusal.noKeyMaterial);
    }
    // 06 §5 🔒 says *newly* certified. Read before anything is filed: a
    // device that already holds a certificate has already announced itself,
    // and re-certifying it (an S0.9 retry after a success) must not file a
    // second `device_added` record.
    final wasCertified = ledger.ownDeviceCert != null;
    final cert = offer.cert;
    if (cert.deviceId != s.session.deviceId) {
      // One device, one id: a certificate over any other id would certify a
      // device this session is not (ADR 2026-09-16 §1). The id never reaches
      // the log (rule 4).
      _log('device_cert_id_mismatch');
      throw const CertificationRefused(CertRefusal.deviceIdMismatch);
    }
    final token = await accessToken();
    final r = await _post(endpoints.devicesCertify, {
      'cert': {
        'signature': Bytes.base64Url(cert.signature),
        'issued_at_ms': cert.issuedAtMs,
        // Self-issued (04 §3.4 first bullet). A linked device's certificate
        // will name the device that issued it (§9.1, M8).
        'issued_by_device': cert.deviceId,
      },
      'umk_key_version': offer.umkKeyVersion,
      // The first device's UMK is new to the server; a later one's is already
      // on file and this field is ignored (⚠️ WIRE certifyWith).
      'umk_pub_ed': Bytes.base64Url(offer.umkPubEd),
      // 04 §6.3 🔒 compares both halves, and the server cannot derive this one
      // from `pub_ed`. Write-once on the server (0012, `rf.set_umk_pubs`), so
      // sending it every time is idempotent (ADR 2026-09-24b §2).
      'umk_pub_x': Bytes.base64Url(offer.umkPubX),
    }, bearer: token);
    final body = _json(r);
    if (r.statusCode == 200 &&
        body['status'] == 'certified' &&
        body['device_id'] == cert.deviceId) {
      // Filed only now, and only after the ledger re-checks it: from here the
      // trust store roots this device's own chain (04 §3.4) instead of
      // quarantining its envelopes `certMissing`.
      await ledger.installOwnCert(cert);
      markCertified();
      _log('device_certified');
      // Only now: the record is authored by *this* device, and a reader can
      // only verify it once this install's own chain is rooted in the
      // certificate it just filed (04 §3.4). Announcing first would post a
      // record whose author the device itself could not yet vouch for.
      //
      // Deliberately after [markCertified] and after the log line, and
      // deliberately total: [DeviceAddedAnnouncer.deviceAdded] swallows its
      // own failures, and this `try` is the second belt — the seam is another
      // lane's to implement, and no implementation of it may un-certify a
      // device that the server has certified (06 §3 step 3).
      if (!wasCertified) {
        try {
          await announcer?.deviceAdded(
            cert,
            umkKeyVersion: offer.umkKeyVersion,
          );
        } on Object {
          _log(DeviceAddedRecorder.unfiledEvent);
        }
      }
      return;
    }
    final reason = switch (body['error']) {
      'cert_malformed' => CertRefusal.certMalformed,
      // The offered UMK half is not 32 bytes: like `cert_malformed`, the
      // server could not read what this client built — known, not a retry.
      'umk_pub_malformed' => CertRefusal.certMalformed,
      'cert_invalid' => CertRefusal.certInvalid,
      // The server holds a different x half for this account's UMK. Since
      // activation sends `umk_pub_x` this check runs *before* the signature
      // one (index.ts `certify`), so a phone holding a different UMK than the
      // account's now hears this where it used to hear `cert_invalid` — the
      // same fact, and the same answer: 04 §7 recovery, not a retry.
      'umk_pub_conflict' => CertRefusal.certInvalid,
      'umk_unknown' => CertRefusal.umkUnknown,
      _ => CertRefusal.unavailable,
    };
    _log('device_certify_refused_${reason.name}');
    throw CertificationRefused(reason);
  }

  bool _reoffered = false;

  /// Re-offers this device's **filed** certificate with both UMK public
  /// halves, once per launch and with no prompt (ADR 2026-09-24b §2).
  ///
  /// Why it exists: before 0012 no client sent `umk_pub_x`, so every
  /// installed device's `umk_public_keys` row holds `pub_ed` alone, and a
  /// verifier comparing both halves (04 §6.3 🔒) can never pass against it.
  /// `rf.set_umk_pubs` fills a NULL once, so the first launch after this
  /// build backfills the row and every later one is a no-op on the server.
  ///
  /// **Harmless by construction.** It sends the certificate already on file,
  /// byte for byte — nothing is issued or signed — and whatever the answer,
  /// it changes nothing here: it never files a certificate, never flips
  /// [markCertified] either way, never announces `device_added`, never throws
  /// and never logs a `device_certify_refused_*` event, because it is not a
  /// certification attempt. A device the server has certified stays
  /// certified. The outcome is returned for the caller that wants it
  /// (a test); the composition root fires and forgets.
  ///
  /// It is the first network call of a cold start, and after [restore] no
  /// access token is cached, so it refreshes. That refresh is the one every
  /// other caller in the same window joins ([accessToken] is single-flight):
  /// a second `/refresh` with the same rotated token would read as theft to
  /// the server (06 §4 step 2 🔒) and sign this device out.
  ///
  /// Skipped — nothing posted — when there is no session, no ledger, or no
  /// filed certificate: an uncertified device's own [certifyDevice] carries
  /// both halves already.
  Future<UmkReoffer> reofferUmkPublic() async {
    if (_reoffered) return UmkReoffer.skipped;
    final s = current;
    if (s is! Active) return UmkReoffer.skipped;
    final DeviceCertOffer? offer;
    try {
      offer = certifier?.reofferOwnCert();
    } on Object {
      return UmkReoffer.skipped;
    }
    if (offer == null || offer.cert.deviceId != s.session.deviceId) {
      return UmkReoffer.skipped;
    }
    _reoffered = true;
    final cert = offer.cert;
    try {
      final token = await accessToken();
      final r = await _post(endpoints.devicesCertify, {
        'cert': {
          'signature': Bytes.base64Url(cert.signature),
          'issued_at_ms': cert.issuedAtMs,
          'issued_by_device': cert.deviceId,
        },
        'umk_key_version': offer.umkKeyVersion,
        'umk_pub_ed': Bytes.base64Url(offer.umkPubEd),
        'umk_pub_x': Bytes.base64Url(offer.umkPubX),
      }, bearer: token);
      final body = _json(r);
      if (r.statusCode == 200 &&
          body['status'] == 'certified' &&
          body['device_id'] == cert.deviceId) {
        _log('umk_pub_reoffered');
        return UmkReoffer.accepted;
      }
      // `umk_pub_conflict` is the one refusal worth its own name: the server
      // holds a *different* x half for this UMK, which is a real integrity
      // problem (05c) — surfaced as an event, never acted on here.
      _log(
        body['error'] == 'umk_pub_conflict'
            ? 'umk_pub_conflict'
            : 'umk_reoffer_refused_${r.statusCode}',
      );
      return UmkReoffer.refused;
    } on Object {
      _log('umk_reoffer_unreachable');
      return UmkReoffer.unreachable;
    }
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
    // ADR 2026-09-16 §1–§3: the id is the ledger's, read before any request.
    // No identity → fail closed; this client never mints one.
    final deviceId = await _deviceIdSource();
    if (deviceId == null || !Uuid16.isCanonical(deviceId)) {
      throw const NoDeviceIdentity();
    }
    final pair = await _deviceKeys();
    try {
      final r = await _post(endpoints.devices, {
        'ticket': ticket.value,
        'device_id': deviceId,
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
        if (err == 'device_id_taken') {
          // Another key pair holds this id (ADR 2026-09-16 §2). The id is
          // this device's for life, so there is nothing to retry with.
          _log('device_id_taken');
          throw const AuthFailure(AuthFailureKind.unavailable);
        }
        if (err == 'device_cap' || r.statusCode == 409) {
          _log('device_cap');
          throw const DeviceCapReached();
        }
        _throwGeneric(r, 'device_register');
      }
      final body = _json(r);
      // §3: the server records the id; it never issues one. An echo of any
      // other id is a server this client cannot register with — fail closed,
      // store nothing (the id itself never reaches the log, rule 4).
      if (body['device_id'] != deviceId) {
        _log('device_id_mismatch');
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
      // 06 §3 steps 3–4: registered is not certified. This is the one moment
      // the device both can and must certify — a session is open and the
      // ledger holds the UMK that vouches for it — so it happens here rather
      // than on some later launch. A refusal is not an activation failure:
      // the device is registered and signed in, and stays *sees nothing but
      // itself* (ADR 2026-09-05d §2) until a retry succeeds.
      //
      // The test is what this install *holds*, not what the server *says*: a
      // server that answers `status: "certified"` while this device has filed
      // no certificate would otherwise leave the chain rooted in nothing, and
      // every envelope this device authors quarantined `certMissing` by every
      // reader — including itself after a re-pull. Holding one is cheap;
      // believing a status string instead is not.
      final ledger = certifier;
      if (ledger != null && ledger.ownDeviceCert == null) {
        try {
          await certifyDevice();
        } on Object {
          _log('device_uncertified');
        }
      }
      return session;
    } finally {
      pair.dispose();
    }
  }

  /// Drops the cached access token WITHOUT signing out — the refresh token
  /// stays, so the next call re-mints one (06 §4).
  ///
  /// This is what a 401 on a sync route is allowed to do. ADR 2026-09-05b §2 🔒
  /// forbids treating a plain 401 as a logout: a revoked device is suspended by
  /// a *signed* revocation record, never by a bare status code, so a server
  /// answering 401 must not be able to log a family out of its own ledger.
  void invalidateAccessToken() {
    _accessToken = null;
    _accessExpiresAt = null;
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

  Future<AuthHttpResponse> _post(
    Uri url,
    Map<String, Object?> body, {
    String? bearer,
  }) async {
    final AuthHttpResponse r;
    try {
      r = await _transport.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          clientVersionHeader: _clientVersion,
          if (bearer != null) 'Authorization': 'Bearer $bearer',
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

/// What [HttpAuthClient.reofferUmkPublic] did (ADR 2026-09-24b §2). None of
/// these changes the device's certification — each is only a report.
enum UmkReoffer {
  /// Nothing was posted: already offered this launch, no session, no ledger,
  /// or no filed certificate.
  skipped,

  /// The server re-verified the filed certificate and kept both halves.
  accepted,

  /// The server answered with a refusal. The device is unchanged.
  refused,

  /// The request never got an answer (offline, no token). Unchanged, and not
  /// retried this launch — the next launch offers again.
  unreachable,
}
