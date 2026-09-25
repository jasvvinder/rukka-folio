// The composition root: everything the app needs built once, by hand, and
// handed to [RukkaFolioApp].
//
// Split out of `main.dart` on 13 Sep 2026. There is no service locator and no
// codegen here deliberately — the whole object graph is readable in one
// function, and the order in which it is built (libsodium, then the keystore,
// then the SQLCipher key, then the database) is itself the contract.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:data/data.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sodium_libs/sodium_libs.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import 'features/account/account_routes.dart';
import 'features/advances/advances_routes.dart';
import 'features/auth/auth_routes.dart';
import 'features/auth/http_auth_client.dart';
import 'features/books/books_routes.dart';
import 'features/cash_count/cash_count_routes.dart';
import 'features/cash_count/ledger_cash_count_source.dart';
import 'features/close/close_routes.dart';
import 'features/close/ledger_close_source.dart';
import 'features/close/ledger_year_close_source.dart';
import 'features/ceremony/ceremony_routes.dart';
import 'features/devices/at_rest.dart';
import 'features/devices/devices_routes.dart';
import 'features/devices/keychain_key_store.dart';
import 'features/devices/pin_vault.dart';
import 'features/entry/entry_routes.dart';
import 'features/help/help_routes.dart';
import 'features/home/home_rebuild.dart';
import 'features/home/home_routes.dart';
import 'features/home/home_scope.dart';
import 'features/home/screens/s1_home_screen.dart';
import 'features/inbox/inbox_routes.dart';
import 'features/inbox/late_arrivals.dart';
import 'features/inbox/ledger_late_arrivals.dart';
import 'features/inbox/ledger_review_queue.dart';
import 'features/inbox/review_queue.dart';
import 'features/import/import_routes.dart';
import 'features/ledger/ledger_routes.dart';
import 'features/legal/legal_routes.dart';
import 'features/members/members_api.dart';
import 'features/members/members_review_policy.dart';
import 'features/members/members_routes.dart';
import 'features/members/server_members_repository.dart';
import 'features/recovery/recovery_routes.dart';
import 'features/menu/menu_routes.dart';
import 'features/onboarding/onboarding_routes.dart';
import 'features/partners/ledger_partners_port.dart';
import 'features/partners/partners_routes.dart';
import 'features/settings/settings_routes.dart';
import 'features/subscription/subscription_routes.dart';
import 'l10n/gen/app_localizations.dart';
import 'main.dart';
import 'shared/app_settings.dart';
import 'shared/ledger/local_ledger.dart';
import 'shared/prefs.dart';
import 'shared/records/device_added_record.dart';
import 'shared/records/device_record_author.dart';
import 'shared/router.dart';
import 'shared/seams/closed_years.dart';
import 'shared/seams/guardians.dart';
import 'shared/seams/http_transport.dart';
import 'shared/seams/key_store.dart';
import 'shared/seams/recovery_ladder.dart';
import 'shared/seams/review_policy.dart';
import 'shared/sync/sync.dart';
import 'shared/widgets/blocked_screen.dart';

/// Where the edge functions live; `--dart-define=RF_API_BASE=…` in release
/// builds (.env.example). Auth endpoints resolve under `auth-challenge/`.
const apiBase = String.fromEnvironment(
  'RF_API_BASE',
  defaultValue: 'http://127.0.0.1:54321/functions/v1/',
);

/// Sent as `x-rukka-client-version` (06 §4.5 min-version gate).
const clientVersion = String.fromEnvironment(
  'RF_CLIENT_VERSION',
  defaultValue: '0.1.0',
);

/// The SPKI pins for the API host, as comma-separated base64 SHA-256 digests:
/// `--dart-define=RF_SPKI_PINS=<current>,<backup>` (05 §1 🔒 needs at least two
/// so rotation is never an outage).
const spkiPinsB64 = String.fromEnvironment('RF_SPKI_PINS');

/// Builds the pin set for this build (05 §1 🔒, ADR 2026-09-05 §1).
///
/// Empty ⇒ the local-dev set, the only one allowed to disable pinning, and the
/// one the default `RF_API_BASE` (127.0.0.1) needs. The release lane asserts a
/// release never ships it.
///
/// A configured set is verified against SHA-256 over the presented
/// certificate's SPKI: `package:crypto` (app/pubspec.yaml) is the digest —
/// libsodium offers BLAKE2b and HKDF-SHA256, neither a plain digest, and rule
/// 7 forbids hand-rolling one. What the chain source can *see* is still one
/// leaf certificate, and it is a probe rather than the request's own
/// connection — the two ⚠️ SPEC items are in `shared/sync/tls_chain_source.dart`
/// (ADR 2026-09-15, whose suite is F1-05-32…42 and another lane's).
(eng.SpkiPins, eng.TlsChainSource?) spkiPins() {
  if (spkiPinsB64.isEmpty) return (const eng.SpkiPins.localDev(), null);
  final digests = [
    for (final b64 in spkiPinsB64.split(',').where((s) => s.isNotEmpty))
      eng.SpkiPin(Uint8List.fromList(base64.decode(base64.normalize(b64)))),
  ];
  return (
    eng.SpkiPins(digests),
    IoTlsChainSource(
      sha256: (b) => Uint8List.fromList(crypto.sha256.convert(b).bytes),
    ),
  );
}

