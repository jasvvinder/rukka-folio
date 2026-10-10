// F1-1008-1…3 — ADR 2026-10-08 (*joint fund* replaces *pool*; the 8 Oct
// ਪੰਜਾਬੀ / हिन्दी glossary rulings; unlock methods by platform; Android
// platform nouns), asserted through the production widgets in EN/PA/HI.
//
// The expected words are the ADR's own (its tables), typed here as literals —
// never read back from the ARB files, so a wrong ARB value fails the test
// instead of agreeing with it.
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/advances/screens/s5_advances_screen.dart';
import 'package:rukka_folio/features/books/screens/s9_books_screen.dart';
import 'package:rukka_folio/features/devices/devices_repository.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/lock/biometric_gate.dart';
import 'package:rukka_folio/features/lock/biometric_kind.dart';
import 'package:rukka_folio/features/lock/lock_scope.dart';
import 'package:rukka_folio/features/lock/screens/s15_lock_screen.dart';
import 'package:rukka_folio/features/onboarding/onboarding_flow.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_5_books_safe_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6d_family_name_screen.dart'
    show FamilyDraft;
import 'package:rukka_folio/features/onboarding/screens/s0_8_set_pin_screen.dart';
import 'package:rukka_folio/features/onboarding/widgets/family_opening_host.dart';
import 'package:core_ledger/core_ledger.dart' show LocalDate;

import '../features/advances/s5_advances_test.dart' show seedAdvances;
import '../features/lock/lock_harness.dart';
import '../shared/test_app.dart';

const _en = Locale('en');
const _pa = Locale('pa');
const _hi = Locale('hi');

/// Every string drawn on screen right now.
Iterable<String> _drawn(WidgetTester tester) sync* {
  for (final e in find.byType(RichText).evaluate()) {
    yield (e.widget as RichText).text.toPlainText();
  }
}

