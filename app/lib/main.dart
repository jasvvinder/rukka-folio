import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:data/data.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sodium_libs/sodium_libs.dart';

import 'features/auth/auth_routes.dart';
import 'features/auth/http_auth_client.dart';
import 'features/auth/http_client_transport.dart';
import 'features/devices/at_rest.dart';
import 'features/devices/devices_routes.dart';
import 'features/home/home_routes.dart';
import 'features/devices/keychain_key_store.dart';
import 'features/ledger/ledger_routes.dart';
import 'features/onboarding/onboarding_routes.dart';
import 'l10n/gen/app_localizations.dart';
import 'shared/app_scope.dart';
import 'shared/ledger/ledger_scope.dart';
import 'shared/ledger/local_ledger.dart';
import 'shared/router.dart';
import 'shared/seams/auth_client.dart';
import 'shared/seams/key_store.dart';
import 'shared/seams/sync_client.dart';
import 'shared/theme.dart';
import 'shared/tokens.dart';

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

Future<void> main() async {
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
          homeTabRoot: homeRoot,
          ledgerTabRoot: ledgerRoot,
          featureRoutes: [
            ...onboardingRoutes,
            ...authRoutes,
            ...devicesRoutes,
            ...homeRoutes,
            ...ledgerRoutes,
          ],
        ),
      );
    case MigrationFailed() || QuickCheckFailed() || OpenFailed():
      // 03 §5: fail closed. The support screen (S19.x) is a later lane; this
      // blocks with one plain line and no data on screen.
      runApp(const RukkaFolioBlocked());
  }
}

/// The app: theme from tokens, EN/PA/HI, the 13 §3.1 shell, and one scope of
/// dependencies. Feature routes are composed here at integration.
class RukkaFolioApp extends StatefulWidget {
  const RukkaFolioApp({
    super.key,
    required this.db,
    required this.sync,
    required this.auth,
    this.keys,
    required this.now,
    this.locale,
    this.featureRoutes = const [],
    this.homeTabRoot,
    this.ledgerTabRoot,
    this.router,
    this.ledger,
    this.updateRequired,
  });

  final LedgerDatabase db;
  final SyncClient sync;
  final AuthClient auth;

  /// Secrets at rest; defaults to the in-memory fake until lane C's Keychain store lands.
  final KeyStore? keys;
  final DateTime Function() now;

  /// Forced locale (tests, previews); null follows the device.
  final Locale? locale;

  /// Routes from `features/*/<feature>_routes.dart`.
  final List<RouteBase> featureRoutes;

  /// The Home tab's root (S1); null leaves the tab's placeholder in place.
  final RkTabRoot? homeTabRoot;

  /// The Ledger tab's root (S3); null leaves the tab's placeholder in place.
  final RkTabRoot? ledgerTabRoot;

  /// A prebuilt router (tests); otherwise [buildRouter] with [featureRoutes].
  final GoRouter? router;

  /// The ledger facade every data screen reads through [LedgerScope]; null
  /// (shell-only tests) mounts no scope and screens show their empty state.
  final LocalLedger? ledger;

  /// The 426 gate (06 §4.5): a non-null value routes to S19.1 at once.
  final ValueListenable<UpdateRequired?>? updateRequired;

  @override
  State<RukkaFolioApp> createState() => _RukkaFolioAppState();
}

class _RukkaFolioAppState extends State<RukkaFolioApp> {
  late final GoRouter _router =
      widget.router ??
      buildRouter(
        featureRoutes: widget.featureRoutes,
        home: widget.homeTabRoot,
        ledger: widget.ledgerTabRoot,
      );

  @override
  void initState() {
    super.initState();
    widget.updateRequired?.addListener(_onUpdateRequired);
  }

  @override
  void dispose() {
    widget.updateRequired?.removeListener(_onUpdateRequired);
    super.dispose();
  }

  void _onUpdateRequired() {
    final gate = widget.updateRequired?.value;
    if (gate != null) _router.go(RkPaths.updateRequired, extra: gate);
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: widget.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: rkLocalizationsDelegates,
      theme: rkTheme(Brightness.light),
      darkTheme: rkTheme(Brightness.dark),
      routerConfig: _router,
    );
    final ledger = widget.ledger;
    return RkScope(
      db: widget.db,
      sync: widget.sync,
      auth: widget.auth,
      keys: widget.keys ?? FakeKeyStore(),
      now: widget.now,
      child: ledger == null ? app : LedgerScope(ledger: ledger, child: app),
    );
  }
}

/// The l10n delegates every MaterialApp in this repo installs.
const rkLocalizationsDelegates = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Shown when the ledger cannot be opened (03 §5 fail-closed). No data, no
/// codes on screen — one sentence.
class RukkaFolioBlocked extends StatelessWidget {
  const RukkaFolioBlocked({super.key, this.locale});

  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: rkLocalizationsDelegates,
      theme: rkTheme(Brightness.light),
      darkTheme: rkTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(RkSpace.gutter),
              child: Center(
                child: Text(
                  AppLocalizations.of(context).appOpenFailedBody,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
