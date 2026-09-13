// The entrypoint. Everything it needs is built by [bootstrap]; this file holds
// the app widget itself and the shell-state helpers that cannot live anywhere
// else. The composition root moved to `bootstrap.dart` on 13 Sep 2026.
import 'dart:async';

import 'package:data/data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'bootstrap.dart';
import 'features/auth/http_auth_client.dart';
import 'features/devices/pin_vault.dart';
import 'features/home/home_scope.dart';
import 'features/lock/lock_routes.dart';
import 'l10n/gen/app_localizations.dart';
import 'l10n/l10n.dart';
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

Future<void> main() => bootstrap();

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
    this.inboxTabRoot,
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

  /// The Inbox tab's root (S6); null leaves the tab's placeholder in place.
  /// Its `routes` are empty — S6.2's stepper is full-screen and covers the tab
  /// bar, so it mounts on the root navigator through [featureRoutes]
  /// (`inboxRoutes`), the same treatment S4.1 gets.
  final RkTabRoot? inboxTabRoot;

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
        inbox: widget.inboxTabRoot,
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
