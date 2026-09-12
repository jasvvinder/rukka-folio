// App-level state the shell owns and the screens only read: the chosen
// language (07 §16), the appearance mode (ADR 2026-09-05f §H12), the two
// auto-lock values (06 §4.5 background 2 min · ADR 2026-09-05 §7 idle 5 min)
// and the scope each tab is showing (13 §2.2 🔒 "scope persists per tab,
// defaults to last used").
//
// It is a [ChangeNotifier] over an [RkPrefs] store: every setter writes
// through, so a restart reads the same values back. S13 (features/settings)
// hands its choices here through `onLanguageChanged`/`onAppearanceChanged`
// and reads the live auto-lock values back out; the scope holder each tab
// hands down is seeded from [scopeOf] and persisted by [setScope].
import 'package:flutter/material.dart';

import 'prefs.dart';
import 'widgets/rk_tab_bar.dart';

/// The shell's own state, persisted through [RkPrefs].
class AppSettings extends ChangeNotifier {
  /// Reads and writes through [prefs]; call [load] once before use (the
  /// pre-load values are the defaults below, so a screen built first is
  /// never wrong, only early).
  AppSettings({required this.prefs});

  /// Foreground inactivity lock (ADR 2026-09-05 §7).
  static const defaultAutoLockIdle = Duration(minutes: 5);

  /// Background timeout (06 §4.5).
  static const defaultAutoLockBackground = Duration(minutes: 2);

  /// The locales S13 offers (01 §1.8: EN, PA, HI).
  static const supportedLanguageTags = ['en', 'pa', 'hi'];

  /// Where the values live.
  final RkPrefs prefs;

  Locale? _locale;
  ThemeMode _appearance = ThemeMode.system;
  Duration _idle = defaultAutoLockIdle;
  Duration _background = defaultAutoLockBackground;
  final Map<RkTab, String> _scopes = {};
  String? _lastScope;
  bool _loaded = false;

  /// The chosen locale, or null to follow the device.
  Locale? get locale => _locale;

  /// System · light · dark.
  ThemeMode get appearance => _appearance;

  /// Minutes of no touch in the foreground before the lock (default 5 min).
  Duration get autoLockIdle => _idle;

  /// Minutes in the background before the lock (default 2 min).
  Duration get autoLockBackground => _background;

  /// True once [load] has finished.
  bool get loaded => _loaded;

  /// Reads every stored value; notifies once at the end.
  Future<void> load() async {
    final tag = await prefs.read(RkPrefKeys.locale);
    if (tag != null && supportedLanguageTags.contains(tag)) {
      _locale = Locale(tag);
    }
    _appearance = _modeOf(await prefs.read(RkPrefKeys.appearance));
    _idle = _durationOf(
      await prefs.read(RkPrefKeys.autoLockIdle),
      defaultAutoLockIdle,
    );
    _background = _durationOf(
      await prefs.read(RkPrefKeys.autoLockBackground),
      defaultAutoLockBackground,
    );
    _lastScope = await prefs.read(RkPrefKeys.lastScope);
    for (final tab in RkTab.values) {
      final scope = await prefs.read(RkPrefKeys.scopeOfTab(tab.name));
      if (scope != null) _scopes[tab] = scope;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Sets the UI language; null follows the device again.
  Future<void> setLocale(Locale? locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    if (locale == null) {
      await prefs.remove(RkPrefKeys.locale);
    } else {
      await prefs.write(RkPrefKeys.locale, locale.languageCode);
    }
  }

  /// Sets system · light · dark.
  Future<void> setAppearance(ThemeMode mode) async {
    if (_appearance == mode) return;
    _appearance = mode;
    notifyListeners();
    await prefs.write(RkPrefKeys.appearance, mode.name);
  }

  /// Changes either auto-lock value. A non-positive duration is refused —
  /// "lock immediately" is not one of the offered values (06 §4.5).
  Future<void> setAutoLock({Duration? idle, Duration? background}) async {
    var changed = false;
    if (idle != null && idle > Duration.zero && idle != _idle) {
      _idle = idle;
      changed = true;
      await prefs.write(RkPrefKeys.autoLockIdle, '${idle.inSeconds}');
    }
    if (background != null &&
        background > Duration.zero &&
        background != _background) {
      _background = background;
      changed = true;
      await prefs.write(
        RkPrefKeys.autoLockBackground,
        '${background.inSeconds}',
      );
    }
    if (changed) notifyListeners();
  }

  /// The scope [tab] is showing: its own, else the last scope used anywhere
  /// (13 §2.2 🔒 "persists per tab, defaults to last used"), else null.
  String? scopeOf(RkTab tab) => _scopes[tab] ?? _lastScope;

  /// The scope stored for [tab] alone, ignoring the last-used fallback.
  String? storedScopeOf(RkTab tab) => _scopes[tab];

  /// Records the scope [tab] moved to. It also becomes the last-used scope,
  /// which is what a tab that has never been switched will default to.
  Future<void> setScope(RkTab tab, String? scope) async {
    if (scope == null) {
      if (_scopes.remove(tab) == null) return;
      notifyListeners();
      await prefs.remove(RkPrefKeys.scopeOfTab(tab.name));
      return;
    }
    if (_scopes[tab] == scope && _lastScope == scope) return;
    _scopes[tab] = scope;
    _lastScope = scope;
    notifyListeners();
    await prefs.write(RkPrefKeys.scopeOfTab(tab.name), scope);
    await prefs.write(RkPrefKeys.lastScope, scope);
  }

  static ThemeMode _modeOf(String? name) => switch (name) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static Duration _durationOf(String? seconds, Duration fallback) {
    final n = int.tryParse(seconds ?? '');
    return n == null || n <= 0 ? fallback : Duration(seconds: n);
  }
}

/// Hands [AppSettings] down the tree and rebuilds its dependents on every
/// change. Mounted above the router in `main.dart`; S13 reads it through
/// [maybeOf] so the screen itself stays state-free.
class AppSettingsScope extends InheritedNotifier<AppSettings> {
  /// Wraps [child] with [settings].
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  /// The nearest settings, or null when the shell mounted none.
  static AppSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()?.notifier;

  /// The nearest settings; throws when none is mounted.
  static AppSettings of(BuildContext context) {
    final settings = maybeOf(context);
    if (settings == null) {
      throw FlutterError('No AppSettingsScope above this widget');
    }
    return settings;
  }
}
