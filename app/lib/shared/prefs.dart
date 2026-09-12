// Device-local preferences (13 §2.2 scope per tab · 07 §16 language,
// appearance, auto-lock). Not financial data and not secrets — but not
// nothing either: a stored scope names a book, so it is kept in the same
// protected item store as the rest of the device's state rather than in a
// plaintext file beside the encrypted database (CLAUDE.md rule 4, conservative
// reading).
//
// The seam is deliberately tiny — string in, string out by a stable key — so
// the app never grows a preferences plugin for four values and a widget test
// can hand the shell a memory store and then hand the *same* store to a second
// app instance to model a restart.
import 'dart:convert';
import 'dart:typed_data';

import 'seams/key_store.dart';

/// Keys the shell stores. The only place these strings live.
abstract final class RkPrefKeys {
  /// Chosen UI locale as a language tag (`en` · `pa` · `hi`); absent follows
  /// the device.
  static const locale = 'locale';

  /// Appearance (ADR 2026-09-05f §H12): `system` · `light` · `dark`.
  static const appearance = 'appearance';

  /// Foreground inactivity lock, in seconds (ADR 2026-09-05 §7, default 5 min).
  static const autoLockIdle = 'autolock.idle';

  /// Background timeout, in seconds (06 §4.5, default 2 min).
  static const autoLockBackground = 'autolock.background';

  /// The scope last used anywhere — what a tab with no scope of its own
  /// defaults to (13 §2.2 "defaults to last used").
  static const lastScope = 'scope.last';

  /// The scope a tab is showing; [tab] is the tab's path name.
  static String scopeOfTab(String tab) => 'scope.$tab';
}

/// A string-keyed store of small device-local values.
abstract class RkPrefs {
  /// The value under [key], or null.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing any previous value.
  Future<void> write(String key, String value);

  /// Removes [key]; a no-op when absent.
  Future<void> remove(String key);
}

/// In-memory preferences — widget tests and previews. Persistent only for as
/// long as the object lives, which is what makes it a usable restart fake.
class MemoryPrefs implements RkPrefs {
  /// What has been stored.
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Preferences kept in the platform [KeyStore], one item per key. No key
/// material passes through here — only the small values of [RkPrefKeys].
class KeyStorePrefs implements RkPrefs {
  /// Wraps [keys].
  const KeyStorePrefs(this.keys);

  /// The device's protected item store.
  final KeyStore keys;

  static String _id(String key) => 'rk.pref.$key';

  @override
  Future<String?> read(String key) async {
    final bytes = await keys.read(_id(key));
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<void> write(String key, String value) =>
      keys.write(_id(key), Uint8List.fromList(utf8.encode(value)));

  @override
  Future<void> remove(String key) => keys.delete(_id(key));
}
