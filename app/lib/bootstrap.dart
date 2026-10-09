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
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart' show Printing;
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
import 'features/devices/guardian_standing.dart';
import 'features/devices/keychain_key_store.dart';
import 'features/devices/keystore_platform.dart';
import 'features/devices/pin_vault.dart';
import 'features/entry/entry_routes.dart';
import 'features/help/help_routes.dart';
import 'features/home/home_routes.dart';
import 'features/home/home_scope.dart';
import 'features/inbox/inbox_routes.dart';
import 'features/inbox/late_arrivals.dart';
import 'features/inbox/ledger_late_arrivals.dart';
import 'features/inbox/ledger_review_queue.dart';
import 'features/inbox/review_queue.dart';
import 'features/import/import_routes.dart';
import 'features/ledger/ledger_routes.dart';
import 'features/legal/legal_routes.dart';
import 'features/lock/cold_start_gate.dart';
import 'features/lock/keystore_biometric_gate.dart';
import 'features/lock/relock_sync_nudge.dart';
import 'features/members/invite_nonce_relay.dart';
import 'features/members/members_api.dart';
import 'features/members/members_review_policy.dart';
import 'features/members/members_routes.dart';
import 'features/members/server_members_repository.dart';
import 'features/recovery/recovery_routes.dart';
import 'features/menu/menu_routes.dart';
import 'features/demo/demo_gate.dart' show watchDemoSignIn;
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
import 'shared/seams/auth_client.dart' show Active;
import 'shared/seams/closed_years.dart';
import 'shared/seams/dialer.dart';
import 'shared/seams/share_sheet.dart';
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

/// The ledger the composition root opens (02 · 03 · 04): the one
/// construction in this file, with the provisional-identity guard **on**
/// (ADR 2026-10-04b §2 🔒) — until `/otp/verify` echoes this install's own
/// user id, `createBook` and every other authoring door refuse with
/// `IdentityNotConfirmed`, and no certificate or UMK half leaves.
///
/// Separate from [bootstrap] so C-04b-2 (`bootstrap_wiring_test.dart`) can
/// drive the production construction; [bootstrap] is its only caller.
LocalLedger productionLedger({
  required LedgerDatabase db,
  required KeyStore keys,
  required CryptoSuite suite,
  required DateTime Function() now,
  ReviewPolicy reviewPolicy = noReviewPolicy,
}) => LocalLedger(
  db: db,
  keys: keys,
  suite: suite,
  now: now,
  reviewPolicy: reviewPolicy,
  requireConfirmedIdentity: true,
);

/// S11.1's roster (04 §7.3 Setup) from the members feature's [snapshot],
/// read in [tenantId] — the install's tenant, whose members the snapshot
/// holds, and so the tenant a set chosen from them is set up in (ADR
/// 2026-10-03b §1 🔒: `guardian_sets.tenant_id`). Without it
/// [ServerGuardians.save] refuses `no_tenant` before anything is sealed, so
/// a roster with no tenant is an S11.1 that can never save (M13-REV89U
/// finding 1).
///
/// Separate from [bootstrap] so F1-03b-3 can drive a real save through it;
/// [bootstrap] is its only production caller.
GuardianRoster guardianRosterOf(
  MembersSnapshot? snapshot, {
  required String tenantId,
  required String Function(String userId) nameOf,
}) => GuardianRoster(
  candidates: [
    for (final m in snapshot?.members ?? const <Member>[])
      GuardianCandidateRow(
        userId: m.id,
        name: nameOf(m.id),
        // 04 §7.3 asks for a *mutual ceremony per guardian*. This device holds
        // a 04 §6.4 log entry only for one that finished, and the membership
        // reads `active` only once keys were wrapped; anything less is *not
        // started* rather than *started*, which would have S11.1 imply a
        // half-done ceremony this device knows nothing about.
        ceremony: m.verification != null && m.state == MembershipState.active
            ? GuardianCeremony.done
            : GuardianCeremony.notStarted,
        isYou: m.isYou,
      ),
  ],
  // The set protects this user's own key. It is not a book object and no book
  // role gates it (06 §1.0 🔒: a role is per book), so there is no read-only
  // case to derive here.
  readOnly: false,
  tenantId: tenantId,
);

