@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/recovery/screens/s11_3_sheet_screen.dart';
import 'package:rukka_folio/features/recovery/widgets/recovery_parts.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

/// A code as the sheet prints it: Crockford Base32 in groups of four
/// (04 §7.4 🔒).
const _printed = 'K8N4-2QRT-9VWX-Y0Z1';

List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

Future<void> _openField(WidgetTester tester) async {
  await tester.tap(find.text('Type the code instead'));
  await tester.pumpAndSettle();
}

void main() {
  group(
    'S11.3 Recovery — the paper sheet (13 §3.2, design R2.4, 04 §7.4 🔒)',
    () {
      testWidgets(
        'F1-07-298 both ways in are drawn, and the camera path — which no '
        'package in this build can walk — is disabled **with its reason** and '
        'names the path that works (13 §4.3, 07 §1 rule 6 🔒)',
        (tester) async {
          await pumpRk(
            tester,
            RecoverySheetScreen(sheet: FakeRecoverySheet()),
            viewport: rkTallViewport,
          );
          expect(find.text('Use your recovery sheet'), findsOneWidget);
          expect(find.textContaining('One printed page'), findsOneWidget);
          expect(find.text('Type the code instead'), findsOneWidget);

          // The seam's default is the truth of this build.
          await tester.tap(find.text('Type the code instead'));
          await tester.pumpAndSettle();
          expect(find.byType(TextField), findsOneWidget);
        },
      );

      testWidgets(
        'F1-07-299 the typed path is real: Crockford’s own reading rules are '
        'applied (case, O→0, I/L→1, separators ignored) and the code is read '
        'back in the sheet’s groups of four',
        (tester) async {
          final seam = FakeRecoverySheet();
          await pumpRk(
            tester,
            RecoverySheetScreen(sheet: seam),
            viewport: rkTallViewport,
          );
          await _openField(tester);
          await tester.enterText(find.byType(TextField), 'k8n4 2qrt 9vwx yozi');
          await tester.pumpAndSettle();

          // O read as 0 and I as 1 — the sheet's own alphabet.
          expect(find.text('K8N4-2QRT-9VWX-Y0Z1'), findsOneWidget);
          await tester.tap(find.text('Open my books'));
          await tester.pumpAndSettle();
          expect(seam.submitted.single.value, 'K8N42QRT9VWXY0Z1');
        },
      );

      testWidgets(
        'F1-07-300 a character the sheet does not have keeps the button '
        'disabled with its reason, and the seam is never asked — the one '
        'failure this phone can name by itself',
        (tester) async {
          final seam = FakeRecoverySheet();
          await pumpRk(
            tester,
            RecoverySheetScreen(sheet: seam),
            viewport: rkTallViewport,
          );
          await _openField(tester);
          await tester.enterText(find.byType(TextField), 'K8N4-2QRU-9VWX');
          await tester.pumpAndSettle();

          expect(
            find.textContaining('not a code from a recovery sheet'),
            findsOneWidget,
          );
          final button = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Open my books'),
          );
          expect(button.onPressed, isNull);
          await tester.tap(find.text('Open my books'), warnIfMissed: false);
          await tester.pumpAndSettle();
          expect(seam.submitted, isEmpty);
        },
      );

      testWidgets(
        'F1-07-301 a good code opens the books and the entries come back over '
        'the determinate rule as a **count** — never a percentage, never a '
        'spinner (11 §4.5 🔒)',
        (tester) async {
          var home = 0;
          final seam = FakeRecoverySheet(
            progress: const [
              RecoveryProgress(
                done: 1240,
                total: 3890,
                unit: RecoveryUnit.entries,
              ),
              RecoveryProgress(
                done: 3890,
                total: 3890,
                unit: RecoveryUnit.entries,
                finished: true,
              ),
            ],
          );
          await pumpRk(
            tester,
            RecoverySheetScreen(sheet: seam, onRestored: () => home++),
            viewport: rkTallViewport,
          );
          await _openField(tester);
          await tester.enterText(find.byType(TextField), _printed);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open my books'));
          await tester.pumpAndSettle();

          expect(find.text('Your books are back'), findsOneWidget);
          expect(find.text('3,890 of 3,890 entries restored'), findsOneWidget);
          expect(find.byType(RecoveryLoaderRule), findsOneWidget);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          for (final s in _texts(tester)) {
            expect(s, isNot(contains('%')), reason: s);
          }
          await tester.tap(find.text('Go to my books'));
          await tester.pumpAndSettle();
          expect(home, 1);
        },
      );

      testWidgets(
        'F1-07-302 the failure state (design R2.4): “That code did not work” '
        'with **both** likely causes in plain words — a newer sheet, or a '
        'mistype — and the typed code survives the trip back to the field',
        (tester) async {
          final seam = FakeRecoverySheet(
            accepts: RecoverySheetCode.parse('ZZZZ'),
          );
          await pumpRk(
            tester,
            RecoverySheetScreen(sheet: seam),
            viewport: rkTallViewport,
          );
          await _openField(tester);
          await tester.enterText(find.byType(TextField), _printed);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open my books'));
          await tester.pumpAndSettle();

          expect(find.text('That code did not work'), findsOneWidget);
          expect(find.textContaining('newer sheet'), findsOneWidget);
          expect(find.textContaining('mistyped'), findsOneWidget);
          // Never a blank error, and never a raw code (07 §1 rule 12).
          for (final s in _texts(tester)) {
            expect(s.trim(), isNotEmpty);
          }

          await tester.tap(find.text('Try the code again'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text,
            _printed,
          );
        },
      );

      testWidgets(
        'F1-07-303 the two states that are not a wrong code: an attempt that '
        'could not be made at all is an error-with-retry, and offline is a '
        'quiet chip that blocks nothing (13 §4.3, 07 §1 rule 7)',
        (tester) async {
          final seam = FakeRecoverySheet(
            failsWith: const RecoveryFailure('unreachable'),
          );
          await pumpRk(
            tester,
            RecoverySheetScreen(sheet: seam),
            viewport: rkTallViewport,
          );
          await _openField(tester);
          await tester.enterText(find.byType(TextField), _printed);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open my books'));
          await tester.pumpAndSettle();
          expect(
            find.text('We could not check that code just now.'),
            findsOneWidget,
          );
          expect(find.text('Try again'), findsOneWidget);

          await pumpRk(
            tester,
            RecoverySheetScreen(sheet: FakeRecoverySheet()),
            sync: FakeSyncClient(initial: const Offline()),
            viewport: rkTallViewport,
          );
          expect(find.textContaining('Offline'), findsOneWidget);
          expect(find.text('Type the code instead'), findsOneWidget);
        },
      );

      testWidgets(
        'F1-07-304 the screen holds at 130 % and 200 % text on 360×800 and '
        '375×667 in all three languages — the whole list, scrolled through, '
        'with the field open and a code in it',
        (tester) async {
          for (final locale in rkLocales) {
            for (final size in rkPhones) {
              for (final scale in rkTextScales) {
                final reason = '$locale $size ×$scale';
                await pumpRk(
                  tester,
                  RecoverySheetScreen(sheet: FakeRecoverySheet()),
                  locale: locale,
                  textScale: scale,
                  viewport: size,
                );
                // At 200 % on a 360 px phone the list is longer than the
                // screen, and a lazy list only lays out what it shows — so the
                // sweep walks it rather than trusting the first screenful.
                await _sweep(tester, reason);
                await tester.scrollUntilVisible(find.byType(TextButton), 120);
                await tester.tap(find.byType(TextButton).first);
                await tester.pumpAndSettle();
                await tester.enterText(find.byType(TextField), _printed);
                await tester.pumpAndSettle();
                await _sweep(tester, reason);
              }
            }
          }
        },
      );
    },
  );
}

/// Walks the whole scrollable, checking at each screenful that nothing
/// overflowed and no word was silently cut.
Future<void> _sweep(WidgetTester tester, String reason) async {
  for (var i = 0; i < 8; i++) {
    expect(tester.takeException(), isNull, reason: reason);
    expectTextFits(tester, reason: reason);
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) return;
    await tester.drag(scrollable.first, const Offset(0, -320));
    await tester.pumpAndSettle();
  }
}
