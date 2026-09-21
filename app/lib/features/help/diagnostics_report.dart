// The S17.4 payload (13 §3.2 row S17.4 — "user-triggered, financial values
// scrubbed, shown before sending"; 07 §22 🔒).
//
// CLAUDE.md rule 4 is the whole design of this file: **no plaintext financial
// data** may reach a diagnostics report. The rule is kept by construction,
// not by redaction — the report is an **allow-list**. [DiagField] enumerates
// every line a report may carry, [buildDiagnosticsReport] is the only way to
// make one, and each value is normalised to a shape narrow enough that an
// amount, an account name or a party name cannot travel inside it:
//
//   * a [SyncStatus] is reduced to its *state word*. `WaitingFor` carries the
//     display name of the member whose entries are missing (05 §9) and that
//     name never leaves this function — `waiting_for_author` is what the
//     report says.
//   * the outbox is a **count of entries**, never a sum of them.
//   * an app or OS version that is not shaped like a version is dropped.
//   * a problem code that is not shaped like a code — lowercase identifier,
//     no long digit run that could be an amount in paise — is dropped. The
//     shape check is a backstop, not the guarantee: a [DiagnosticsDevice]
//     must hand over codes from the app's own fixed table and never a
//     formatted message. The seam says so, and the report caps the list at
//     [diagMaxCodes].
//
// Pure: no clock, no I/O, no localisation. The clock is passed in (a widget
// reads `RkScope.of(context).now()`), so the same inputs always build the
// same report and a test can assert on its exact bytes.
library;

import 'dart:ui' show Brightness, Locale;

import 'package:flutter/foundation.dart' show TargetPlatform;

import '../../shared/seams/sync_client.dart';

/// Every line a diagnostics report is allowed to carry, in the order the
/// report prints them.
///
/// This is the contract the `diag.field.*` / `diag.included` / `diag.excluded.*`
/// strings state to the reader on S17.4, and it is enumerated rather than
/// open so that adding a field is a visible code change with a string beside
/// it — not something that leaks in behind a map key.
enum DiagField {
  /// The app's own version, e.g. `0.1.0+1`.
  appVersion('app_version'),

  /// `android`, `ios`, or `other`.
  platform('platform'),

  /// The phone's software version, when the app can read it.
  osVersion('os_version'),

  /// `en`, `pa`, `hi`, or `other`.
  language('language'),

  /// The OS font scale, two decimals — the setting most layout reports turn
  /// on (09 suite F sweeps 1.3 and 2.0).
  textScale('text_scale'),

  /// `light` or `dark`.
  theme('theme'),

  /// One of the five 05 §9 state words, and nothing the state carries.
  syncState('sync_state'),

  /// How many entries are still waiting to sync — a count, never an amount.
  outboxDepth('outbox_depth'),

  /// The local database's schema number (03).
  schemaVersion('schema_version'),

  /// When the report was built, to the minute, in UTC.
  generatedAt('generated_at'),

  /// Problem codes the app recorded for itself, comma-separated.
  codes('codes');

  const DiagField(this.wire);

  /// The stable name this field prints under. Not localised: the report is
  /// read by whoever receives it, and the labels beside it on screen
  /// (`diag.field.*`) are what the *person* reads.
  final String wire;
}

/// What the app can learn about the device it is running on.
///
/// Every part is optional because the producer for it may be absent — see
/// [DiagnosticsDevice] in `diagnostics_seams.dart`. A field the app cannot
/// read is **omitted from the report**, never guessed and never filled with a
/// placeholder that would read like a fact.
final class DeviceFacts {
  /// Creates the facts.
  const DeviceFacts({
    this.appVersion,
    this.osVersion,
    this.problemCodes = const [],
  });

  /// The app's version string as the bundle spells it.
  final String? appVersion;

  /// The phone's software version.
  final String? osVersion;

  /// Codes the app recorded for itself. Filtered on the way in — see
  /// [buildDiagnosticsReport].
  final List<String> problemCodes;
}

