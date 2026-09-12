// F1 widget tests for 07 §3.1 steps 5 and 6 — S0.5 *Keeping your books safe*
// (F1-07-71, F1-07-72) and S0.5b the recovery sheet (F1-07-73).
//
// Sources: 07 §3.1 step 5 🔒 and step 6, 04 §7.0 / §7.4 🔒 / §7.6 🔒,
// ADR 2026-09-05c §8, ADR 2026-09-05f §G, 13 §3.2 rows S0.5 / S0.5b,
// 13 §4.3 states.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/devices_repository.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_5_books_safe_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_5b_recovery_sheet_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

const _locales = [Locale('en'), Locale('pa'), Locale('hi')];

Widget _scoped(DevicesRepository repo, Widget child) =>
    DevicesRepositoryScope(repository: repo, child: child);

/// Pumps on a tall surface so a scrolling screen is entirely built — a widget
/// a [ListView] has not reached is not in the tree at all.
Future<void> pumpTall(
  WidgetTester tester,
  Widget child, {
  Locale? locale,
}) async {
  tester.view.physicalSize = const Size(420, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpRk(tester, child, locale: locale);
}

/// Pumps [build] at 200% text scale on 360x800 in EN, PA and HI and fails on
/// any overflow (07 §1, design-system accessibility rules).
Future<void> expectNoOverflowInEveryLocale(
  WidgetTester tester,
  Widget Function() build,
) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  for (final locale in _locales) {
    await pumpRk(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: build(),
      ),
      locale: locale,
    );
    expect(tester.takeException(), isNull, reason: 'overflow in $locale');
  }
}