/// Installs the S11 guardians row's live reading (ADR 2026-10-03b §4 🔒,
/// `features/devices/guardian_standing.dart`) above [child], and owns it:
/// the [GuardianStanding] is made once, from [trust] — the
/// `RecordTrustStore` the sync engine files `guardian_sets` rows and
/// membership facts into — with S11.1's [guardians] as its second reading
/// and change signal, and is disposed when this leaves the tree (its
/// backstop poll and stream subscriptions with it).
///
/// Without it S11 keeps the row's ordinary line: no reading, no claim
/// (M13-REV89U finding 2). Pinned by F1-03b-4.
///
/// The subject is read late (ADR 2026-10-09 §1 🔒): the root passes
/// [subjectUserIdOf], the ledger's live user id, and the host re-makes the
/// reading when a C-04b-3 re-mint or a C-04b-4 adoption changes it — never a
/// relaunch. [subjectUserId] fixes it instead, for a caller whose id cannot
/// change; exactly one is given.
class GuardianStandingHost extends StatefulWidget {
  /// Creates the host.
  const GuardianStandingHost({
    super.key,
    required this.trust,
    this.subjectUserId,
    this.subjectUserIdOf,
    required this.guardians,
    required this.child,
  }) : assert(
         (subjectUserId == null) != (subjectUserIdOf == null),
         'exactly one of subjectUserId and subjectUserIdOf',
       );

  /// The engine's trust store — the facts its revocation count reads.
  final eng.RecordTrustStore trust;

  /// The user id the engine counts this device's own revocations under,
  /// fixed.
  final String? subjectUserId;

  /// The same id, live, with its change signal.
  final ValueListenable<String>? subjectUserIdOf;

  /// S11.1's repository, the one door to `guardian_sets` the screens read.
  final ServerGuardians guardians;

  /// The subtree S11 is routed in.
  final Widget child;

  @override
  State<GuardianStandingHost> createState() => _GuardianStandingHostState();
}

class _GuardianStandingHostState extends State<GuardianStandingHost> {
  // Made once per subject: S11 listens to it, and the scope treats a new
  // object as a new reading. The root builds this widget once per process;
  // only a change of the install's user id makes a second one.
  late String _subject = _currentSubject();
  late GuardianStanding _standing = trustStoreGuardianStanding(
    widget.trust,
    subjectUserId: _subject,
    guardians: widget.guardians,
  );

  String _currentSubject() =>
      widget.subjectUserIdOf?.value ?? widget.subjectUserId!;

  @override
  void initState() {
    super.initState();
    widget.subjectUserIdOf?.addListener(_subjectChanged);
  }

  void _subjectChanged() {
    final now = _currentSubject();
    if (now == _subject || !mounted) return;
    final old = _standing;
    setState(() {
      _subject = now;
      _standing = trustStoreGuardianStanding(
        widget.trust,
        subjectUserId: now,
        guardians: widget.guardians,
      );
    });
    // After the frame that hands S11 the new reading, so nothing still
    // listening to the old one is cut off mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    widget.subjectUserIdOf?.removeListener(_subjectChanged);
    _standing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      GuardianStandingScope(standing: _standing, child: widget.child);
}

/// Rebuilds the composition root after a recovered UMK is adopted (rung 3,
/// ADR 2026-10-06d §2). Until ADR 2026-10-09 §1 it also ran after a
/// provisional re-mint (ADR 2026-10-04b §2 last bullet; review finding
/// ID107C-3); the root now reads ids and keys late, so a re-mint needs no
/// rebuild (desk 126). What follows describes why a rebuild was needed then
/// and still is for a replaced UMK, which is retired, not zeroised, until
/// the old root's `ledger.dispose()`.
///
/// Everything [bootstrap] builds from the ledger's identity is stamped at
/// launch: the sync engine's user and tenant ids, its `CryptoGuard`'s UMK and
/// book-key store, the members repository, S11.1's tenant. A re-mint in the
/// same process leaves all of them naming the discarded ids (the ledger
/// retires rather than zeroises the old UMK, so nothing throws meanwhile, but
/// nothing syncs either). The fix is the one a cold start already gives: the
/// root is built again from what the ledger persisted.
///
/// When: the first time the app comes back to the foreground after the
/// re-minted identity has been confirmed **and** the session is live
/// ([ready]) — never in the middle of S0.2's verify or activation, and never
/// under the user's hands. What the user then sees is exactly a cold start
/// after the platform killed a backgrounded app, which every launch path
/// already handles. ⚠️ SPEC: no doc names a moment for this; the one chosen
/// adds no screen, no string and no state a cold start does not already have.
class RootRelaunch with WidgetsBindingObserver {
  /// [ready] says the re-minted identity is safe to rebuild around;
  /// [relaunch] tears the root down and builds it again.
  RootRelaunch({required this.ready, required this.relaunch});

  /// True once nothing is in flight that a rebuild would cut short.
  final bool Function() ready;

  /// Tears this root down and runs [bootstrap] again.
  final Future<void> Function() relaunch;

  bool _armed = false;
  bool _fired = false;