/// No drawn string carries a *pool* word (ADR 2026-10-08 §1).
void _expectNoPool(WidgetTester tester, String where) {
  for (final s in _drawn(tester)) {
    final lower = s.toLowerCase();
    expect(
      lower.contains('pool') || s.contains('पूल') || s.contains('ਪੂਲ'),
      isFalse,
      reason: '$where draws "$s" — *joint fund*, never *pool*',
    );
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

void _tall(WidgetTester tester, {double width = 420, double height = 3200}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Runs [body] with the app drawn as [platform], always restoring it — the
/// test binding fails any test that leaves the override set.
Future<void> _as(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  group('F1-1008-1 joint fund replaces pool (ADR 2026-10-08 §1)', () {
    final joint = {_en: 'Joint fund', _pa: 'ਸਾਂਝਾ ਫ਼ੰਡ', _hi: 'साझा फ़ंड'};
    final has = {
      _en: 'What the joint fund has',
      _pa: 'ਸਾਂਝੇ ਫ਼ੰਡ ਕੋਲ ਕੀ ਹੈ',
      _hi: 'साझे फ़ंड के पास क्या है',
    };

    for (final locale in [_en, _pa, _hi]) {
      testWidgets('F1-1008-1 S9 names a joint book *${joint[locale]}* '
          '(${locale.languageCode})', (tester) async {
        _tall(tester, height: 1200);
        await pumpRk(
          tester,
          const BooksScreen(
            books: [BookRow(id: 'b1', name: 'Sandhu family', type: 'joint')],
          ),
          locale: locale,
        );
        expect(find.text(joint[locale]!), findsOneWidget);
        _expectNoPool(tester, 'S9');
        await _unmount(tester);
      });

      testWidgets('F1-1008-1 S0.6f says *${has[locale]}* and nowhere *pool* '
          '(${locale.languageCode})', (tester) async {
        _tall(tester);
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = OnboardingFlow()
          ..setYourName('Amrit Kaur')
          ..setFamily(const FamilyDraft(name: 'Sharma Family'));
        await pumpRk(
          tester,
          FamilyOpeningHost(flow: flow, startDate: LocalDate(2026, 9, 7)),
          ledger: ledger,
          locale: locale,
        );
        await tester.pumpAndSettle();
        expect(find.text(has[locale]!), findsOneWidget);
        _expectNoPool(tester, 'S0.6f');
        await _unmount(tester);
      });
    }
  });

  group('F1-1008-2 the term-table rulings (ADR 2026-10-08 §2)', () {
    final position = {
      _en: ['Cash in hand', 'You will get', 'You will give', 'Advances out'],
      _pa: ['ਹੱਥ ਵਿੱਚ ਰੋਕੜ', 'ਤੁਸੀਂ ਲੈਣੇ ਹਨ', 'ਤੁਸੀਂ ਦੇਣੇ ਹਨ', 'ਐਡਵਾਂਸ ਦਿੱਤਾ'],
      _hi: ['हाथ में रोकड़', 'आपने लेने हैं', 'आपने देने हैं', 'एडवांस दिया'],
    };
    for (final locale in [_en, _pa, _hi]) {
      testWidgets(
        'F1-1008-2 S1 position card: cash in hand, you will get / give, '
        'advance out (${locale.languageCode})',
        (tester) async {
          _tall(tester, width: 400, height: 3000);
          final seed = await seedSoloLedger();
          await pumpRk(
            tester,
            const HomeScreen(),
            ledger: seed.ledger,
            locale: locale,
          );
          for (final term in position[locale]!) {
            expect(find.text(term), findsOneWidget, reason: term);
          }
          // The superseded forms are gone (the ADR's *was* column).
          for (final old in [
            'ਹੱਥ ਵਿੱਚ ਨਕਦੀ',
            'हाथ में नक़दी',
            'आपको मिलने हैं',
          ]) {
            expect(find.text(old), findsNothing, reason: old);
          }
          await _unmount(tester);
        },
      );
    }

    final advanceOut = {
      _en: 'Advance out',
      _pa: 'ਐਡਵਾਂਸ ਦਿੱਤਾ',
      _hi: 'एडवांस दिया',
    };
    for (final locale in [_en, _pa, _hi]) {
      testWidgets(
        'F1-1008-2 S5 heads the given section *${advanceOut[locale]}* '
        '(${locale.languageCode})',
        (tester) async {
          final f = await seedAdvances();
          await pumpRk(
            tester,
            AdvancesScreen(bookId: f.bookId),
            ledger: f.ledger,
            locale: locale,
            viewport: const Size(400, 1600),
          );
          expect(find.text(advanceOut[locale]!), findsOneWidget);
          await _unmount(tester);
        },
      );
    }

    testWidgets('F1-1008-2 HI *Save* is सुरक्षित करें on S0.6f', (
      tester,
    ) async {
      _tall(tester);
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo(firstBookName: 'Me');
      final flow = OnboardingFlow()
        ..setYourName('Amrit Kaur')
        ..setFamily(const FamilyDraft(name: 'Sharma Family'));
      await pumpRk(
        tester,
        FamilyOpeningHost(flow: flow, startDate: LocalDate(2026, 9, 7)),
        ledger: ledger,
        locale: _hi,
      );
      await tester.pumpAndSettle();
      expect(find.text('सुरक्षित करें'), findsOneWidget);
      expect(find.textContaining('सहेज'), findsNothing);
      expect(find.textContaining('सेव'), findsNothing);
      await _unmount(tester);
    });

    // The same 🔒 row's ਪੰਜਾਬੀ cell: *Save* is ਸੇਵ ਕਰੋ (unchanged), never
    // ਸੰਭਾਲੋ / ਸਾਂਭੋ (keep / look after). Every other PA Save string is held
    // by F1-PASAVE-1…3 (test/l10n/f1_pasave_test.dart).
    testWidgets('F1-1008-2 PA *Save* is ਸੇਵ ਕਰੋ on S0.6f', (tester) async {
      _tall(tester);
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo(firstBookName: 'Me');
      final flow = OnboardingFlow()
        ..setYourName('Amrit Kaur')
        ..setFamily(const FamilyDraft(name: 'Sharma Family'));
      await pumpRk(
        tester,
        FamilyOpeningHost(flow: flow, startDate: LocalDate(2026, 9, 7)),
        ledger: ledger,
        locale: _pa,
      );
      await tester.pumpAndSettle();
      expect(find.text('ਸੇਵ ਕਰੋ'), findsOneWidget);
      expect(find.textContaining('ਸੰਭਾਲ'), findsNothing);
      expect(find.textContaining('ਸਾਂਭ'), findsNothing);
      await _unmount(tester);
    });
  });

  group('F1-1008-3 the unlock method by platform (ADR 2026-10-08 §3–§4)', () {
    // (platform, modality) → the name on the S15.3 button, per locale.
    final cases = <(TargetPlatform, BiometricModality, Map<Locale, String>)>[
      (
        TargetPlatform.iOS,
        BiometricModality.face,
        {_en: 'Face ID', _pa: 'ਫੇਸ ਆਈਡੀ', _hi: 'फ़ेस आईडी'},
      ),
      (
        TargetPlatform.iOS,
        BiometricModality.fingerprint,
        {_en: 'Touch ID', _pa: 'ਟੱਚ ਆਈਡੀ', _hi: 'टच आईडी'},
      ),
      (
        TargetPlatform.android,
        BiometricModality.fingerprint,
        {_en: 'Fingerprint', _pa: 'ਫ਼ਿੰਗਰਪ੍ਰਿੰਟ', _hi: 'फ़िंगरप्रिंट'},
      ),
      (
        TargetPlatform.android,
        BiometricModality.face,
        {_en: 'Face unlock', _pa: 'ਫੇਸ ਅਨਲਾਕ', _hi: 'फ़ेस अनलॉक'},
      ),
    ];
    const allNames = [
      'Face ID',
      'Touch ID',
      'Fingerprint',
      'Face unlock',
      'ਫੇਸ ਆਈਡੀ',
      'ਟੱਚ ਆਈਡੀ',
      'ਫ਼ਿੰਗਰਪ੍ਰਿੰਟ',
      'ਫੇਸ ਅਨਲਾਕ',
      'फ़ेस आईडी',
      'टच आईडी',
      'फ़िंगरप्रिंट',
      'फ़ेस अनलॉक',
    ];

    for (final (platform, modality, names) in cases) {
      for (final locale in [_en, _pa, _hi]) {
        final name = names[locale]!;
        testWidgets(
          'F1-1008-3 S15.3 on ${platform.name} with a ${modality.name} '
          'names *$name* and no other method (${locale.languageCode})',
          (tester) async {
            await _as(platform, () async {
              sizeView(tester);
              final clock = TestClock();
              final vault = await makeVault(clock);
              await vault.setPin('135790');
              await pumpLock(
                tester,
                LockScreen(onUnlocked: () {}, onForgotPin: () {}),
                vault: vault,
                biometrics: FakeBiometricGate(
                  [BiometricOutcome.cancelled],
                  true,
                  modality,
                ),
                clock: clock,
                locale: locale,
              );
              expect(find.text(name), findsOneWidget);
              for (final other in allNames.where((n) => n != name)) {
                expect(find.text(other), findsNothing, reason: other);
              }
              await unmount(tester);
            });
          },
        );
      }
    }

    testWidgets('F1-1008-3 S15 on an Android fingerprint phone: the '
        'fingerprint glyph, *Touch the sensor*, then *Fingerprint not '
        'recognised* — never Face ID', (tester) async {
      await _as(TargetPlatform.android, () async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        final gate = FakeBiometricGate(
          [BiometricOutcome.failed],
          true,
          BiometricModality.fingerprint,
        );
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: gate,
          clock: clock,
        );
        expect(find.text('Fingerprint not recognised'), findsOneWidget);
        expect(find.byIcon(Icons.fingerprint), findsOneWidget);
        expect(find.textContaining('Face'), findsNothing);
        await unmount(tester);
      });
    });

    testWidgets('F1-1008-3 S15 waiting on an Android fingerprint: *Touch the '
        'sensor* under the glyph (c3 S15 Android frame)', (tester) async {
      await _as(TargetPlatform.android, () async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        final pending = Completer<BiometricOutcome>();
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: _PendingGate(pending, BiometricModality.fingerprint),
          clock: clock,
        );
        expect(find.text('Touch the sensor'), findsOneWidget);
        expect(find.textContaining('Face'), findsNothing);
        pending.complete(BiometricOutcome.cancelled);
        await tester.pumpAndSettle();
        await unmount(tester);
      });
    });

    testWidgets('F1-1008-3 a gate that cannot say which biometric names it '
        'neutrally — neither Face ID nor Fingerprint', (tester) async {
      await _as(TargetPlatform.android, () async {
        sizeView(tester);
        final clock = TestClock();
        final vault = await makeVault(clock);
        await vault.setPin('135790');
        await pumpLock(
          tester,
          LockScreen(onUnlocked: () {}, onForgotPin: () {}),
          vault: vault,
          biometrics: FakeBiometricGate([BiometricOutcome.cancelled]),
          clock: clock,
        );
        expect(find.text('Fingerprint or face'), findsOneWidget);
        for (final n in ['Face ID', 'Touch ID', 'Fingerprint', 'Face unlock']) {
          expect(find.text(n), findsNothing, reason: n);
        }
        await unmount(tester);
      });
    });

    final s08 = {
      (TargetPlatform.iOS, BiometricModality.face): (
        "You'll use Face ID most of the time.",
        'Face ID keeps this app closed to everyone else — if a new face is '
            'added to this phone, the app asks for your PIN',
      ),
      (TargetPlatform.iOS, BiometricModality.fingerprint): (
        "You'll use Touch ID most of the time.",
        'Touch ID keeps this app closed to everyone else — if a new '
            'fingerprint is added to this phone, the app asks for your PIN',
      ),
      (TargetPlatform.android, BiometricModality.fingerprint): (
        "You'll use your fingerprint most of the time.",
        'Fingerprint keeps this app closed to everyone else — if a new '
            'fingerprint is added to this phone, the app asks for your PIN',
      ),
      (TargetPlatform.android, BiometricModality.face): (
        "You'll use Face unlock most of the time.",
        'Face unlock keeps this app closed to everyone else — if a new face '
            'is added to this phone, the app asks for your PIN',
      ),
    };
    for (final MapEntry(key: (platform, modality), value: (lead, note))
        in s08.entries) {
      testWidgets('F1-1008-3 S0.8 on ${platform.name} with a ${modality.name}: '
          '"$lead"', (tester) async {
        await _as(platform, () async {
          _tall(tester, width: 400, height: 1400);
          final clock = TestClock();
          final vault = await makeVault(clock);
          await pumpRk(
            tester,
            LockScope(
              vault: vault,
              biometrics: FakeBiometricGate(
                const [BiometricOutcome.success],
                true,
                modality,
              ),
              child: const SetPinScreen(),
            ),
          );
          expect(find.textContaining(lead), findsOneWidget);
          expect(find.text(note), findsOneWidget);
          if (platform == TargetPlatform.android) {
            expect(find.textContaining('Face ID'), findsNothing);
          }
          await _unmount(tester);
        });
      });
    }

    final keysync = {
      _en: (
        'Your key is kept in Google Password Manager',
        'Google cannot read it.',
      ),
      _pa: (
        'ਤੁਹਾਡੀ ਕੁੰਜੀ Google Password Manager ਵਿੱਚ ਰੱਖੀ ਜਾਂਦੀ ਹੈ',
        'Google ਇਸਨੂੰ ਪੜ੍ਹ ਨਹੀਂ ਸਕਦਾ।',
      ),
      _hi: (
        'आपकी कुंजी Google Password Manager में रखी जाती है',
        'Google इसे पढ़ नहीं सकता।',
      ),
    };
    for (final locale in [_en, _pa, _hi]) {
      testWidgets(
        'F1-1008-3 S0.5 on Android names Google Password Manager and never '
        'iCloud Keychain or Apple (${locale.languageCode})',
        (tester) async {
          await _as(TargetPlatform.android, () async {
            _tall(tester, height: 3600);
            final repo = FakeDevicesRepository(
              initial: const DevicesSnapshot(),
            );
            await pumpRk(
              tester,
              DevicesRepositoryScope(
                repository: repo,
                child: const BooksSafeScreen(),
              ),
              locale: locale,
            );
            final (title, vendor) = keysync[locale]!;
            expect(find.text(title), findsOneWidget);
            expect(find.text(vendor), findsOneWidget);
            expect(find.textContaining('iCloud'), findsNothing);
            expect(find.textContaining('Keychain'), findsNothing);
            for (final s in _drawn(tester)) {
              // *Apple or Google* (a line naming both, as the readable
              // copy's disclosure does) is fine; Apple alone is the iPhone's.
              if (s.contains('Apple')) {
                expect(s, contains('Google'), reason: s);
              }
            }
            await _unmount(tester);
          });
        },
      );
    }

    testWidgets('F1-1008-3 S0.5 on iPhone keeps iCloud Keychain and Apple', (
      tester,
    ) async {
      await _as(TargetPlatform.iOS, () async {
        _tall(tester, height: 3600);
        final repo = FakeDevicesRepository(initial: const DevicesSnapshot());
        await pumpRk(
          tester,
          DevicesRepositoryScope(
            repository: repo,
            child: const BooksSafeScreen(),
          ),
        );
        expect(
          find.text('Your key is kept in iCloud Keychain'),
          findsOneWidget,
        );
        expect(find.text('Apple cannot read it.'), findsOneWidget);
        expect(find.textContaining('Google Password Manager'), findsNothing);
        await _unmount(tester);
      });
    });

    test(
      'F1-1008-3 the kind is the platform and the modality, never a guess',
      () {
        expect(
          biometricKindFor(TargetPlatform.iOS, BiometricModality.face),
          BiometricKind.faceId,
        );
        expect(
          biometricKindFor(TargetPlatform.iOS, BiometricModality.fingerprint),
          BiometricKind.touchId,
        );
        expect(
          biometricKindFor(
            TargetPlatform.android,
            BiometricModality.fingerprint,
          ),
          BiometricKind.fingerprint,
        );
        expect(
          biometricKindFor(TargetPlatform.android, BiometricModality.face),
          BiometricKind.faceUnlock,
        );
        expect(biometricKindFor(TargetPlatform.android, null), isNull);
        expect(biometricKindFor(TargetPlatform.iOS, null), isNull);
      },
    );
  });
}

/// A gate whose sheet stays up until [pending] completes — the *waiting*
/// state of c3 S15.
final class _PendingGate implements BiometricGate, BiometricModalitySource {
  _PendingGate(this.pending, this.modality);

  final Completer<BiometricOutcome> pending;
  final BiometricModality modality;

  @override
  Future<BiometricOutcome> authenticate({required String reason}) =>
      pending.future;

  @override
  Future<bool> qualifyingBiometricEnrolled() async => true;

  @override
  Future<BiometricModality?> enrolledModality() async => modality;
}