/// The live [eng.SyncTransport] (05 §1 transport, §3 push, §4 pull, §5 meta):
/// HTTPS + JSON to the deployed edge functions, the 15-minute access token of
/// 06 §4 asked for per request, the min-version header of 06 §4.5, and the pin
/// set of [spkiPins] checked before any request leaves.
///
/// Separate from [bootstrap] so a test can build the door without the whole
/// object graph (F1-05-30 pins it); [bootstrap] hands the result straight to
/// `eng.SyncEngine`.
eng.HttpSyncTransport buildSyncTransport({
  required http.Client client,
  required Future<String> Function() accessTokenOf,
  ForgetAccessToken? forgetAccessToken,
  Uri? functionsRoot,
}) {
  final (pins, tlsChain) = spkiPins();
  return eng.HttpSyncTransport(
    client: client,
    functionsRoot: functionsRoot ?? Uri.parse(apiBase),
    // One token per call, never cached in the transport; a 401 drops the
    // cached token and nothing else — a device never wipes, and never logs
    // out, on the server's word (ADR 2026-09-05b §2 🔒).
    credentials: AuthSyncCredentials(
      accessTokenOf: accessTokenOf,
      forget: forgetAccessToken,
    ),
    clientVersion: clientVersion,
    pins: pins,
    tlsChainSource: tlsChain,
  );
}

/// The engine's clock (05 §2, 09 §1). `sync_engine` is pure Dart and never
/// calls `DateTime.now()` itself; the composition root is where the real clock
/// enters, exactly as the ledger's own `now` does below.
final class SystemSyncClock implements eng.Clock {
  /// Creates the clock.
  const SystemSyncClock();

  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch;
}

/// The identity `LocalLedger` wrote at bootstrap, read without opening the
/// ledger: `{device_id, user_id, tenant_id}`, all canonical uuids. Null on a
/// device that has never bootstrapped a ledger — which is every device until
/// somebody calls `LocalLedger.bootstrapSolo()`.
///
/// Delegates to [readStoredIdentity], which is the one implementation
/// (`shared/ledger/ledger_identity.dart`). Kept as a name because F1-05-31 and
/// the bootstrap wiring tests call it; the parsing lived here twice until
/// ADR 2026-09-16 gave the ledger sole authority over the device id.
Future<LedgerIdentity?> storedIdentity(KeyStore keys) =>
    readStoredIdentity(keys);