void main() {
  group('S0.5 Keeping your books safe (07 §3.1 step 5 🔒, 04 §7.6 🔒)', () {
    testWidgets(
      'F1-07-71 all three items are on the one screen: key sync stated (not '
      'asked), automatic backup on with its disclosure, sheet action below',
      (tester) async {
        final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
        await pumpTall(tester, _scoped(repo, const BooksSafeScreen()));
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BooksSafeScreen)),
        );

        // (a) stated, never asked: the line is there and it has no switch.
        expect(find.text(l10n.onboardingBooksSafeKeysyncTitle), findsOneWidget);
        expect(find.text(l10n.onboardingBooksSafeKeysyncApple), findsOneWidget);
        // ADR 2026-09-05f §G / ADR 2026-09-05c §8 — the one line that stops a
        // user believing an iCloud phone backup carries the books.
        expect(
          find.text(l10n.onboardingBooksSafeKeysyncPhoneBackup),
          findsOneWidget,
        );
        expect(
          find.byType(Switch),
          findsNWidgets(2),
          reason:
              'key sync is stated, not asked — only the two automatic '
              'backup artefacts have switches (07 §3.1 step 5 🔒)',
        );

        // (b) automatic backup, on, destination shown, disclosure prominent.
        expect(find.text(l10n.onboardingBooksSafeBackupTitle), findsOneWidget);
        expect(
          find.text(l10n.onboardingBooksSafeBackupDestinationUnset),
          findsOneWidget,
        );
        expect(
          find.text(l10n.onboardingBooksSafeBackupReadableDisclosure),
          findsOneWidget,
        );
        for (final s in tester.widgetList<Switch>(find.byType(Switch))) {
          expect(s.value, isTrue, reason: '04 §7.6 defaults are ON');
        }

        // (c) the sheet action sits below both other items.
        final sheet = find.text(l10n.onboardingBooksSafeSheetAction);
        expect(sheet, findsOneWidget);
        expect(
          tester.getTopLeft(sheet).dy,
          greaterThan(
            tester
                .getTopLeft(
                  find.text(l10n.onboardingBooksSafeBackupReadableTitle),
                )
                .dy,
          ),
          reason: '07 §3.1 step 5 🔒 puts the sheet action *below* (a) and (b)',
        );
      },
    );

    testWidgets('F1-07-71 the readable copy has a one-tap off that reaches the '
        'repository (04 §7.6 🔒)', (tester) async {
      final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
      await pumpTall(tester, _scoped(repo, const BooksSafeScreen()));

      // The second switch is the readable monthly export — the one the
      // disclosure belongs to.
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();

      expect(repo.current!.backup[BackupSetting.readableMonthly], isFalse);
      expect(
        repo.current!.backup[BackupSetting.encryptedVault],
        isTrue,
        reason:
            'one tap turns off one artefact, never a pair the user cannot '
            'see (04 §7.6 🔒)',
      );
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).last.value,
        isFalse,
      );
    });

    testWidgets('F1-07-71 a failed save shows the error and leaves the switch '
        'as it was (13 §4.3)', (tester) async {
      final repo = FakeDevicesRepository(initial: const DevicesSnapshot())
        ..failNext = const DevicesFailure('offline');
      await pumpTall(tester, _scoped(repo, const BooksSafeScreen()));
      final l10n = AppLocalizations.of(
        tester.element(find.byType(BooksSafeScreen)),
      );

      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();

      expect(
        find.text(l10n.onboardingBooksSafeBackupSaveFailed),
        findsOneWidget,
      );
      expect(repo.current!.backup[BackupSetting.readableMonthly], isTrue);
      expect(tester.widgetList<Switch>(find.byType(Switch)).last.value, isTrue);
    });

    testWidgets('F1-07-71 no overflow at 200% on 360x800 in EN, PA and HI', (
      tester,
    ) async {
      final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
      await expectNoOverflowInEveryLocale(
        tester,
        () => _scoped(repo, const BooksSafeScreen()),
      );
    });

    testWidgets(
      'F1-07-72 iCloud Keychain unavailable: the screen says so plainly and '
      'the sheet becomes the primary action (07 §3.1 step 5 🔒)',
      (tester) async {
        final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
        await pumpTall(
          tester,
          _scoped(
            repo,
            BooksSafeScreen(
              keySyncAvailable: () async => false,
              onContinue: () {},
              onSheet: () {},
              onSkip: () {},
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BooksSafeScreen)),
        );

        expect(
          find.text(l10n.onboardingBooksSafeKeysyncOffTitle),
          findsOneWidget,
        );
        expect(
          find.text(l10n.onboardingBooksSafeKeysyncOffBody),
          findsOneWidget,
        );
        expect(
          find.text(l10n.onboardingBooksSafeKeysyncTitle),
          findsNothing,
          reason: 'nothing may claim the key is in a Keychain that is off',
        );

        // The sheet is the primary action; Continue has stepped down to the
        // skip, so the screen is still not a dead end (07 §1 rule 6).
        expect(
          find.widgetWithText(
            FilledButton,
            l10n.onboardingBooksSafeSheetAction,
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            FilledButton,
            l10n.onboardingBooksSafeContinueLabel,
          ),
          findsNothing,
        );
        expect(
          find.widgetWithText(TextButton, l10n.onboardingBooksSafeSkip),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'F1-07-72 an availability check that throws takes the conservative '
      'reading — the unavailable copy, not a promise of recovery',
      (tester) async {
        final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
        await pumpTall(
          tester,
          _scoped(
            repo,
            BooksSafeScreen(
              keySyncAvailable: () async => throw StateError('no platform'),
            ),
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BooksSafeScreen)),
        );
        expect(
          find.text(l10n.onboardingBooksSafeKeysyncOffTitle),
          findsOneWidget,
        );
      },
    );

    testWidgets('F1-07-72 unavailable: no overflow at 200% on 360x800 in EN, '
        'PA and HI', (tester) async {
      final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
      await expectNoOverflowInEveryLocale(
        tester,
        () =>
            _scoped(repo, BooksSafeScreen(keySyncAvailable: () async => false)),
      );
    });
  });

  group('S0.5b Recovery sheet (07 §3.1 step 6, 04 §7.4 🔒)', () {
    testWidgets(
      'F1-07-73 generate → share/print → the nag persists until the printed '
      'sheet is scanned back',
      (tester) async {
        var generated = 0;
        var shared = 0;
        var scans = 0;
        final verified = <bool>[];
        await pumpTall(
          tester,
          RecoverySheetScreen(
            onGenerate: () async => generated++,
            onShare: () async => shared++,
            // The first scan does not match the printed sheet; the second does.
            onScanBack: () async => ++scans > 1,
            onVerifiedChanged: verified.add,
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(RecoverySheetScreen)),
        );

        // Intro: the one-screen explanation of why there is no reset.
        expect(find.text(l10n.onboardingRecoverySheetWhyTitle), findsOneWidget);
        expect(find.text(l10n.onboardingRecoverySheetWhyBody), findsOneWidget);
        expect(find.text(l10n.onboardingRecoverySheetShare), findsNothing);

        await tester.tap(find.text(l10n.onboardingRecoverySheetGenerate));
        await tester.pumpAndSettle();
        expect(generated, 1);

        // Ready: print/save, the risk line, and the nag.
        expect(find.text(l10n.onboardingRecoverySheetShare), findsOneWidget);
        expect(find.text(l10n.onboardingRecoverySheetRisk), findsOneWidget);
        expect(find.text(l10n.onboardingRecoverySheetNagTitle), findsOneWidget);
        expect(verified, [false]);

        // No key material is ever rendered (04 §7.4 is a printed document).
        await tester.tap(find.text(l10n.onboardingRecoverySheetShare));
        await tester.pumpAndSettle();
        expect(shared, 1);
        expect(
          find.text(l10n.onboardingRecoverySheetNagTitle),
          findsOneWidget,
          reason:
              'printing is not verifying — the nag survives the share '
              '(04 §7.4 🔒)',
        );

        // A scan that does not match keeps the nag and offers the scan again.
        await tester.tap(find.text(l10n.onboardingRecoverySheetScan));
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.onboardingRecoverySheetScanFailed),
          findsOneWidget,
        );
        expect(find.text(l10n.onboardingRecoverySheetNagTitle), findsOneWidget);
        expect(verified, [false]);

        // The matching scan is what stops it.
        await tester.tap(find.text(l10n.onboardingRecoverySheetScan));
        await tester.pumpAndSettle();
        expect(find.text(l10n.onboardingRecoverySheetVerified), findsOneWidget);
        expect(find.text(l10n.onboardingRecoverySheetNagTitle), findsNothing);
        expect(verified, [false, true]);
      },
    );

    testWidgets('F1-07-73 a failed generate changes nothing and keeps a retry '
        '(13 §4.3, 07 §1 rule 6)', (tester) async {
      final verified = <bool>[];
      var calls = 0;
      await pumpTall(
        tester,
        RecoverySheetScreen(
          onGenerate: () async {
            if (++calls == 1) throw StateError('no sheet');
          },
          onShare: () async {},
          onScanBack: () async => true,
          onVerifiedChanged: verified.add,
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(RecoverySheetScreen)),
      );

      await tester.tap(find.text(l10n.onboardingRecoverySheetGenerate));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onboardingRecoverySheetError), findsOneWidget);
      expect(find.text(l10n.onboardingRecoverySheetShare), findsNothing);
      expect(verified, isEmpty);

      await tester.tap(find.text(l10n.onboardingRecoverySheetRetry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onboardingRecoverySheetShare), findsOneWidget);
      expect(verified, [false]);
    });

    testWidgets('F1-07-73 the step is skippable and resumable (07 §3.1.1) — '
        'skip never claims the sheet was verified', (tester) async {
      var skipped = 0;
      final verified = <bool>[];
      await pumpTall(
        tester,
        RecoverySheetScreen(
          onGenerate: () async {},
          onSkip: () => skipped++,
          onVerifiedChanged: verified.add,
        ),
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(RecoverySheetScreen)),
      );
      await tester.tap(find.text(l10n.onboardingRecoverySheetSkip));
      await tester.pumpAndSettle();
      expect(skipped, 1);
      expect(verified, isEmpty);
    });

    testWidgets('F1-07-73 no overflow at 200% on 360x800 in EN, PA and HI', (
      tester,
    ) async {
      await expectNoOverflowInEveryLocale(
        tester,
        () => RecoverySheetScreen(
          onGenerate: () async {},
          onShare: () async {},
          onScanBack: () async => true,
        ),
      );
    });
  });
}
