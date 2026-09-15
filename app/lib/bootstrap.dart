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

import 'features/auth/auth_routes.dart';
import 'features/auth/http_auth_client.dart';
import 'features/books/books_routes.dart';
import 'features/ceremony/ceremony_routes.dart';
import 'features/devices/at_rest.dart';
import 'features/devices/devices_routes.dart';
import 'features/devices/keychain_key_store.dart';
import 'features/devices/pin_vault.dart';
import 'features/entry/entry_routes.dart';
import 'features/home/home_rebuild.dart';
import 'features/home/home_routes.dart';
import 'features/home/home_scope.dart';
import 'features/home/screens/s1_home_screen.dart';
import 'features/inbox/inbox_routes.dart';
import 'features/ledger/ledger_routes.dart';
import 'features/members/members_api.dart';
import 'features/members/members_routes.dart';
import 'features/members/server_members_repository.dart';
import 'features/menu/menu_routes.dart';
import 'features/onboarding/onboarding_routes.dart';
import 'features/settings/settings_routes.dart';
import 'l10n/gen/app_localizations.dart';
import 'main.dart';
import 'shared/app_settings.dart';
import 'shared/ledger/local_ledger.dart';
import 'shared/prefs.dart';
import 'shared/records/device_record_author.dart';
import 'shared/router.dart';
import 'shared/seams/http_transport.dart';
import 'shared/seams/key_store.dart';
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
      final ledger = LocalLedger(
        db: db,
        keys: keys,
        suite: suite,
        now: DateTime.now,
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
      final members = ServerMembersRepository(
        api: HttpMembersApi(
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
        ),
        tenantId: identity.tenantId,
        userId: identity.userId,
        believes: believeNothing,
        unknownVerifierName: l10n.membersVerifiedSomeone,
        someoneToMeetName: l10n.membersPendingBooksSomeone,
        author: recordAuthor,
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
          ...onboardingRoutes,
          ...authRoutes,
          ...booksRoutes,
          ...ceremonyRoutes,
          ...devicesRoutes,
          ...homeRoutes,
          ...inboxRoutes,
          ...ledgerRoutes,
          ...membersRoutes,
          ...settingsRoutes,
        ],
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
            child: app,
          ),
        ),
      );
    case MigrationFailed() || QuickCheckFailed() || OpenFailed():
      // 03 §5: fail closed. The support screen (S19.x) is a later lane; this
      // blocks with one plain line and no data on screen.
      runApp(const RukkaFolioBlocked());
  }
}