/// Builds every dependency and starts the app (03 §5: fail closed).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'rukka_folio.sqlite'));

  // All crypto via libsodium (rule 7): one initialised binding, injected.
  final suite = CryptoSuite(await SodiumInit.init());
  final keys = KeychainKeyStore();

  // At rest (03 §3, 06 §3): the SQLCipher key is 32 CSPRNG bytes kept
  // this-device-only in the platform keystore; `openLedgerDatabase` verifies
  // it unlocked the file and zeroises it. ⚠️ SPEC: the binary is SQLCipher
  // only once the WORKSPACE ROOT pubspec carries
  // `hooks.user_defines.sqlite3.source: sqlcipher` (features/devices/at_rest.dart);
  // on a plain SQLite build the PRAGMA is a no-op and the build must not ship
  // past the dev loop.
  final dbKey = await provisionDatabaseKey(keys, suite);
  final result = await openLedgerDatabase(
    NativeDatabase.createInBackground(file, setup: sqlcipherSetup(dbKey)),
    cipherKey: dbKey,
  );
  switch (result) {
    case Opened(:final db):
      // One HTTP door for the whole app (05 §1, 06 §2–§4): one `http.Client`,
      // one transport, one place that speaks `package:http`. `features/auth`
      // and `features/members` each see it through their own seam.
      final httpClient = http.Client();
      final httpDoor = HttpClientRkTransport(httpClient);

      final auth = HttpAuthClient(
        transport: AuthTransportOverRkHttp(httpDoor),
        suite: suite,
        keys: keys,
        now: DateTime.now,
        baseUrl: Uri.parse(apiBase),
        clientVersion: clientVersion,
        deviceOs: Platform.operatingSystem,
      );
      await auth.restore();

      // Shell state that outlives a screen and a launch (07 §16, 13 §2.2):
      // language, appearance, the two auto-lock values and the scope each tab
      // is showing, kept in the device's protected item store.
      final settings = AppSettings(prefs: KeyStorePrefs(keys));
      await settings.load();

      // The MPIN vault the lock family reads (06 §4.4). Built here rather than
      // hung on RkScope because it needs the libsodium suite, which the scope
      // does not carry.
      final vault = PinVault(keys: keys, suite: suite, now: DateTime.now);

      // 13 §2.2 🔒 scope persists per tab and defaults to last used, so the
      // selection is held by the shell and handed down to S1 — not owned by
      // the screen, which would forget it on every tab switch.
      final homeScope = HomeScopeController();
      final storedScope = settings.scopeOf(RkTab.home);
      if (storedScope != null) {
        final scope = decodeScope(storedScope);
        if (scope != null) homeScope.select(scope);
      }
      // The ledger itself (02 · 03 · 04), opened here because every screen
      // below `LedgerScope` assumes an open facade and because the identity it
      // mints (or reopens) is what the members feature and the sync engine are
      // stamped with. `bootstrapSolo` is idempotent: first run mints device,
      // user and tenant ids and the keys; every later run reopens them. No
      // book is named, so nothing is invented — onboarding still creates the
      // first book (features/onboarding).
      // The auto-post limit this client measures its own entries against
      // (02 §3 🔒, 03 §3.3 rule 5 🔒). It is answered from `book_roles`, which
      // reaches this app through `ServerMembersRepository` — and that
      // repository is built from `identity.tenantId` / `identity.userId`,
      // which exist only once this ledger has bootstrapped. The order cannot
      // be swapped, so the ledger takes the holder now and the real policy is
      // set into it a few lines below, before `runApp`: no screen exists yet
      // to post through the window, and the holder answers *no limit* — never
      // *reviewed* — while it is empty.
      final reviewPolicy = LateReviewPolicy();
      final ledger = LocalLedger(
        db: db,
        keys: keys,
        suite: suite,
        now: DateTime.now,
        reviewPolicy: reviewPolicy,
      );
      final LedgerIdentity identity;
      try {
        identity = await ledger.bootstrapSolo();
      } on Object {
        // 03 §5 fail closed. The one reachable case is *identity present,
        // device keys missing* — a keystore wiped under us, which is the
        // recovery path (04 §7) and not something to paper over by minting a
        // second identity for the same books. ⚠️ SPEC: S19.x explains it; this
        // blocks with one plain line until that screen exists.
        runApp(const RukkaFolioBlocked());
        return;
      }

      // Signing structural facts (ADR 2026-09-05b §1 🔒). Null when this
      // device holds no Ed25519 key or has never registered — and null is the
      // input `ServerMembersRepository` turns into `unauthorized`, which is
      // the correct refusal and stays reachable.
      final recordAuthor = await DeviceRecordAuthor.ifAvailable(
        suite: suite,
        keys: keys,
        deviceIdOf: () async {
          final raw = await keys.read(SessionItems.deviceId);
          return raw == null ? null : utf8.decode(raw);
        },
        clock: RecordHlcClock(DateTime.now),
      );

      // The members feature against the real server (06 §7, ADR 2026-09-05d
      // §9 🔒), for the tenant this install belongs to. `believeNothing` is
      // the posture of a device that has verified nobody: every membership
      // then reads as pending, which is the truth. A guard now exists below
      // and could check a record's chain, but believing a *membership* on it
      // is a trust decision this seam's owner makes, not a wiring detail —
      // left as it stands (lane report M7-W4).
      final l10n = await AppLocalizations.delegate.load(
        settings.locale ?? const Locale('en'),
      );
      final membersApi = HttpMembersApi(
        transport: MembersTransportOverRkHttp(httpDoor),
        functionsRoot: Uri.parse(apiBase),
        accessToken: () async {
          try {
            return await auth.accessToken();
          } on Object {
            return null; // no live session ⇒ `unauthorized`
          }
        },
        clientVersion: clientVersion,
      );
      final members = ServerMembersRepository(
        api: membersApi,
        tenantId: identity.tenantId,
        userId: identity.userId,
        believes: believeNothing,
        unknownVerifierName: l10n.membersVerifiedSomeone,
        someoneToMeetName: l10n.membersPendingBooksSomeone,
        author: recordAuthor,
      );
      // The limit's one real source, closed over the repository built above
      // (02 §1.3 🔒: the authoring client is the only one that may read
      // `book_roles`; the projector never does — 03 §3.3 rule 5 🔒).
      reviewPolicy.policy = MembersReviewPolicy(members);

      // The name this device holds for a member, or the *someone in this
      // book* string — never a raw user id (ADR 2026-09-05c §4: a contact is
      // this phone's, never the server's, so an id is all the wire can carry
      // and an id is not a name).
      String memberName(String userId) {
        for (final m in members.current?.members ?? const <Member>[]) {
          if (m.id == userId) {
            return m.displayName ?? l10n.inboxReviewAuthorUnknown;
          }
        }
        return l10n.inboxReviewAuthorUnknown;
      }

      // ── the recovery ladder (04 §7.3 🔒, 06 §5, 13 §5 F11) ───────────────
      //
      // S11.2 / S11.3 / S11.7 ran on `recovery_ladder.dart`'s fakes until
      // now. These are their live producers over migration 0010's routes, and
      // they are installed as **scopes** below rather than through
      // `recoveryRoutes()`, whose signature is unchanged — a screen never
      // learns which producer it got.
      //
      // Installing them is strictly better than leaving the scopes empty even
      // where a producer cannot finish the job: with no scope each screen
      // falls back to the seam's own fake, and `FakeRecoverySheet` **accepts
      // any well-formed code and reports a restore that did not happen**. A
      // producer that refuses plainly is the truth; a fake that succeeds is
      // not.
      final recoveryApi = HttpRecoveryApi(
        transport: MembersTransportOverRkHttp(httpDoor),
        functionsRoot: Uri.parse(apiBase),
        accessToken: () async {
          try {
            return await auth.accessToken();
          } on Object {
            return null; // no live session ⇒ `unauthorized`
          }
        },
        clientVersion: clientVersion,
      );

      // 04 §7.3 step 2 🔒 — the new phone's fingerprint, drawn small and
      // monospaced so a guardian can read it aloud on the call.
      //
      // ⚠️ SPEC: no doc fixes the *rendering* of a device fingerprint. 04
      // §3.1 defines the UMK fingerprint as BLAKE2b-256 and 04 §7.3 step 2
      // names "new device fingerprint" without a format, so the same digest
      // is taken over the candidate key and its first eight bytes are shown
      // as four groups of four hex characters. Nothing security-bearing rests
      // on the string: the check that matters is ADR 2026-09-13c §3's
      // byte-for-byte comparison of the scanned `DeviceQrPayload` against the
      // relayed candidate key, which is the scanner's, not this line's.
      // Reported to the owner.
      String candidateFingerprint(Uint8List candidatePubX) {
        final d = suite.blake2b256(candidatePubX);
        final hex = [
          for (var i = 0; i < 8; i++)
            d[i].toRadixString(16).padLeft(2, '0').toUpperCase(),
        ].join();
        return [for (var i = 0; i < hex.length; i += 4) hex.substring(i, i + 4)]
            .join(' ');
      }

      // The read side of the guardian set (04 §7.3 Setup, the meta pull's
      // `guardian_sets`). Declared here because S11.2's roster needs it: a
      // recovery attempt is pinned to a **generation** of the set, and the
      // only place this device can learn who was in that generation is the
      // published history.
      final guardiansApi = HttpGuardiansApi(
        transport: MembersTransportOverRkHttp(httpDoor),
        functionsRoot: Uri.parse(apiBase),
        accessToken: () async {
          try {
            return await auth.accessToken();
          } on Object {
            return null; // no live session ⇒ `unauthorized`
          }
        },
        clientVersion: clientVersion,
      );

      final guardianRecovery = HttpGuardianRecovery(
        api: recoveryApi,
        // The real people, at last: the members of the generation the attempt
        // is **pinned** to (0010 pins `share_set_version` at open), each named
        // from this device's own member list — names are never the server's
        // (ADR 2026-09-05c §4 🔒). `progressToWire` now carries the decision
        // rows, so a tick lands on the member a row names and on nobody else;
        // a generation this device cannot read names nobody at all, which
        // under-reports rather than misattributing (`recovery_roster.dart`).
        roster: PinnedGuardianRoster(
          api: guardiansApi,
          nameOf: memberName,
          // ADR 2026-09-05c §4 🔒 — this device holds no number for another
          // member, so R2.2's *Call* link is correctly absent rather than
          // dialling something guessed.
          phoneOf: (_) => null,
        ).call,
        // ⚠️ SPEC: minting and persisting the *candidate* X25519 pair of
        // 04 §7.3 step 1 is `core_crypto`/`features/devices` behaviour and
        // has no producer, so this build re-reads an attempt that is already
        // open and refuses plainly when there is none. Reusing this device's
        // own `pub_x` is the convenient reading of "fresh device keys **+** a
        // candidate X25519 pair" and is not taken here. Reported.
        candidateKey: null,
        // No camera package is in the app (cf. ADR 2026-09-12e), so the
        // recovery ceremony of ADR 2026-09-13c ruling 1 🔒 reports
        // `unavailable` rather than a screen pretending the control works.
        scanner: null,
      );

      final guardianApprovals = HttpGuardianApprovals(
        api: recoveryApi,
        requesterNameOf: memberName,
        // ⚠️ SPEC: a guardian cannot learn the *model* of the requester's new
        // phone — the subject's `devices` rows are not a guardian's to read,
        // and 04 §7.3 step 2 🔒 asks for the requester's name and the device
        // **fingerprint**, not a device name. R2.3 draws a name anyway. The
        // empty string is passed rather than an invented one; S11.7 should
        // drop that line when it is empty. Reported as an open item against
        // DESIGN-PACK R2.3 and `features/recovery`.
        deviceNameOf: (_) => '',
        fingerprintOf: candidateFingerprint,
        // ADR 2026-09-05c §4 🔒 — a number is never the server's, and this
        // device holds none for another member, so R2.2/R2.3's *Call* link is
        // correctly absent rather than dialling something guessed.
        phoneOf: (_) => null,
        // With no scanner the check of ADR 2026-09-13c ruling 3 🔒 cannot
        // pass, so `approve` refuses with `RecoveryCandidateUnverified` and
        // no share is ever sealed to an unverified candidate. That is the
        // posture the ruling asks for when the check cannot be performed —
        // never a bypass. `decline` still works, because refusing is safe.
        scanner: null,
        resealer: null,
      );

      // Rung 3 — the paper sheet (04 §7.4 🔒, migration 0011). The routes
      // exist now, so this producer **fetches** the user's own current
      // `sealed_RK_blob` instead of refusing before it starts.
      //
      // ⚠️ SPEC: it is still installed with **no opener**, and that is the
      // conservative reading rather than an omission. Two things are missing
      // and neither is this file's to invent:
      //
      //   1. a **framing** for `SealedRecoveryBlob`. `core_crypto`'s
      //      `sealUmkUnderRecoveryKey` returns `suite_version`, a 24-byte
      //      nonce and the ciphertext as three fields and serialises none of
      //      them; 0011 stores one opaque byte string. Choosing the byte
      //      layout is `core_crypto` behaviour (the `GuardianShare.encode`
      //      precedent), not an app-layer guess — and a wrong guess would
      //      read as a wrong *code* to whoever typed one.
      //   2. a way to **put the recovered key back**. `LedgerKeyMaterial`
      //      holds `umk` and offers no adoption path, so a build that opened
      //      the blob could verify the code and then drop the key it found —
      //      and S11.3 would draw a restore that did not happen, which is
      //      exactly what installing `FakeRecoverySheet` would do.
      //
      // So `submit` fetches nothing and refuses plainly (`no opener`), and no
      // correctly copied sheet is ever told it is wrong. Both items are
      // reported for the lane that owns `core_crypto` and the ledger.
      //
      // The **precheck** is installed, though, and it is a correction rather
      // than an addition. The seam used to carry a ⚠️ SPEC claiming 04 §7.4's
      // 2-char checksum was unspecified "so nothing here verifies one". It is
      // specified: `core_crypto`'s `_sheetChecksum`
      // (`packages/core_crypto/lib/src/recovery.dart:318`) is the first two
      // Crockford symbols of `BLAKE2b-256(version ‖ user_id ‖ RK)`, and
      // `recoverySheetFromTyped` (`:360`) throws
      // `RecoverySheetChecksumFailed` on a mismatch. So a mistype is caught
      // on this phone, for nothing, before the rate-limited `recovery/sheet`
      // route is spent on a code already known to be wrong.
      //
      // It runs here and not behind the seam because verifying the checksum
      // means decoding the payload, and the payload **is** `RK`. The sheet is
      // disposed in the same statement that made it, so the key exists for
      // the length of one comparison and is zeroised whichever way the check
      // goes (04 §7.4, 07 §5.6 🔒). Nothing is returned but the bool.
      bool sheetCodeIsWorthTrying(RecoverySheetCode code) {
        RecoverySheet? sheet;
        try {
          sheet = recoverySheetFromTyped(suite, code.value);
          return true;
        } on RecoverySheetChecksumFailed {
          return false; // a mistype — R2.4's first stated cause
        } on FormatException {
          return false; // wrong length, foreign symbol, unknown version
        } finally {
          sheet?.dispose();
        }
      }

      final recoverySheet = HttpRecoverySheet(
        api: recoveryApi,
        precheck: sheetCodeIsWorthTrying,
      );

      // ── the ladder itself (04 §7.0 🔒, §7.1, §7.2, §7.4 🔒; 13 §5 F11) ───
      //
      // One call, because the probe map is the fact worth pinning and a map
      // built inline inside `bootstrap()` cannot be: see
      // [buildRecoveryLadder], and F1-06-89 / F1-06-90 over it.
      final recoveryLadder = buildRecoveryLadder(
        keys: keys,
        guardians: guardiansApi,
        recovery: recoveryApi,
      );

      // ── the socket (05 §1) ──────────────────────────────────────────────
      //
      // The engine over the real transport. Its key material comes from the
      // ledger through the one accessor that hands it over — device pair, UMK
      // and the **live** book-key store the projector also reads, so a key
      // that arrives on a pull opens envelopes for both halves at once (05 §5)
      // and there is no second unwrap path anywhere in the app.
      //
      // `trust` starts holding exactly one belief: this user's own
      // ceremony-verified UMK (`material` is the `VerifiedUmkSource`, and it
      // answers for nobody else — 04 §8.2 🔒). Device certificates arrive on
      // the meta channel and the engine files them; another member's UMK is
      // believed only after a ceremony, so their envelopes stay
      // `authorUnverified` until one happens. That is the conservative
      // reading, and it is the reason `believes: believeNothing` above is
      // still right.
      final material = ledger.keyMaterial;
      final trust = eng.RecordTrustStore(umks: material);

      // 04 §3.4 🔒 — the device certificate, the root of the chain. Three
      // wires, all of them late because the trust store is built *from* the
      // ledger's material and so cannot be handed to either constructor:
      //   • the ledger issues and files this device's certificate (the UMK
      //     secret never leaves it) and the auth client uploads it over
      //     `devices/certify` at activation (06 §3 step 3);
      //   • a certificate filed in an earlier session is read back at open
      //     and seeds the trust store, so a cold start verifies its own
      //     envelopes instead of quarantining them `certMissing`;
      //   • one filed later in this session reaches the same store live.
      // Other devices' certificates still arrive on the meta channel and are
      // believed only under a ceremony-verified UMK — this adds exactly one
      // belief, about this install itself.
      //
      // ⚠️ SPEC — the same question ADR 2026-09-16 settled for the device id,
      // still open for the *user* id. `ChainVerifier` looks a certificate's
      // user up with `verifiedUmkOf(cert.user_id)`, and this install's
      // certificate names the user id the ledger minted, which is the only one
      // that resolves. The server mints its own `user_id` at OTP verify and
      // the `devices` meta row carries that one, so the certificate the sync
      // engine rebuilds from meta (`CryptoGuard.buildCert`) is labelled with
      // an id no UMK is verified for — `authorUnverified` — and it replaces
      // this one in `trust.certs`. The signature is identical either way
      // (04 §3.4 does not sign the user id); only the label differs. Left as
      // it stands: reconciling the two is an identity decision, not a wiring
      // one (lane report M7-U7 `open`).
      auth.certifier = ledger;
      // 06 §5 🔒 / ADR 2026-09-05d §6 — a newly certified device announces
      // itself as a `device_added` signed record, over the same author and
      // the same record route the members feature already uses (lane R1).
      // With no author (no Ed25519 key yet) the device certifies exactly as
      // before and files nothing; a failed post never un-certifies it.
      if (recordAuthor != null) {
        auth.announcer = DeviceAddedRecorder(
          author: recordAuthor,
          tenantId: identity.tenantId,
          post: membersApi.postRecords,
        );
      }
      final ownCert = ledger.ownDeviceCert;
      if (ownCert != null) trust.certs[ownCert.deviceId] = ownCert;
      ledger.onOwnCert = (cert) => trust.certs[cert.deviceId] = cert;
      // ADR 2026-09-24b §2 — every installed device re-offers its UMK's X25519
      // half once per launch, with no prompt. Before 0012 no client sent it,
      // so an installed device's `umk_public_keys` row holds `pub_ed` alone
      // and nobody can verify its user (04 §6.3 🔒 compares both halves).
      // It re-sends the certificate already on file, so the server re-stores
      // the same row and `rf.set_umk_pubs` fills the NULL once; whatever the
      // answer, the device's certification is untouched. Not awaited: 07 §1.7
      // 🔒, a round trip never stands in front of the user. It is the launch's
      // first token refresh; `accessToken()` is single-flight, so a sync cycle
      // that asks in the same instant joins it instead of presenting the
      // rotated refresh token a second time (06 §4 step 2 🔒 — a reuse
      // revokes the family). Pinned by F1-24b-2 (launch_reoffer_wiring_test).
      unawaited(auth.reofferUmkPublic());
      final engine = eng.SyncEngine(
        db: db,
        mirror: ledger.mirror,
        transport: buildSyncTransport(
          client: httpClient,
          accessTokenOf: auth.accessToken,
        ),
        clock: const SystemSyncClock(),
        guard: eng.CryptoGuard(
          suite: suite,
          keys: material.bookKeys,
          trust: trust,
          me: material.device,
          umk: material.umk,
        ),
        trust: trust,
        deviceId: identity.deviceId,
        userId: identity.userId,
        tenantId: identity.tenantId,
        // Pulled envelopes are projected by the same projector the write path
        // uses — one Recompute, one set of keys (03 §3.3: a pure function of
        // the ordered envelopes).
        recompute: ledger.recompute,
        // A key accepted on the meta channel is unwrapped into the store
        // above — which lives only as long as this process. The ledger writes
        // the sealed blob to `key_cache` (03 §3.1) so the next launch reads it
        // back; without this seam a device that joined someone else's book
        // holds the key once and then sits in `key_wait` for ever, because the
        // meta cursor has passed the `wrapped_keys` row (05 §4, §5).
        keySink: ledger,
      );
      final sync = EngineSyncClient(
        engine: engine,
        // 05 §9's `Waiting for entries from {name}'s phone`. The engine speaks
        // device ids; the device → user step is the trust store's (from meta),
        // the user → name step this device's own contact knowledge. Neither is
        // the server's to hold (ADR 2026-09-05c §4), so an unknown author is
        // *"someone in this book"* rather than a uuid.
        memberName: (deviceId) {
          final userId = trust.userOf(deviceId);
          if (userId != null) {
            for (final m in members.current?.members ?? const <Member>[]) {
              if (m.id == userId && m.displayName != null) {
                return m.displayName!;
              }
            }
          }
          return l10n.membersVerifiedSomeone;
        },
        // 05 §7's backstop poll is *on unmetered networks*; this app has no
        // metering source yet, and the client arms no poll without one rather
        // than guessing. The other four triggers are all wired.
        unmetered: null,
      );
      // App open (05 §7) — one status read now, then a cycle; resumes come
      // through the observer. Fire-and-forget: 07 §1.7 🔒 says a sync cycle
      // never stands in front of the user, so nothing below awaits it.
      await sync.start();
      WidgetsBinding.instance.addObserver(SyncLifecycleObserver(sync));

      homeScope.addListener(() {
        unawaited(
          settings.setScope(RkTab.home, encodeScope(homeScope.selected)),
        );
        // 05 §7 🔒: a scope switch is a foreground pull.
        sync.onScopeSwitch();
      });

      final app = RukkaFolioApp(
        db: db,
        sync: sync,
        auth: auth,
        keys: keys,
        now: DateTime.now,
        ledger: ledger,
        updateRequired: auth.updateRequired,
        settings: settings,
        pinVault: vault,
        // S1 with the shell's scope holder. `homeRoot` (features/home) is
        // the same screen without it — kept there for tests and previews;
        // the two wirings must be changed together.
        homeTabRoot: RkTabRoot(
          builder: (context) => HomeScreen(
            scopeController: homeScope,
            // S1.4's producer (07 §28 🔒) — the same source `homeRoot`
            // passes; the two wirings change together.
            rebuildProgress: rebuildProgressOf(context),
            onOpenPosition: (line) => context.push(HomePaths.positionOf(line)),
            onOpenAccount: (accountId) =>
                context.push(LedgerPaths.statementOf(accountId)),
            onVerb: (kind) =>
                context.push('${RkPaths.entry}?verb=${kind.wire}'),
          ),
        ),
        ledgerTabRoot: ledgerRoot,
        // S6 Inbox (07 §9). `inboxRoutes` carries S6.2's stepper on the root
        // navigator, so the review flow covers the tab bar.
        inboxTabRoot: inboxRoot(),
        menuTabRoot: menuRoot,
        entryRoot: entryScreen,
        featureRoutes: [
          ...accountRoutes,
          ...advancesRoutes,
          ...onboardingRoutes,
          ...partnersRoutes,
          ...authRoutes,
          ...booksRoutes,
          ...cashCountRoutes,
          ...ceremonyRoutes,
          ...closeRoutes,
          ...devicesRoutes,
          ...helpRoutes,
          ...homeRoutes,
          ...inboxRoutes,
          ...importRoutes,
          ...ledgerRoutes,
          ...legalRoutes,
          ...membersRoutes,
          // S11.5/S11.6/S11.8 — the activation ladder, root navigator
          // (13 §5 F11). A finished restore lands on Home, which
          // features/recovery does not own.
          ...recoveryRoutes(onRestored: (context) => context.go(RkPaths.home)),
          ...settingsRoutes,
          // S12/S12.1 — Menu → Subscription and Settings → Subscription
          // (07 §20); the doors live in features/menu and features/settings.
          ...subscriptionRoutes,
        ],
      );

      // ── 04 §7.3 🔒 Setup: the trusted-member set behind S11.1 ───────────
      //
      // S11.1 ran on `FakeGuardians` until now — a fake that accepts a set and
      // reports a split that never happened. This is its live producer over
      // the same 0010 routes: the meta pull's `guardian_sets` history on the
      // read side, `POST sync-meta/recovery/guardians` on the write side.
      //
      // The two facts it needs come from the two places that hold them, and
      // from nowhere else:
      //
      //   • the roster is `features/members`' — names and where the mutual
      //     ceremony stands — and reaches the repository through the
      //     `GuardianRosterSource` port, so nothing in `shared/sync` imports
      //     a feature;
      //   • the **key** is `material`'s. `LedgerKeyMaterial.verifiedUmkOf`
      //     answers for this install's own user and null for everybody else
      //     (04 §8.2 🔒), and a share is sealed only to a `VerifiedUmkPublic`
      //     — `VerifiedGuardian` takes nothing else. So until a ceremony's
      //     verified key is *persisted* for another member, this repository
      //     refuses to publish rather than sealing a piece of `UMK_priv` to a
      //     key nobody confirmed. Refusing is the posture rule 5 asks for when
      //     the check cannot be made; reported as an open item.
      final guardians = ServerGuardians(
        // The same client S11.2's roster reads the set history through — one
        // door to `guardian_sets`, so the set a screen shows and the set a
        // recovery attempts against can never come from two readings.
        api: guardiansApi,
        roster: () async => GuardianRoster(
          candidates: [
            for (final m in members.current?.members ?? const <Member>[])
              GuardianCandidateRow(
                userId: m.id,
                name: memberName(m.id),
                // 04 §7.3 asks for a *mutual ceremony per guardian*. This
                // device holds a 04 §6.4 log entry only for one that finished,
                // and the membership reads `active` only once keys were
                // wrapped; anything less is *not started* rather than
                // *started*, which would have S11.1 imply a half-done ceremony
                // this device knows nothing about.
                ceremony:
                    m.verification != null && m.state == MembershipState.active
                    ? GuardianCeremony.done
                    : GuardianCeremony.notStarted,
                // ⚠️ SPEC: S11.1's *Meet them* opens a ceremony invite, and
                // `MembersSnapshot` carries no invite id per member — only
                // this user's own invitations (`myInvites`). Null disables the
                // control **with its reason** (13 §4.3) instead of opening a
                // ceremony against an id this build guessed. Reported.
                inviteId: null,
                isYou: m.isYou,
              ),
          ],
          // The set protects this user's own key. It is not a book object and
          // no book role gates it (06 §1.0 🔒: a role is per book), so there is
          // no read-only case to derive here.
          readOnly: false,
        ),
        verified: material,
        sealer: CryptoGuardianSealer(
          suite: suite,
          umk: () => material.umk,
        ).call,
      );

      // ── 04 §6 the ceremony: S9.2 / S9.3 (ADR 2026-09-24b §2) ────────────
      //
      // `CeremonyScope` was declared at M7 and installed nowhere, so S9.3
      // rendered its *Checking.* placeholder in production for ever. Both of
      // the verifier's seams exist on the wire now and are bound here:
      //
      //   • the relayed keys — BOTH halves — from the meta pull's
      //     `umk_public_keys` rows (sync-meta relays `pub_ed` and `pub_x`). A
      //     row with `pub_ed` alone is named, not compared: S9.3 tells the
      //     user to ask the person to open the app once (the re-offer above
      //     is what fills it);
      //   • the live session, by subject and tenant, over
      //     `GET sync-meta/ceremony?subject_user_id=&tenant_id=`.
      //
      // S9.2's side is NOT bound: its per-invite nonce is server-generated
      // (04 §6.1 🔒) and no route yet returns one the invitee can attribute
      // to itself. `nonces` is left null, so S9.2 keeps its placeholder rather
      // than draw a nonce on this device. ⚠️ SPEC — reported.
      //
      // No camera package is in the app, so the scope carries no scanner:
      // S9.3 opens on *Enter code instead*, its equal path (design-system
      // §3.1 rule 7), and never on a dead camera.
      final ceremonyApi = HttpCeremonyApi(
        transport: httpDoor,
        functionsRoot: Uri.parse(apiBase),
        accessToken: () async {
          try {
            return await auth.accessToken();
          } on Object {
            return null; // no live session ⇒ `unauthorized`
          }
        },
        clientVersion: clientVersion,
      );
      // One call, so the two bindings below are pinned by F1-24b-3 rather
      // than written inline where a default could silently stand in for them
      // (see [buildLiveCeremonySessions]).
      final ceremonySessions = buildLiveCeremonySessions(
        suite: suite,
        api: ceremonyApi,
        pullMeta: membersApi.pullMeta,
        tenantId: identity.tenantId,
        selfUserId: identity.userId,
        ownUmk: () {
          try {
            return ledger.keyMaterial.umk.public;
          } on Object {
            return null; // a closed ledger opens nothing
          }
        },
        verifierName: () => l10n.membersVerifiedSomeone,
        memberName: memberName,
        now: DateTime.now,
        // ⚠️ SPEC 04 §6.3 — no durable security-event store exists yet (see
        // `DelegatedCeremonyEventLog`); the permanent entry is the signed
        // `verification_event` the sink below writes.
        log: const DelegatedCeremonyEventLog(),
        // 04 §8.2 🔒 — a proved key is kept, through the ledger's one door.
        keys: ledger.verifiedMembers,
      );

      // S9/S9.1 read the repository off the tree; with no tenant yet there is
      // nothing to read and the scope's own empty fake is the right answer.
      // S0.9 (13 §3.2) reads its invitations off the tree the same way. Bound
      // to the real repository the joiner's screen shows a real invitation;
      // unbound it falls back to the scope's empty fake, which is the safe
      // state (no invitation claimed) but never a true one. `pending` is the
      // greyed shared books of 07 §12 — absent until a meta pull has run, so
      // the gateway reports none rather than guessing.
      runApp(
        MembersRepositoryScope(
          repository: members,
          child: InvitationGatewayScope(
            gateway: DelegatedInvitationGateway(
              offers: members.myInvites,
              accept: members.acceptInvite,
              pending: () async =>
                  members.current?.pendingBooks ?? const <PendingBook>[],
            ),
            // S5.5, S10, S10.3, S10.4 and S14 read their ledger-backed
            // sources off the tree (features/cash_count, features/close,
            // features/inbox, features/partners); each takes only the live
            // ledger — no clock, no config, no other seam.
            //
            // `ClosedYearsScope` is the FY switcher's one source (ADR
            // 2026-09-09 §4 🔒): S4 and S8.2 read it here and fall back to
            // what they were constructed with when it is absent, so *no
            // switcher until the first year close* stays true by construction
            // — `certifiedYears` is empty until then.
            //
            // `LateArrivalsScope` is device-wide on purpose: the Inbox is one
            // surface (07 §9 🔒), so the tray merges every book this device
            // holds rather than following Home's selected book. So is
            // `ReviewQueueScope`, for the same reason: S6's approvals now run
            // on the real ledger (02 §3 🔒) instead of `FakeReviewQueue`. The
            // author's name is the members repository's — the ledger holds no
            // contact book — and falls back to the *someone in this book*
            // string when this phone does not hold the contact (ADR
            // 2026-09-05c §4), never to a raw user id.
            child: CashCountScope(
              source: LedgerCashCountSource(ledger),
              child: CloseScope(
                source: LedgerCloseSource(ledger),
                child: YearCloseScope(
                  source: LedgerYearCloseSource(ledger),
                  child: ClosedYearsScope(
                    source: LedgerClosedYearsSource(ledger).call,
                    child: LateArrivalsScope(
                      tray: LedgerLateArrivals(ledger),
                      child: ReviewQueueScope(
                        queue: LedgerReviewQueue(
                          ledger,
                          authorNameOf: memberName,
                        ),
                        child: PartnersScope(
                          port: LedgerPartnersPort(ledger),
                          // The activation ladder's three producers. They sit
                          // innermost because they are the newest and own no
                          // other screen; nothing below reads them but S11.2,
                          // S11.3 and S11.7, each of which still falls back to
                          // what it was constructed with when a scope is
                          // absent (07 §1 rule 6 — a missing scope is never a
                          // red screen).
                          // S11.5 and S11.6's one source. Outermost of the
                          // activation producers because it is the one the
                          // fork asks before any other screen exists — and
                          // because installing it is what stops S11.6 running
                          // on `FakeRecoveryLadder` in production, where every
                          // rung reads as available whether it is or not.
                          child: RecoveryLadderScope(
                            ladder: recoveryLadder,
                            child: GuardianRecoveryScope(
                              recovery: guardianRecovery,
                              child: RecoverySheetScope(
                                sheet: recoverySheet,
                                child: GuardianApprovalsScope(
                                  approvals: guardianApprovals,
                                  // S11.1's live producer, innermost with the
                                  // other activation producers. The screen
                                  // still falls back to the seam's own fake
                                  // when the scope is absent (07 §1 rule 6 —
                                  // a missing scope is never a red screen),
                                  // which is why installing it here is what
                                  // stops S11.1 running on `FakeGuardians` in
                                  // production.
                                  child: GuardiansScope(
                                    repository: guardians,
                                    // S9.2 / S9.3 open through this factory;
                                    // without it both routes fall back to
                                    // `NoCeremonySessions` and wait for ever.
                                    child: CeremonyScope(
                                      sessions: ceremonySessions,
                                      child: app,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    case MigrationFailed() || QuickCheckFailed() || OpenFailed():
      // 03 §5: fail closed. The support screen (S19.x) is a later lane; this
      // blocks with one plain line and no data on screen.
      runApp(const RukkaFolioBlocked());
  }
}