/// A built report: an ordered, allow-listed set of fields, plus the exact
/// text that is shown and sent.
final class DiagnosticsReport {
  /// Wraps [values]. Only [buildDiagnosticsReport] should call this.
  const DiagnosticsReport(this.values);

  /// The fields that made it in, in [DiagField] order.
  final Map<DiagField, String> values;

  /// The payload, exactly as S17.4 shows it and exactly as it is sent — the
  /// screen has no second version of it (`diag.intro`).
  String get text =>
      values.entries.map((e) => '${e.key.wire}: ${e.value}').join('\n');
}

/// A version string: digits and dots, with an optional `+build`.
final _version = RegExp(r'^[0-9]{1,4}(\.[0-9]{1,4}){0,3}(\+[0-9]{1,6})?$');

/// An OS version: **digits and dots only**.
///
/// Deliberately as narrow as [_version] rather than "short free text with a
/// digit in it". A looser shape — say `Android 15` — admits any two words
/// with a number after them, and `Ramesh 15` is two words with a number
/// after them. The platform field already says `android` or `ios`, so the
/// number is the whole of what this field adds, and a producer that has
/// `Android 15` in hand passes `15`.
final _osVersion = RegExp(r'^[0-9]{1,4}(\.[0-9]{1,4}){0,3}$');

/// A problem code: a lowercase identifier the app chose for itself.
final _code = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// A run of four or more digits — the shape a paise amount has. A code with
/// one in it is refused rather than reasoned about.
final _longDigits = RegExp(r'[0-9]{4,}');

/// How many codes a report may carry.
const diagMaxCodes = 10;

/// Builds the one report S17.4 shows and sends.
///
/// The report is the **allow-list** of [DiagField] and nothing else. Values
/// that do not match the shape their field expects are dropped, so a field is
/// either a fact of the stated shape or absent.
DiagnosticsReport buildDiagnosticsReport({
  required DeviceFacts device,
  required SyncStatus sync,
  required Locale locale,
  required double textScale,
  required Brightness brightness,
  required TargetPlatform platform,
  required int schemaVersion,
  required DateTime now,
}) {
  final out = <DiagField, String>{};

  final app = device.appVersion?.trim();
  if (app != null && _version.hasMatch(app)) out[DiagField.appVersion] = app;

  out[DiagField.platform] = switch (platform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => 'other',
  };

  final os = device.osVersion?.trim();
  if (os != null && _osVersion.hasMatch(os)) out[DiagField.osVersion] = os;

  out[DiagField.language] = switch (locale.languageCode) {
    'en' => 'en',
    'pa' => 'pa',
    'hi' => 'hi',
    _ => 'other',
  };
  out[DiagField.textScale] = textScale.toStringAsFixed(2);
  out[DiagField.theme] = brightness == Brightness.dark ? 'dark' : 'light';

  // The state word only. `WaitingFor.name` stops here (05 §9,
  // `diag.excluded.people`).
  out[DiagField.syncState] = switch (sync) {
    Synced() => 'synced',
    SavedWillSync() => 'saved_will_sync',
    Offline() => 'offline',
    WaitingFor() => 'waiting_for_author',
    NeedsAttention() => 'needs_attention',
  };
  // A count of envelopes, never a sum of money.
  out[DiagField.outboxDepth] = switch (sync) {
    SavedWillSync(:final count) => count.toString(),
    _ => '0',
  };

  out[DiagField.schemaVersion] = schemaVersion.toString();
  out[DiagField.generatedAt] = _minuteUtc(now);

  final codes = device.problemCodes
      .map((c) => c.trim())
      .where((c) => _code.hasMatch(c) && !_longDigits.hasMatch(c))
      .take(diagMaxCodes)
      .toList(growable: false);
  if (codes.isNotEmpty) out[DiagField.codes] = codes.join(',');

  return DiagnosticsReport(out);
}

/// `2026-09-07T04:30Z` — UTC, to the minute. Deliberately coarse: a
/// to-the-second timestamp is a weak identifier, and the minute is all a
/// support reader needs.
String _minuteUtc(DateTime now) {
  final t = now.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}Z';
}
