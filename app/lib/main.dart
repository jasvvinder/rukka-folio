import 'dart:async';
import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:data/data.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sodium_libs/sodium_libs.dart';

import 'features/auth/auth_routes.dart';
import 'features/auth/http_auth_client.dart';
import 'features/auth/http_client_transport.dart';
import 'features/devices/at_rest.dart';
import 'features/devices/devices_routes.dart';
import 'features/devices/pin_vault.dart';
import 'features/entry/entry_routes.dart';
import 'features/home/home_rebuild.dart';
import 'features/home/home_routes.dart';
import 'features/home/home_scope.dart';
import 'features/home/screens/s1_home_screen.dart';
import 'features/devices/keychain_key_store.dart';
import 'features/ledger/ledger_routes.dart';
import 'features/lock/lock_routes.dart';
import 'features/menu/menu_routes.dart';
import 'features/onboarding/onboarding_routes.dart';
import 'features/settings/settings_routes.dart';
import 'l10n/gen/app_localizations.dart';
import 'shared/app_scope.dart';
import 'shared/app_settings.dart';
import 'shared/ledger/ledger_scope.dart';
import 'shared/ledger/local_ledger.dart';
import 'shared/lock/auto_lock.dart';
import 'shared/lock/draft_activity.dart';
import 'shared/prefs.dart';
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
          menuTabRoot: menuRoot,
          entryRoot: entryScreen,
          featureRoutes: [
            ...onboardingRoutes,
            ...authRoutes,
            ...devicesRoutes,
            ...homeRoutes,
            ...ledgerRoutes,
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
    this.menuTabRoot,
    this.entryRoot,
    this.router,
    this.ledger,
    this.updateRequired,
    this.settings,
    this.pinVault,
    this.biometrics,
    this.draftActivity,
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

  /// The Menu tab's root (S8); null leaves the tab's placeholder in place.
  /// Its `routes` carry S8.1 Reports one level below (13 §3.2 depth rule),
  /// so Reports opens with the tab bar still visible.
  final RkTabRoot? menuTabRoot;

  /// S2 Add entry, pushed over the shell by the centre ( + ) — not a tab
  /// (13 §3.1); null leaves the entry placeholder in place.
  final WidgetBuilder? entryRoot;

  /// A prebuilt router (tests); otherwise [buildRouter] with [featureRoutes].
  final GoRouter? router;

  /// The ledger facade every data screen reads through [LedgerScope]; null
  /// (shell-only tests) mounts no scope and screens show their empty state.
  final LocalLedger? ledger;

  /// The 426 gate (06 §4.5): a non-null value routes to S19.1 at once.
  final ValueListenable<UpdateRequired?>? updateRequired;

  /// Language, appearance, the auto-lock values and per-tab scope (07 §16,
  /// 13 §2.2); null gives an unpersisted set over [MemoryPrefs].
  final AppSettings? settings;

  /// The MPIN vault (06 §4.4). Non-null mounts the lock family: [LockScope],
  /// `lockRoutes` on the root navigator and the two auto-lock timers. Null
  /// (shell-only tests) leaves the app ungated.
  final PinVault? pinVault;

  /// The biometric seam (07 §5.6). A platform gate is a separate lane, so the
  /// default is the fake answering **unavailable** — never *success*: a gate
  /// that waves everyone through would make the lock decorative on a real
  /// build. Unavailable is the honest state (no sensor wired) and the MPIN
  /// carries the unlock, exactly as 07 §5.6 specifies for a sensor that
  /// cannot run.
  final BiometricGate? biometrics;

  /// The draft-activity registry the idle lock reads (07 §5.6 🔒); null
  /// builds one.
  final DraftActivity? draftActivity;

  @override
  State<RukkaFolioApp> createState() => _RukkaFolioAppState();
}

class _RukkaFolioAppState extends State<RukkaFolioApp> {
  late final AppSettings _settings =
      widget.settings ?? AppSettings(prefs: MemoryPrefs());
  late final AppLockState _lock = AppLockState();
  late final DraftActivity _draft = widget.draftActivity ?? DraftActivity();
  late final BiometricGate _biometrics =
      widget.biometrics ??
      FakeBiometricGate(const [BiometricOutcome.unavailable]);

  /// True once a PIN is known to exist: only then may a timer lock the app.
  bool _lockArmed = false;
  bool _lockShowing = false;

