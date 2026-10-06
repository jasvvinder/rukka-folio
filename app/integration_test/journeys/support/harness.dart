// The end-to-end journey harness (owner, 6 Oct 2026: "audit, review, test,
// match UI, then ask for testing" — phase 0). It drives the REAL app — the
// production composition root, `main()` → `bootstrap()` — on a device against
// the hosted dev server, and REPORTS what it finds; it never fixes anything.
//
// One journey per test file (13 §5 flows F1, F1b, F2). Each step:
//   1. waits for the expected screen by a stable finder (a screen widget type,
//      a widget Key, or a string from the EN ARB through AppLocalizations);
//   2. asserts that no blocking state is on screen (RkErrorState, the
//      RukkaFolioBlocked screen, a red ErrorWidget, any "Couldn't load");
//   3. takes a screenshot `<journey>__<nn>-<S-id>.png`;
//   4. acts.
// The first BLOCKING failure is recorded — {journey, step, expected screen,
// what was on screen, screenshot} — and the journey stops there. A DEFECT is
// a departure from the spec that does not stop the person (a step 13 §5 lists
// but the chain skipped, a seam drawn but wired to nothing, a book the card
// should have created, any framework error such as an overflow): it is
// recorded with a screenshot and the journey carries on, so later steps are
// still checked. Either one makes the verdict FAIL — PASS means no failure
// and no defect. The result is
// written after every step (so a crash still leaves it) to the app's cache
// dir `journeys/<journey>/result.json` beside the PNGs, and printed as one
// `JOURNEY_RESULT {...}` line; scripts/run_journeys.sh pulls both to
// app/build/journeys/ and builds report.json.
//
// Synthetic data only (CLAUDE.md rule 4): a fresh random dev demo number
// `+91 5…` per run (OTP 123456 on dev, RF_DEMO_PHONES), a fixed test PIN,
// made-up names, and token amounts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rukka_folio/features/lock/widgets/pin_pad.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/main.dart' as app;
import 'package:rukka_folio/shared/widgets/blocked_screen.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

/// The fixed test PIN (S0.8). Synthetic; never a real person's.
const journeyPin = '258036';

/// The dev OTP for `+91 5…` demo numbers (ADR 2026-09-25 §1).
const journeyOtp = '123456';

/// A fresh national number in the dev demo range: `5` + nine random digits.
/// Numbers already used on dev answer "existing", so one is never reused.
String freshDemoNumber() {
  final r = Random();
  return '5${List.generate(9, (_) => r.nextInt(10)).join()}';
}

/// One journey's run: its steps, its first failure, its warnings.
class Journey {
  Journey._(this.name, this.tester, this.binding, this._dir);

  /// Binds the integration-test binding. Call once at the top of `main()`.
  static IntegrationTestWidgetsFlutterBinding ensureBinding() =>
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Starts the real app and returns the journey that drives it.
  static Future<Journey> launch(
    String name,
    WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding,
  ) async {
    final cache = await getTemporaryDirectory();
    final dir = Directory('${cache.path}/journeys/$name');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final j = Journey._(name, tester, binding, dir);
    j._startedAt = DateTime.now();
    // Framework errors (overflow, assertion, an exception in a callback) are
    // DEFECTS — each fails the verdict — kept with the diagnostic's widget
    // location and a screenshot taken at the next pump; restored in [finish].
    j._previousOnError = FlutterError.onError;
    FlutterError.onError = j._recordFrameworkError;
    // The production composition root, exactly as a launch runs it. An error
    // out of main()'s own future is a framework defect too; an uncaught error
    // elsewhere in the zone fails the test, which run_journeys.sh checks
    // against the verdict through the exit code.
    unawaited(
      app.main().catchError((Object e, StackTrace st) {
        j._recordFrameworkError(
          FlutterErrorDetails(
            exception: e,
            stack: st,
            library: 'main()',
            context: ErrorDescription('while running the app'),
          ),
        );
      }),
    );
    return j;
  }

