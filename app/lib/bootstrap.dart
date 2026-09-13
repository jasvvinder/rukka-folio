// The composition root: everything the app needs built once, by hand, and
// handed to [RukkaFolioApp].
//
// Split out of `main.dart` on 13 Sep 2026. There is no service locator and no
// codegen here deliberately — the whole object graph is readable in one
// function, and the order in which it is built (libsodium, then the keystore,
// then the SQLCipher key, then the database) is itself the contract.
import 'dart:async';
import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:data/data.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sodium_libs/sodium_libs.dart';

import 'features/auth/auth_routes.dart';
import 'features/auth/http_auth_client.dart';
import 'features/auth/http_client_transport.dart';
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
import 'features/members/members_routes.dart';
import 'features/menu/menu_routes.dart';
import 'features/onboarding/onboarding_routes.dart';
import 'features/settings/settings_routes.dart';
import 'main.dart';
import 'shared/app_settings.dart';
import 'shared/ledger/local_ledger.dart';
import 'shared/prefs.dart';
import 'shared/router.dart';
import 'shared/seams/sync_client.dart';
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
      final auth = HttpAuthClient(
        transport: HttpClientTransport(http.Client()),
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
      homeScope.addListener(
        () => unawaited(
          settings.setScope(RkTab.home, encodeScope(homeScope.selected)),
        ),
      );

      runApp(
        RukkaFolioApp(
          db: db,
          // ⚠️ SPEC: the sync_engine adapter onto the `SyncClient` seam lands
          // with the next integration (engine API in packages/sync_engine).
          sync: FakeSyncClient(),
          auth: auth,
          keys: keys,
          now: DateTime.now,
          ledger: LocalLedger(
            db: db,
            keys: keys,
            suite: suite,
            now: DateTime.now,
          ),
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
              onOpenPosition: (line) =>
                  context.push(HomePaths.positionOf(line)),
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
            ...ceremonyRoutes,
            ...devicesRoutes,
            ...homeRoutes,
            ...inboxRoutes,
            ...ledgerRoutes,
            ...membersRoutes,
            ...settingsRoutes,
          ],
        ),
      );
    case MigrationFailed() || QuickCheckFailed() || OpenFailed():
      // 03 §5: fail closed. The support screen (S19.x) is a later lane; this
      // blocks with one plain line and no data on screen.
      runApp(const RukkaFolioBlocked());
  }
}
