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

  /// `1` once this install's sign-up (13 §5 F1) or sign-in (F1b) chain has
  /// handed over to Home (ADR 2026-10-06b ruling 1); absent before. Not
  /// financial data — one bit about this install.
  static const onboarded = 'onboarded';

  /// The scope a tab is showing; [tab] is the tab's path name.
  static String scopeOfTab(String tab) => 'scope.$tab';

  /// Prefix of the per-book S0.6 *Finish* record (desk 172); see
  /// [openingBalancesOf]. Moved here from `OpeningSetupRecord.key` (desk 176)
  /// — the stored string is unchanged, so a record written before the move
  /// still reads.
  static const openingBalances = 'setup.openingBalances';

  /// `1` once an opening-balances step's *Finish* was pressed over [bookId]
  /// (S0.6, S0.6b, S0.6f or S0.6i — ADR 2026-10-07 ruling 3: the S0.7 row
  /// arrives ticked). Absent before.
  static String openingBalancesOf(String bookId) => '$openingBalances.$bookId';

  /// The purpose card chosen on S0.3 — an `OnboardingPurpose` name
  /// (`myself` · `businesses` · `family` · `trust`) — kept so the branch
  /// steps and the S0.7 checklist rows survive a cold start (ADR 2026-10-07
  /// ruling 3; ADR 2026-10-06b ruling 2).
  static const setupPurpose = 'setup.purpose';

  /// The one branch step S0.7 can bring back (ADR 2026-10-07 ruling 3): the
  /// family's or trust's invite step (S0.6e / S0.6h) when it was skipped. A
  /// small JSON object `{"purpose", "state", "book"}` — a purpose name, one of
  /// `open` · `done` · `notNeeded`, and the branch book's id once it exists.
  /// Absent when nothing was skipped. No name, no phone number, no figure.
  static const setupBranch = 'setup.branch';

  /// The branch books sign-up has made, in the order they were made (S0.6b,
  /// S0.6f, S0.6i's `createBook`): a small JSON list of
  /// `{"purpose", "book", "shared"}` — a purpose name, a book id, and for a
  /// business whether S0.6a said *Shared with others*. A cold start that lost
  /// the in-memory chain resumes over these books instead of asking the name
  /// again and making a second one (ADR 2026-10-06b ruling 2 🔒; 07 §3.1.1
  /// *never duplicated*). No name, no phone number, no figure.
  static const setupBranchBooks = 'setup.branchBooks';

  /// `1` once the printed recovery sheet has been scanned back (04 §7.4
  /// verified storage); absent before. The S0.7 row *Check your recovery
  /// sheet* stays open until then (ADR 2026-10-07 ruling 3).
  static const recoverySheetVerified = 'setup.recoverySheet.verified';
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
