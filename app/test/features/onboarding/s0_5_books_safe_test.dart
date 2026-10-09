// F1 widget tests for 07 §3.1 steps 5 and 6 — S0.5 *Keeping your books safe*
// (F1-07-71, F1-07-72) and S0.5b the recovery sheet (F1-07-73).
//
// Sources: 07 §3.1 step 5 🔒 and step 6, 04 §7.0 / §7.4 🔒 / §7.6 🔒,
// ADR 2026-09-05c §8, ADR 2026-09-05f §G, 13 §3.2 rows S0.5 / S0.5b,
// 13 §4.3 states.
@Tags(['F1'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/devices/devices_repository.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_5_books_safe_screen.dart';
import 'package:rukka_folio/features/onboarding/recovery_sheet/recovery_sheet_service.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_5b_recovery_sheet_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';
import 'onboarding_sweep.dart';

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

void main() {
  setUpAll(loadRkFonts);

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

    // HARN2 review, finding 3: production installs no DevicesRepositoryScope
    // (bootstrap.dart, main.dart) and nothing produces a vault file or a
    // monthly export, so the screen as onboarding_routes.dart builds it runs
    // on DevicesRepositoryScope's process-static fake and still says
    // *Automatic backup · On*. Every other F1-07-71 case injects its own fake
    // and so passes whatever production is wired to. This case pumps the
    // screen exactly as the route does, with no scope, and asks for the true
    // position (04 §7.6 🔒: "state the true position in the UI"; "none is
    // ever enabled silently").
    //
    // ⚠️ SPEC: skipped, not deleted — the honest state needs copy this lane
    // cannot add (the onboarding ARB parts are not in its directories) and a
    // real DevicesRepository plus vault/export producer installed at
    // bootstrap (features/devices, app bootstrap). Lane report M13-HARN2.
    testWidgets(
      'F1-07-71 with no devices repository installed (production today) the '
      'backup block never claims to be on and offers no switch that reaches '
      'nothing (04 §7.6 🔒)',
      (tester) async {
        await pumpTall(tester, const BooksSafeScreen());
        final l10n = AppLocalizations.of(
          tester.element(find.byType(BooksSafeScreen)),
        );
        expect(
          find.byType(Switch),
          findsNothing,
          reason: 'a switch with no repository behind it toggles nothing',
        );
        // Item (a) has its own "On" chip; item (b) must not add a second.
        final sameWord =
            l10n.onboardingBooksSafeBackupStateOn ==
            l10n.onboardingBooksSafeKeysyncStateOn;
        expect(
          find.text(l10n.onboardingBooksSafeBackupStateOn).evaluate().length,
          lessThanOrEqualTo(sameWord ? 1 : 0),
        );
      },
      skip: true, // HARN2 finding 3 — owner item; see the ⚠️ SPEC above.
    );

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

  // F1-07-73 over the re-skinned S0.5b (canvas c1/O5b; ADR 2026-10-06d
  // ruling 3). The live service's make/publish/check is F1-1006d-1…3
  // (f1_1006d_recovery_sheet_test.dart); this group pins 13 §3.2's row —
  // generate, print/save, verify by scanning back — on the screen itself.
  group('S0.5b Recovery sheet (07 §3.1 step 6, 04 §7.4 🔒)', () {
    testWidgets(
      'F1-07-73 generate → print/save → the nag persists until the printed '
      'sheet is scanned back',
      (tester) async {
        final service = _FakeSheetService();
        final verified = <bool>[];
        await pumpTall(
          tester,
          RecoverySheetScreen(
            service: service,
            onVerifiedChanged: verified.add,
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(RecoverySheetScreen)),
        );

        // Intro: why there is no reset, and the drawing of the page.
        expect(find.text(l10n.onboardingRecoverySheetWhyTitle), findsOneWidget);
        expect(find.byType(RecoverySheetPreview), findsOneWidget);
        await tester.tap(find.text(l10n.onboardingRecoverySheetPrint));
        await tester.pumpAndSettle();
        expect(service.made, 1);
        expect(service.opened, 1);
        expect(verified, [false], reason: 'made, not checked: the nag starts');

        // Printing is not verifying: reopened from S0.7 the screen checks.
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpTall(
          tester,
          RecoverySheetScreen(
            service: service,
            entry: RecoverySheetEntry.checkIfMade,
            onVerifiedChanged: verified.add,
          ),
        );
        expect(
          find.text(l10n.onboardingRecoverySheetCheckHeading),
          findsOneWidget,
        );
        service.next = RecoverySheetCheckResult.didNotOpen;
        await tester.tap(find.text(l10n.onboardingRecoverySheetCheckScan));
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.onboardingRecoverySheetCheckFailedTitle),
          findsOneWidget,
        );
        expect(verified, [false]);

        service.next = RecoverySheetCheckResult.opens;
        await tester.tap(find.text(l10n.onboardingRecoverySheetCheckScan));
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.onboardingRecoverySheetCheckVerified),
          findsOneWidget,
        );
        expect(verified, [false, true]);
      },
    );

    testWidgets('F1-07-73 no overflow at 200% on 360x800 in EN, PA and HI — '
        'make, failed and check', (tester) async {
      await expectNoOverflowInEveryLocale(
        tester,
        () => RecoverySheetScreen(service: _FakeSheetService()),
      );
      await expectNoOverflowInEveryLocale(
        tester,
        () => RecoverySheetScreen(onSkip: () {}),
      );
      await expectNoOverflowInEveryLocale(
        tester,
        () => RecoverySheetScreen(
          service: _FakeSheetService(),
          entry: RecoverySheetEntry.checkIfMade,
        ),
      );
    });
  });
}

/// A service that makes, opens and checks on command — the screen's view of
/// rung 3, with no crypto (that is F1-1006d's).
final class _FakeSheetService implements RecoverySheetService {
  int made = 0;
  int opened = 0;
  RecoverySheetCheckResult next = RecoverySheetCheckResult.opens;

  @override
  Future<RecoverySheetPrintout> make(Locale locale) async {
    made++;
    return RecoverySheetPrintout(Uint8List(4), (pdf, name) async {
      opened++;
      return true; // printed or saved
    }, version: made);
  }

  @override
  Future<bool> sheetOnServer() async => true;

  @override
  Future<RecoverySheetCheckResult> checkTyped(String typed) async => next;

  @override
  Future<RecoverySheetCheckResult> scan() async => next;
}