  /// Whether a re-mint has happened and the rebuild has not yet run.
  bool get pending => _armed && !_fired;

  /// The ledger's `onIdentityReminted` and `onUmkAdopted`.
  void arm() => _armed = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !pending || !ready()) return;
    _fired = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(relaunch());
  }
}

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
      // 03 §6 🔒 / ADR 2026-09-05c §8 (desk 150): a phone backup never carries
      // the books. Android keeps the whole app out of backup in its manifest;
      // iOS needs NSURLIsExcludedFromBackupKey on the file and the SQLite side
      // files, set through the app's keystore channel. A refusal is not a
      // reason to lock the person out of their own books — the file is
      // useless without the this-device-only key — so it is swallowed.
      if (Platform.isIOS) {
        try {
          await const MethodChannelKeystorePlatform().excludeFromBackup([
            for (final suffix in const ['', '-wal', '-shm', '-journal'])
              '${file.path}$suffix',
          ]);
        } on Object {
          // Retried at the next launch.
        }
      }

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
      // DEBUG ONLY (owner-directed, 4 Oct 2026): the S0.3 demo card needs the
      // number that signs in during this launch, which `Active` does not
      // carry. Listens to nothing — and holds no number — unless the demo
      // gate is open; a release build never opens it (features/demo).
      watchDemoSignIn(auth);

      // Shell state that outlives a screen and a launch (07 §16, 13 §2.2):
      // language, appearance, the two auto-lock values and the scope each tab
      // is showing, kept in the device's protected item store.
      final settings = AppSettings(prefs: KeyStorePrefs(keys));
      await settings.load();

      // The MPIN vault the lock family reads (06 §4.4). Built here rather than
      // hung on RkScope because it needs the libsodium suite, which the scope
      // does not carry.
      //
      // ADR 2026-10-06 🔒 — the fingerprint guards a gate key, never the
      // device keys. Every verified MPIN (set at O4b, or accepted at S15):
      //   • opens the sealed device-key store at once (ruling 3, onPinProven
      //     runs before the PIN's answer is returned);
      //   • mints a new gate for the biometric set enrolled now, or none on a
      //     PIN-only phone (rulings 2 and 4, afterPinProven). An enrolment
      //     change therefore costs only the gate: the device keys, the UMK
      //     copy and the books are never touched. Never on a biometric alone.
      final biometricGate = KeystoreBiometricGate(
        keys: keys,
        platform: const MethodChannelKeystorePlatform(),
      );
      final vault = PinVault(
        keys: keys,
        suite: suite,
        now: DateTime.now,
        onPinProven: keys.unsealAfterPin,
        afterPinProven: () async {
          await keys.afterPinProven();
        },
      );

      // The biometric sheet (the gate read; a legacy class's own prompt)
      // speaks ARB, not the plugin's English defaults (whose subtitle offers
      // "device credentials" — 07 §5.6 forbids); its negative button is the
      // way to the PIN.
      final l10n = await AppLocalizations.delegate.load(
        settings.locale ?? const Locale('en'),
      );
      keys.setPromptCopy(
        title: l10n.lockBiometricPrompt,
        subtitle: l10n.lockBiometricSheetSubtitle,
        cancel: l10n.lockPinUseInstead,
      );

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
      // mints (or reopens) is what the members feature and the sync engine
      // read — late, through `ledger.binding` (ADR 2026-10-09 §1 🔒).
      // `openIdentity` is idempotent: a first launch mints the device, user
      // and tenant ids and no key material; every later run reopens them.
      // The keys are minted inside S0.2, through the ledger, immediately
      // before `POST devices` (§2: `auth.keyMint` below). No book is named,
      // so nothing is invented — onboarding still creates the first book
      // (features/onboarding).
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
      final ledger = productionLedger(
        db: db,
        keys: keys,
        suite: suite,
        now: DateTime.now,
        reviewPolicy: reviewPolicy,
      );
      // ADR 2026-10-06 §3 🔒 — the device-key store is sealed: nothing reads
      // the device keys, unwraps the UMK, signs or syncs until the person is
      // through S15 by the gate (the biometric) or the MPIN. So on any install
      // with an MPIN, S15 goes up first and the ledger opens behind it
      // (features/lock/cold_start_gate.dart): a cancelled or failed biometric
      // leaves *Use PIN instead*, never RukkaFolioBlocked. With no MPIN yet
      // (first run, onboarding before O4b) there is no lock to pass and
      // nothing to verify, so the store opens as it is (⚠️ SPEC in
      // keychain_key_store.dart `unsealIfNoPin`).
      //
      // Ruling 1: the device keys are minted when the device is first
      // registered (S0.2) — by the ledger's `mintForRegistration`, which the
      // auth client runs immediately before `POST devices` (ADR 2026-10-09
      // §2 🔒) — straight into the hardware-backed class with no
      // user-authentication binding, where they stay. A first launch mints
      // ids only, so an install with an MPIN (after O4b, after S0.2) always
      // has keys to open here.
      if (!await keys.unsealIfNoPin()) {
        final through = Completer<ColdStartResult>();
        runApp(
          ColdStartApp(
            locale: settings.locale,
            themeMode: settings.appearance,
            child: ColdStartGate(
              vault: vault,
              attempt: (reason) =>
                  biometricGate.openAtColdStart(reason: reason),
              open: () => ledger.openIdentity(),
              onDone: through.complete,
            ),
          ),
        );
        if (await through.future != ColdStartResult.opened) {
          // The device keys are absent, a legacy biometric-bound class was
          // invalidated, or only the wrapped UMK is gone: nothing was removed
          // (ruling 4), and the books need the recovery ladder (04 §7).
          // ⚠️ SPEC: S19.x / the S11 entry from here is not built; this
          // blocks with one plain line, as a wiped keystore always has.
          runApp(const RukkaFolioBlocked());
          return;
        }
        // The person is through; the in-app S15 must not ask again for this
        // launch.
        biometricGate.admitOnce();
      }
      try {
        await ledger.openIdentity();
      } on Object {
        // 03 §5 fail closed. The one reachable case is *identity present,
        // device keys missing* — a keystore wiped under us, which is the
        // recovery path (04 §7) and not something to paper over by minting a
        // second identity for the same books. An install with no keys yet
        // opens instead, as *not registered yet*, only while nothing was
        // authored, no certificate was filed and no device was registered
        // (ADR 2026-10-09 *Open*, `LocalLedger._reopen`). ⚠️ SPEC: S19.x
        // explains it; this blocks with one plain line until that screen
        // exists.
        runApp(const RukkaFolioBlocked());
        return;
      }
      // ADR 2026-10-09 §1 🔒 — everything below reads the install's ids and
      // keys through this view, at use, never in a constructor: before S0.2
      // it answers *not registered yet* (the engine holds, nothing is
      // signed), and the S0.2 mint, a C-04b-3 re-mint or a C-04b-4 adoption
      // takes effect without a relaunch.
      final identity = ledger.binding;
      // ADR 2026-10-06 §5 🔒: an install whose device keys still sit in a
      // legacy class (biometric-bound, or ADR 2026-10-05b's PIN-only) moves
      // now, behind the unlock that just opened them — copy, read back and
      // compare, flip, mint the gate, then delete the old items. A failure
      // part-way leaves the old items opening; it is tried again next launch.
      try {
        await keys.migrateAfterUnlock();
      } on Object {
        // Nothing logged (rule 4); the old class still opens.
      }
      // ADR 2026-10-04b §1–§2 🔒: `/otp/verify` proposes this ledger's user id
      // and confirms the identity on the echo (or re-mints it once on
      // `user_id_taken`). Bound here, before any screen can reach S0.2.
      auth.signupIdentity = ledger;
      // ADR 2026-10-09 §2 🔒: S0.2's key step is the ledger's — seeds, and a
      // new account's UMK and wrap, in one idempotent step immediately before
      // `POST devices`. The auth client mints nothing of its own.
      auth.keyMint = ledger;

      // Signing structural facts (ADR 2026-09-05b §1 🔒). Built always and
      // read late (ADR 2026-10-09 §1 🔒): every signature reads the device id
      // and the Ed25519 seed at that moment, so a device registered later in
      // this launch signs without a relaunch. Until it has registered — no
      // device id stored, no seed — each signature refuses `unauthorized`,
      // which is the correct refusal and stays reachable. A provisional
      // identity signs no record either (ADR 2026-10-04b §2 🔒): no device id
      // is offered until signup has confirmed it.
      final recordAuthor = DeviceRecordAuthor(
        suite: suite,
        keys: keys,
        deviceIdOf: () async {
          if (!ledger.identityConfirmed) return null;
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
        tenantIdOf: () => identity.tenantId.value,
        userIdOf: () => identity.userId.value,
        believes: believeNothing,
        unknownVerifierName: l10n.membersVerifiedSomeone,
        someoneToMeetName: l10n.membersPendingBooksSomeone,
        author: recordAuthor,
        // ⚠️ SPEC (M11-INV2): no `inviteLinkOf` — the client has no ruled
        // invite-link format (ADR 2026-09-15 §4 fixes the host, nothing fixes
        // the path), so a created invite carries no link and the share panel
        // offers nothing to send, saying why (it names no join path: S0.9 is
        // entered only by deep link). Owner desk item; never invented here.
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

      // ── the camera and the dialer (ADR 2026-09-19 🔒) ──────────────────
      //
      // `mobile_scanner` behind `CeremonyScanner`, one scanner per screen
      // (each screen disposes the one it is handed). The recovery scans read
      // through [RecoveryCamera], which opens the scan over whichever of
      // S11.2 / S11.3 / S11.7 lent it a navigator; every comparison is
      // `core_crypto`'s, and only an outcome reaches a screen.
      final recoveryCamera = RecoveryCamera(
        newScanner: MobileScannerCeremonyScanner.new,
      );
      // R2.2 / R2.3's *Call*: `tel:` through `launchUrl`, never
      // `canLaunchUrl`, so no LSApplicationQueriesSchemes / <queries> entry
      // exists or is needed (ruling 2).
      const dialer = UrlLauncherDialer();
      // S9.1's share sheet (ADR 2026-09-25 §2 — the inviter sends the invite
      // from their own phone). ⚠️ No package in pubspec raises a text share
      // sheet (`printing` shares PDFs only), so the live binding copies the
      // message to the clipboard and S9.1 says to paste it — until a
      // dependency ADR admits one (e.g. `share_plus`). M11-INV2 open item.
      const shareSheet = ClipboardShareSheet();

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
        // 04 §7.3 step 1 — the *candidate* X25519 pair, its own pair and one
        // per attempt (ADR 2026-09-24b §1 🔒): minted from libsodium when this
        // phone opens an attempt, held in the platform key store under
        // `KeyIds.recoveryCandidate` until the attempt closes, zeroised on
        // every close and after reconstruct. Never this device's `pub_x`,
        // never a device key, never a recipient of a book key.
        candidateKeys: KeyStoreRecoveryCandidate(keys: keys, suite: suite),
        // The recovery ceremony of ADR 2026-09-13c ruling 1 🔒: a member's
        // screen shows this user's key; `Ceremony.verifyQr` compares it with
        // the relayed one. QR only (ruling 2) — there is no typed branch.
        //
        // ⚠️ SPEC: **not installed yet, deliberately.** The scan compares
        // against a code that *another member's* phone draws for this user —
        // ruling 1's "renders it as the 04 §6.1 `QrPayload` from its
        // ceremony-verified copy", which the ADR places on S11.7 as *Show
        // {name}'s key*. Nothing in the app draws that code yet: the only QR
        // it renders is S9.2's, of the member's **own** user id and key, and
        // `verifyQr` fails that on the user id every time. Installed now, the
        // natural action — scanning the square on the member's screen — would
        // end on the hard fail *does not match this account. Stop here*, and
        // (ruling 1 🔒) close the attempt. Absent, S11.2 says honestly that
        // this phone cannot scan yet (review SCAN1 #2). The builder is ready
        // and tested (`ownKeyQrScanner`, F1-07-313 / F1-13c-1): once *Show
        // {name}'s key* lands, pass
        //   `ownKeyQrScanner(suite: suite, read: recoveryCamera.read,
        //    userId: identity.userId, relayedOwnUmk: …)`
        // here and flip F1-07-313's root pin, which holds this line. The
        // relayed side is the user's own row with both halves only (04 §6.3
        // 🔒, ADR 2026-09-24b §2): `MetaRelayedUmkSource(membersApi.pullMeta)`
        // over `identity.userId`, `RelayedUmkComplete(:umk)` → umk, anything
        // else → null, so the scan refuses before the camera opens.
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
        // ADR 2026-09-13c ruling 3 🔒: the new phone's `DeviceQrPayload`,
        // compared by `Ceremony.verifyRecoveryCandidateQr` against the
        // relayed request. Until it answers *verified*, `approve` refuses
        // with `RecoveryCandidateUnverified`. `decline` needs no scan.
        //
        // ⚠️ SPEC: still no resealer — 04 §7.3 step 3's re-seal is not
        // built — so a verified scan cannot yet become an approval. The seam
        // therefore answers *unavailable* without opening the camera while
        // `resealer` is null, and S11.7 keeps its honest cannot-approve state
        // rather than enabling an *Approve* that always fails (07 §1 rule 6
        // 🔒, review SCAN1 #4). The scanner is installed so that the re-seal
        // lane has only one line to change.
        scanner: candidateQrScanner(suite: suite, read: recoveryCamera.read),
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
        reader: recoveryCamera.read,
        // R2.4's camera path: the sheet's QR becomes the code the typed
        // path would make (`features/recovery/sheet_qr.dart`).
        codeOfQr: (qr) => recoverySheetCodeOfQr(suite, qr),
      );

      // Rung 3's making half (04 §7.4 🔒; ADR 2026-10-06d ruling 3 🔒): S0.5b
      // makes the sheet from this install's UMK, publishes the sealed blob
      // and only then opens the page in the platform's **print** sheet
      // (`Printing.layoutPdf`, not `sharePdf`: the share path writes the
      // bytes to a temp file, and this page is the key — 04 §7.6). The check
      // reads through the same camera as S11.3 (ADR 2026-09-19 ruling 1 🔒).
      // RK's lifetime is stated in `recovery_sheet_service.dart`'s header.
      final recoverySheetMaker = LiveRecoverySheetService(
        ledger: ledger,
        api: recoveryApi,
        // `layoutPdf` answers false when the person cancels the sheet: that
        // is not an opened page, so S0.5b's *I've kept it safe* stays asleep.
        printer: (pdf, name) =>
            Printing.layoutPdf(onLayout: (_) async => pdf, name: name),
        render: (content, locale) => renderRecoverySheet(content, locale),
        read: recoveryCamera.read,
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
      //
      // Read through `identity` (ADR 2026-10-09 §1 🔒): `BoundUmkSource`
      // believes whatever UMK the binding answers at each verification —
      // nobody before S0.2, the re-minted user after a C-04b-3 re-mint.
      final trust = eng.RecordTrustStore(umks: eng.BoundUmkSource(identity));

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
      auth.announcer = DeviceAddedRecorder.late(
        author: recordAuthor,
        tenantIdOf: () => identity.tenantId.value,
        post: membersApi.postRecords,
      );
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
      // ADR 2026-10-09 §1 🔒: built once, before any key may exist. The
      // engine reads who it is, and the guard what it holds, from `identity`
      // at every round and every call: before S0.2 a round sends nothing and
      // holds `notRegistered`; the mint is used at the next round.
      final engine = eng.SyncEngine.late(
        db: db,
        mirror: ledger.mirror,
        transport: buildSyncTransport(
          client: httpClient,
          accessTokenOf: auth.accessToken,
        ),
        clock: const SystemSyncClock(),
        guard: eng.CryptoGuard.late(
          suite: suite,
          trust: trust,
          material: identity,
        ),
        trust: trust,
        identity: identity,
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
      // ADR 2026-10-06 §3 🔒: a resume that puts S15 up (the background
      // timeout) seals the device keys as S15 mounts, so the resume pull
      // waits for that frame and runs only while they are open; the unlock
      // that reopens them is the pull instead (features/lock/
      // relock_sync_nudge.dart).
      final syncObserver = RelockAwareSyncNudge(
        sealed: () => keys.sealed,
        nudge: sync.onAppForeground,
      );
      keys.onReopened = sync.onAppForeground;
      WidgetsBinding.instance.addObserver(syncObserver);

      // ADR 2026-10-04b §2: a `409 user_id_taken` re-mints the provisional
      // identity in this process, after everything above was stamped with the
      // old ids. Bound before `runApp`, so before any S0.2 can verify.
      // ADR 2026-10-09 §1 🔒: everything above reads the ids late (desk 126),
      // so a re-mint takes effect for them at once. The root is still
      // rebuilt after one, at the next safe foreground, for the one part
      // that still takes the ids at launch: the ceremony builder
      // (`buildLiveCeremonySessions(tenantId:, selfUserId:)`, features/
      // ceremony, its call shape pinned by F1-24b-3). Without it S9.2/S9.3
      // ran under the discarded ids for the rest of the process (review
      // finding KEY168B-2). ⚠️ SPEC: ADR 10-09 §1's list does not name the
      // ceremony builder; once its owner reads the ids late, this arm goes.
      // A C-04b-4 adoption needs no arm: the adopted device is never
      // confirmed before its UMK arrives (`awaitingAccountUmk`), so [ready]
      // never holds for it, and the UMK's arrival arms below. A recovered
      // UMK (rung 3, ADR
      // 2026-10-06d §2) still rebuilds the root once it is safe to: the
      // replaced UMK is retired, not zeroised, while a borrower may hold it,
      // and only the rebuild's `ledger.dispose()` zeroises it; the trust
      // store's own-certificate belief, filed under the replaced UMK, goes
      // with the old root.
      final relaunch = RootRelaunch(
        ready: () => ledger.identityConfirmed && auth.current is Active,
        relaunch: () async {
          WidgetsBinding.instance.removeObserver(syncObserver);
          keys.onReopened = null;
          // Unmount every screen first: they read the database closed below.
          runApp(const SizedBox.shrink());
          await WidgetsBinding.instance.endOfFrame;
          await sync.dispose();
          httpClient.close();
          ledger.dispose(); // zeroises the live and the retired UMK
          await db.close();
          await bootstrap();
        },
      );
      ledger.onIdentityReminted = relaunch.arm;
      ledger.onUmkAdopted = relaunch.arm;
      WidgetsBinding.instance.addObserver(relaunch);

      homeScope.addListener(() {
        unawaited(
          settings.setScope(RkTab.home, encodeScope(homeScope.selected)),
        );
        // 05 §7 🔒: a scope switch is a foreground pull.
        sync.onScopeSwitch();
      });

      // S9.1 / S9 *Send invite*, *Invite again* and *Resend* (ADR
      // 2026-09-25 §2) read the share sheet from here, above the navigator,
      // so a modal sheet finds it too.
      // The app as the routes see it. It is wrapped once more below, after
      // S11.1's repository exists, and that wrapping is what the scopes
      // around it receive as `app`.
      // ADR 2026-10-06b 🔒 — Home is unreachable until F1/F1b hands over
      // (`settings.onboarded`); every launch of an install that is not
      // onboarded resumes the chain, with no launch argument. S0.2's result
      // is the restored session, S0.8's the vault; S0.3/S0.4's answers ride
      // the chain's own flow (onboarding_gate.dart). One gate: the router's
      // redirect and F1b's end through the ladder read the same answers.
      final onboardingGate = OnboardingGate.over(
        auth: auth,
        vault: vault,
        flow: onboardingFlow,
      );

      final shell = ShareSheetScope(
        sheet: shareSheet,
        // S0.5b's sheet maker (rung 3, ADR 2026-10-06d ruling 3 🔒), over
        // every route so the S0.7 row's reopen finds it too.
        child: RecoverySheetServiceScope(
          service: recoverySheetMaker,
          child: RukkaFolioApp(
            db: db,
            sync: sync,
            auth: auth,
            keys: keys,
            now: DateTime.now,
            ledger: ledger,
            updateRequired: auth.updateRequired,
            settings: settings,
            pinVault: vault,
            onboardingGate: onboardingGate,
            // ADR 2026-10-05b: S15 asks the device-key custody — PIN-only phones
            // get the boxes and no biometric button (§1).
            biometrics: biometricGate,
            // S12.x — the entitlement reading every route, sheet and the shell's
            // S12.5 banner read, mounted by the app above its router (ADR
            // 2026-09-24b §13). Untokened is the only honest production reading
            // until the verified producer lands (PLAN desk 23c): Free, never
            // locked (ADR 2026-09-05g §1 🔒). The producer replaces this one
            // binding and nothing below changes.
            entitlement: const UntokenedEntitlementSource(),
            // S12.1's plan list from the server catalogue (ADR 2026-09-25 §6;
            // `GET /sync-meta/plans`). It hands back the last catalogue it
            // read when offline, and never the offline mirror: a phone that has
            // never reached the server is told so, with a retry.
            planCatalogue: HttpPlanCatalogueSource(
              transport: httpDoor,
              functionsRoot: Uri.parse(apiBase),
              accessToken: () async {
                try {
                  return await auth.accessToken();
                } on Object {
                  return null;
                }
              },
              clientVersion: clientVersion,
            ),
            // S1 with the shell's scope holder, through `homeScreenFor` — the one
            // wiring the shipped app and `homeRoot` (tests, previews) share, so
            // every door S1 has (07 §10 🔒 reconciliation, 07 §13 🔒 Close card,
            // S21 search, the S0.7 setup doors) is a door here (desk 132).
            homeTabRoot: homeTabRootWith(homeScope),
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
              ...recoveryRoutes(
                // F1b's end through the ladder (13 §5): a hand-over to Home
                // only for a phone that is set up — a session and a PIN — and
                // only then recorded as onboarded (ADR 2026-10-06b ruling 1);
                // S11.8 with no device activated resumes the chain instead.
                onRestored: onboardingGate.handOverIfReady,
              ),
              ...settingsRoutes,
              // S12/S12.1 — Menu → Subscription and Settings → Subscription
              // (07 §20); the doors live in features/menu and features/settings.
              ...subscriptionRoutes,
            ],
          ),
        ),
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
        // ADR 2026-10-03b §1 🔒 — read in this install's tenant, the one
        // `members` is the repository of; the builder is F1-03b-3's.
        roster: () async => guardianRosterOf(
          members.current,
          tenantId: identity.tenantId.value,
          nameOf: memberName,
        ),
        // Read at each save (ADR 2026-10-09 §1 🔒): nobody is believed, and
        // nothing is sealed, before S0.2.
        verified: eng.BoundUmkSource(identity),
        sealer: CryptoGuardianSealer(
          suite: suite,
          umk: () => ledger.keyMaterial.umk,
        ).call,
      );

      // ── ADR 2026-10-03b §4 🔒 S11's guardians row ───────────────────────
      //
      // When the set can no longer switch off a lost phone. The reading is
      // over `trust`, the store the engine files `guardian_sets` rows and
      // membership facts into and counts revocations from, joined to S11.1's
      // read-back through `guardians`; the host makes it once and disposes it
      // with the tree. It wraps the shell directly, so every route — S11
      // among them — sits under it.
      final app = GuardianStandingHost(
        trust: trust,
        // ⚠️ SPEC (desk 107; ADR 2026-09-16 *Open*: the user id is unruled) —
        // the id the engine counts this device's own revocations under
        // (`SyncEngine.userId`), as `trustStoreGuardianStanding` asks. It is
        // LEDGER-minted (`LocalLedger._firstRun`), while the `guardian_sets`
        // rows and membership facts the engine files carry the SERVER-minted
        // id (auth-challenge `signupUser`; `SessionItems.userId`). Until the
        // two are reconciled the row finds no set for this id and never
        // warns — the same blind spot as the engine's own count
        // (`SyncEngine._ownCount`). No mapping is invented here.
        subjectUserIdOf: identity.userId,
        guardians: guardians,
        child: shell,
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
      // S9.2's side is bound to the RELAYED invite nonce (ADR 2026-09-25b
      // §3): the inviter's device drew it and signed it into the `invite`
      // record, and sync-meta hands it back on `GET invites` and on the accept
      // answer (§2). `InviteNonceRelay` pairs it to the invite THIS device
      // accepted, by `invite_id` — which is why the joiner's accept (S0.9,
      // the gateway below) goes through the same relay. This device never
      // draws an invite nonce: none relayed is S9.2's says-why state.
      // *Regenerate* keeps the nonce and opens a fresh session (§4).
      // After a restart the relay still knows which invite is this device's
      // own: the accepted id — the id only, never the nonce — is kept in the
      // protected item store, and the nonce is read back from `GET invites`
      // (25b §2). ⚠️ SPEC reading in `invite_nonce_relay.dart`.
      //
      // The scope carries a scanner *factory* (ADR 2026-09-19 ruling 1 🔒):
      // S9.3 disposes the camera it is handed. Denied or absent, it opens on
      // *Enter code instead*, its equal path (design-system §3.1 rule 7).
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
      final inviteNonces = InviteNonceRelay(
        offers: membersApi.myInvites,
        accept: membersApi.acceptInviteRelayed,
        store: KeyStorePrefs(keys),
      );
      final ceremonySessions = buildLiveCeremonySessions(
        suite: suite,
        api: ceremonyApi,
        pullMeta: membersApi.pullMeta,
        nonces: relayedInviteNonceOver(inviteNonces.nonce),
        // ⚠️ SPEC (ADR 2026-10-09 §1 lists the parts that capture ids; the
        // ceremony builder is not among them, yet it does): it takes fixed
        // ids (features/ceremony), so these are the ids at launch. After a
        // C-04b-3 re-mint the root is rebuilt at the next safe foreground
        // (`ledger.onIdentityReminted = relaunch.arm` above, review finding
        // KEY168B-2) — HEAD's behaviour before ADR 10-09. Between the
        // re-mint and that rebuild S9.2/S9.3 still name the discarded ids;
        // closing that gap needs the builder to read ids late, which is the
        // ceremony owner's (lane report M13-KEY168B). Not changed here,
        // because F1-24b-3 pins this call's shape.
        tenantId: identity.tenantId.value,
        selfUserId: identity.userId.value,
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
              // Through the nonce relay, so the invite accepted here is the
              // one S9.2 pairs its nonce to (ADR 2026-09-25b §3).
              accept: inviteNonces.acceptInvite,
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
                                    // The recovery scans' camera and the
                                    // *Call* controls' dialer (ADR
                                    // 2026-09-19 🔒), read by S11.2, S11.3
                                    // and S11.7 only.
                                    child: RecoveryCameraScope(
                                      camera: recoveryCamera,
                                      child: DialerScope(
                                        dialer: dialer,
                                        // S9.2 / S9.3 open through this
                                        // factory; without it both routes
                                        // fall back to `NoCeremonySessions`
                                        // and wait for ever.
                                        child: CeremonyScope(
                                          sessions: ceremonySessions,
                                          newScanner:
                                              MobileScannerCeremonyScanner.new,
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
          ),
        ),
      );
    case MigrationFailed() || QuickCheckFailed() || OpenFailed():
      // 03 §5: fail closed. The support screen (S19.x) is a later lane; this
      // blocks with one plain line and no data on screen.
      runApp(const RukkaFolioBlocked());
  }
}