  /// The journey's name — also its screenshot folder.
  final String name;
  final WidgetTester tester;
  final IntegrationTestWidgetsFlutterBinding binding;
  final Directory _dir;

  /// Every string the finders use comes from the EN ARB.
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));

  final List<Map<String, Object?>> steps = [];
  final List<String> warnings = [];
  final List<String> notes = [];
  final Map<String, Object?> facts = {};

  /// Non-blocking departures from the spec; any one fails the verdict.
  final List<Map<String, Object?>> defects = [];
  Map<String, Object?>? failure;
  String _currentSid = '-';
  bool _errorShotPending = false;
  int _droppedErrors = 0;
  FlutterExceptionHandler? _previousOnError;
  DateTime _startedAt = DateTime.now();
  bool _surfaceConverted = false;
  int _n = 0;

  /// True once a step has failed; every later step is a no-op.
  bool get failed => failure != null;

  /// The verdict once [finish] has run: PASS only with no failure and no
  /// defect of any kind.
  bool get passed => failure == null && defects.isEmpty;

  // --- finders ---------------------------------------------------------------

  /// A visible text, exactly.
  Finder text(String s) => find.text(s, skipOffstage: true);

  /// A digit on the on-screen PIN keypad (S0.2 number + code, S0.8, S15).
  Finder padDigit(String d) =>
      find.descendant(of: find.byType(PinKeypad), matching: find.text(d));

  /// What blocks the journey, if anything is on screen; null when clear.
  String? blocking() {
    if (find.byType(RukkaFolioBlocked).evaluate().isNotEmpty) {
      return 'RukkaFolioBlocked (${en.appOpenFailedBody})';
    }
    if (find.byType(ErrorWidget).evaluate().isNotEmpty) {
      return 'ErrorWidget (red screen)';
    }
    if (find.byType(RkErrorState).evaluate().isNotEmpty) {
      return 'RkErrorState';
    }
    for (final s in const ["Couldn't load", 'Couldn’t load']) {
      if (find.textContaining(s).evaluate().isNotEmpty) {
        return '"$s…" on screen';
      }
    }
    return null;
  }

  /// The screen widgets and texts on screen now — the "what was there".
  Map<String, Object?> onScreen() {
    final screens = <String>{};
    for (final e
        in find
            .byWidgetPredicate(
              (w) => w.runtimeType.toString().endsWith('Screen'),
            )
            .evaluate()) {
      screens.add(e.widget.runtimeType.toString());
    }
    final texts = <String>[];
    for (final e in find.byType(Text).evaluate()) {
      final w = e.widget as Text;
      final s = (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
      if (s.isNotEmpty && !texts.contains(s)) texts.add(s);
      if (texts.length >= 40) break;
    }
    return {'screens': screens.toList(), 'texts': texts};
  }

  // --- waiting ---------------------------------------------------------------

  Future<void> settle([Duration d = const Duration(milliseconds: 250)]) async {
    await Future<void>.delayed(d);
    await tester.pump();
    await _shootPendingError();
  }

  /// Pumps until [f] is on screen, a blocking state appears, or [timeout].
  Future<bool> waitFor(
    Finder f, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await settle(const Duration(milliseconds: 200));
      if (f.evaluate().isNotEmpty) return true;
      if (blocking() != null) return false;
    }
    return f.evaluate().isNotEmpty;
  }

  /// Waits for the first of [options] to appear; returns its index or -1.
  Future<int> waitForAny(
    List<Finder> options, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await settle(const Duration(milliseconds: 200));
      for (var i = 0; i < options.length; i++) {
        if (options[i].evaluate().isNotEmpty) return i;
      }
      if (blocking() != null) return -1;
    }
    return -1;
  }

  // --- acting ----------------------------------------------------------------

  /// Taps the last visible match of [f] (the topmost route's copy).
  Future<void> tap(Finder f) async {
    final target = f.last;
    await tester.ensureVisible(target);
    await settle(const Duration(milliseconds: 150));
    await tester.tap(target, warnIfMissed: false);
    await settle();
  }

  /// Types [digits] on the on-screen PIN keypad.
  Future<void> typePad(String digits) async {
    for (final d in digits.split('')) {
      await tester.tap(padDigit(d).last, warnIfMissed: false);
      await settle(const Duration(milliseconds: 120));
    }
  }

  /// Enters [value] into the first TextField on screen.
  Future<void> enterFirstField(String value) async {
    final field = find.byType(TextField).first;
    await tester.ensureVisible(field);
    await tester.tap(field, warnIfMissed: false);
    await settle();
    await tester.enterText(field, value);
    await settle();
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(const Duration(milliseconds: 400));
  }

  // --- the step --------------------------------------------------------------

  /// One step: wait for [screen] (described by [expected]), check nothing
  /// blocks, screenshot, then [act]. Returns false — and stops the journey —
  /// on the first failure.
  Future<bool> step(
    String sid,
    String expected,
    Finder screen, {
    Future<void> Function()? act,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (failed) return false;
    _n++;
    _currentSid = sid;
    final nn = _n.toString().padLeft(2, '0');
    final shotName = '${name}__$nn-$sid';
    final t0 = DateTime.now();
    final found = await waitFor(screen, timeout: timeout);
    // A blocking state that settled in just after the screen appeared (a
    // skeleton turning into "Couldn't load") still fails the step.
    if (found) await settle(const Duration(milliseconds: 600));
    final block = blocking();
    final shot = await _screenshot(shotName);
    final record = <String, Object?>{
      'n': _n,
      'sid': sid,
      'expected': expected,
      'ms': DateTime.now().difference(t0).inMilliseconds,
      'screenshot': shot,
    };
    if (!found || block != null) {
      record['status'] = 'fail';
      steps.add(record);
      failure = {
        'journey': name,
        'step': _n,
        'sid': sid,
        'expected': expected,
        'reason':
            block ?? 'expected screen not shown within ${timeout.inSeconds}s',
        'on_screen': onScreen(),
        'screenshot': shot,
      };
      await _write();
      return false;
    }
    try {
      if (act != null) await act();
      record['status'] = 'ok';
      steps.add(record);
      await _write();
      return true;
    } on Object catch (e) {
      record['status'] = 'fail';
      steps.add(record);
      final after = await _screenshot('${shotName}_act');
      failure = {
        'journey': name,
        'step': _n,
        'sid': sid,
        'expected': expected,
        'reason': 'action failed: ${e.toString().split('\n').first}',
        'on_screen': onScreen(),
        'screenshot': after ?? shot,
      };
      await _write();
      return false;
    }
  }

  /// Records a fact about the run that is NOT a departure from the spec
  /// (e.g. a part of a step the harness cannot drive on a device). Anything
  /// the spec asks for and the app does not do is a [defect], never a note.
  void note(String s) => notes.add(s);

  /// Records a non-blocking departure from the spec at [sid], with a
  /// screenshot, and lets the journey carry on. Fails the verdict.
  Future<void> defect(
    String sid,
    String expected,
    String reason, {
    required String authority,
  }) async {
    if (failed) return;
    _n++;
    _currentSid = sid;
    final nn = _n.toString().padLeft(2, '0');
    final shot = await _screenshot('${name}__$nn-$sid-defect');
    defects.add({
      'kind': 'spec',
      'step': _n,
      'sid': sid,
      'expected': expected,
      'reason': reason,
      'authority': authority,
      'on_screen': onScreen(),
      'screenshot': shot,
    });
    await _write();
  }

  /// FlutterError.onError while the journey runs: a framework defect with
  /// the first line, the widget location the diagnostic names, a bounded
  /// excerpt of the full report, and a screenshot at the next pump.
  void _recordFrameworkError(FlutterErrorDetails details) {
    if (defects.where((d) => d['kind'] == 'framework').length >= 30) {
      _droppedErrors++;
      return;
    }
    final full = details.toString();
    final lines = full.split('\n');
    final location = RegExp(
      r'(package:rukka_folio/\S+?\.dart:\d+:\d+|lib/\S+?\.dart:\d+:\d+)',
    ).firstMatch(full)?.group(0);
    defects.add({
      'kind': 'framework',
      'step': _n,
      'sid': _currentSid,
      'reason': details.exceptionAsString().split('\n').first,
      'location': location,
      'detail': lines.take(40).join('\n'),
      'screenshot': null,
    });
    _errorShotPending = true;
  }

  Future<void> _shootPendingError() async {
    if (!_errorShotPending) return;
    _errorShotPending = false;
    final i = defects.lastIndexWhere((d) => d['kind'] == 'framework');
    if (i < 0) return;
    final nn = _n.toString().padLeft(2, '0');
    final shot = await _screenshot('${name}__$nn-$_currentSid-error$i');
    defects[i]['screenshot'] = shot;
    await _write();
  }

  /// Writes the result, restores the error handler and — when the journey
  /// failed or found any defect — fails the test so the exit code agrees
  /// with the report.
  Future<void> finish() async {
    await _shootPendingError();
    FlutterError.onError = _previousOnError;
    if (_droppedErrors > 0) {
      warnings.add('$_droppedErrors further framework errors not recorded');
    }
    await _write(done: true);
    if (failed) {
      fail(
        'JOURNEY $name FAILED at step ${failure!['step']} '
        '(${failure!['sid']}): ${failure!['reason']}'
        '${defects.isEmpty ? '' : ' (+${defects.length} defects)'}',
      );
    }
    if (defects.isNotEmpty) {
      fail(
        'JOURNEY $name FAILED with ${defects.length} defects: '
        '${defects.map((d) => '${d['sid']}: ${d['reason']}').join(' | ')}',
      );
    }
  }

  // --- output ----------------------------------------------------------------

  Future<String?> _screenshot(String file) async {
    try {
      if (Platform.isAndroid && !_surfaceConverted) {
        await binding.convertFlutterSurfaceToImage();
        _surfaceConverted = true;
      }
      await tester.pump();
      final bytes = await binding.takeScreenshot(file);
      // takeScreenshot also keeps the bytes for a driver; nothing reads them
      // under `flutter test`, so they are dropped to bound memory.
      (binding.reportData?['screenshots'] as List<dynamic>?)?.clear();
      await File('${_dir.path}/$file.png').writeAsBytes(bytes);
      return 'app/build/journeys/$name/$file.png';
    } on Object catch (e) {
      if (warnings.length < 50) warnings.add('screenshot $file: $e');
      return null;
    }
  }

  Map<String, Object?> result({bool done = false}) => {
    'journey': name,
    'verdict': failed
        ? 'FAIL'
        : !done
        ? 'RUNNING'
        : (defects.isEmpty ? 'PASS' : 'FAIL'),
    'completed': done && !failed,
    'started_at': _startedAt.toIso8601String(),
    'seconds': DateTime.now().difference(_startedAt).inSeconds,
    'facts': facts,
    'steps': steps,
    'failure': failure,
    'defects': defects,
    'notes': notes,
    'warnings': warnings,
    'debug_mode': kDebugMode,
  };

  Future<void> _write({bool done = false}) async {
    final r = result(done: done);
    final json = const JsonEncoder.withIndent('  ').convert(r);
    await File('${_dir.path}/result.json').writeAsString(json);
    if (done) {
      // One line the runner can read even when the files cannot be pulled.
      debugPrint('JOURNEY_RESULT ${jsonEncode(r)}', wrapWidth: 1 << 20);
    }
  }
}