  late final GoRouter _router =
      widget.router ??
      buildRouter(
        featureRoutes: [
          ...widget.featureRoutes,
          // The lock covers everything, shell included, so S15 mounts on the
          // root navigator (lock_routes.dart).
          if (widget.pinVault != null)
            ...lockRoutes(onUnlocked: _onUnlocked, onForgotPin: _onForgotPin),
        ],
        home: widget.homeTabRoot,
        ledger: widget.ledgerTabRoot,
        menu: widget.menuTabRoot,
        entry: widget.entryRoot,
      );

  @override
  void initState() {
    super.initState();
    widget.updateRequired?.addListener(_onUpdateRequired);
    _settings.addListener(_onSettingsChanged);
    _lock.addListener(_onLockChanged);
    final vault = widget.pinVault;
    if (vault != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _armLock(vault));
    }
  }

  @override
  void dispose() {
    widget.updateRequired?.removeListener(_onUpdateRequired);
    _settings.removeListener(_onSettingsChanged);
    _lock.removeListener(_onLockChanged);
    super.dispose();
  }

  /// Cold start (07 §5.6): with a PIN set the app opens on S15. With none
  /// there is nothing to unlock with, so the gate stays off rather than
  /// showing a screen that cannot be passed (07 §1 rule 6).
  Future<void> _armLock(PinVault vault) async {
    final status = await vault.status();
    if (!mounted) return;
    final armed = status is! PinNotSet;
    setState(() => _lockArmed = armed);
    if (armed) _lock.lock();
  }

  void _onSettingsChanged() => setState(() {});

  void _onLockChanged() {
    if (!_lock.locked || _lockShowing) return;
    _lockShowing = true;
    _router.push(LockPaths.lock);
  }

  /// Through: pop S15 and the app is exactly where it was, draft and focus
  /// included (ADR 2026-09-05 §7 — the lock never discards work).
  void _onUnlocked() {
    _lockShowing = false;
    _lock.unlock();
    if (_router.canPop()) _router.pop();
  }

  void _onForgotPin() {
    // ⚠️ SPEC: the reset is "OTP to the registered number **plus** biometric,
    // then set a new PIN" (07 §5.6, ADR 2026-09-05d §5). Only its first step
    // exists today (S0.2), and a door that opens on nothing is a dead end
    // (07 §1 rule 6) — so the forgot door lands on the OTP screen and the
    // reverification flow behind it is an open item, not invented here.
    _router.push(RkPaths.authPhone);
  }

  void _onUpdateRequired() {
    final gate = widget.updateRequired?.value;
    if (gate != null) _router.go(RkPaths.updateRequired, extra: gate);
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: widget.locale ?? _settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: rkLocalizationsDelegates,
      theme: rkTheme(Brightness.light),
      darkTheme: rkTheme(Brightness.dark),
      themeMode: _settings.appearance,
      routerConfig: _router,
      // S15.1 (07 §5.6 🔒): inside the app, so the cover has the theme and the
      // strings; above every route, so no screen can escape it.
      builder: (context, child) =>
          PrivacyCover(child: child ?? const SizedBox.shrink()),
    );

    Widget tree = RkAutoLock(
      lock: _lock,
      now: widget.now,
      idleTimeout: _settings.autoLockIdle,
      backgroundTimeout: _settings.autoLockBackground,
      draft: _draft,
      enabled: _lockArmed,
      child: app,
    );
    tree = DraftActivityScope(activity: _draft, child: tree);
    final vault = widget.pinVault;
    if (vault != null) {
      tree = LockScope(vault: vault, biometrics: _biometrics, child: tree);
    }
    tree = AppSettingsScope(settings: _settings, child: tree);

    final ledger = widget.ledger;
    return RkScope(
      db: widget.db,
      sync: widget.sync,
      auth: widget.auth,
      keys: widget.keys ?? FakeKeyStore(),
      now: widget.now,
      child: ledger == null ? tree : LedgerScope(ledger: ledger, child: tree),
    );
  }
}

/// The scope a tab is showing, as [AppSettings] stores it: `everything`, or
/// `book:<id>`. Kept here because [AppSettings] is shell state and must not
/// depend on a feature's types.
String? encodeScope(HomeScope? scope) => switch (scope) {
  null => null,
  HomeScope(isEverything: true) => 'everything',
  HomeScope(:final bookId?) => 'book:$bookId',
  _ => null,
};

/// Reads back what [encodeScope] wrote; null for anything unrecognised, so a
/// stored value from a later build never crashes an older one.
HomeScope? decodeScope(String value) {
  if (value == 'everything') return const HomeScope.everything();
  if (value.startsWith('book:') && value.length > 5) {
    return HomeScope.book(value.substring(5));
  }
  return null;
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
