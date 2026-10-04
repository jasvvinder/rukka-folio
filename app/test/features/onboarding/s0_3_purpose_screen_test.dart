// Widget tests for S0.3 Purpose (13 §3.2 row S0.3, 07 §3.1 step 3, 07 §3.1.1 —
// the purpose card branches the setup), as amended by ADR 2026-10-04c: **four**
// cards — Myself · My business · My family · Our trust — one column on a phone,
// a two-column grid from the `medium` breakpoint (600 logical px).
//
// The former `F1-07-16 all five cards render, trust full width beneath a 2x2
// grid` was superseded by ADR 2026-10-04c §1 and re-lands here as F1-04c-1
// (cards) and F1-04c-4 (layout).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart' show BookType;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart'
    show OnboardingPaths, onboardingFlow;
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/subscription_copy.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';
import 'onboarding_router_harness.dart';

/// The four cards' words per locale (ADR 2026-10-04c §1; 01 §2 purpose cards).
/// Every label is 01 §2's locked core term (🔒): *Myself* is Purpose card 1
/// (ਸਿਰਫ਼ ਮੈਂ / सिर्फ़ मैं), *My family* card 4, *Our trust* card 5, and *My
/// business* the ADR's own wording for card 2. The descriptions other than
/// trust's (01 §2's card 5 subtitle) have no 01 §2 row; they are the shipped
/// ARB values, asserted so a dropped key cannot fall back to English unnoticed.
const _cards = <String, List<(String, String)>>{
  'en': [
    ('Myself', 'Track your own money'),
    ('My business', 'Shop, practice, freelance work — one or more'),
    ('My family', 'Shared with the people at home'),
    ('Our trust', 'gurudwara, temple, society or registered trust'),
  ],
  'pa': [
    ('ਸਿਰਫ਼ ਮੈਂ', 'ਆਪਣੇ ਪੈਸਿਆਂ ਦਾ ਹਿਸਾਬ ਰੱਖੋ'),
    ('ਮੇਰਾ ਕਾਰੋਬਾਰ', 'ਦੁਕਾਨ, ਪ੍ਰੈਕਟਿਸ, ਫ੍ਰੀਲਾਂਸ ਕੰਮ — ਇੱਕ ਜਾਂ ਵੱਧ'),
    ('ਮੇਰਾ ਪਰਿਵਾਰ', 'ਘਰ ਦੇ ਸਭ ਨਾਲ ਸਾਂਝਾ'),
    ('ਸਾਡਾ ਟਰੱਸਟ', 'ਗੁਰਦੁਆਰਾ, ਮੰਦਰ, ਸਭਾ ਜਾਂ ਰਜਿਸਟਰਡ ਟਰੱਸਟ'),
  ],
  'hi': [
    ('सिर्फ़ मैं', 'अपने पैसों का हिसाब रखें'),
    ('मेरा कारोबार', 'दुकान, प्रैक्टिस, फ्रीलांस काम — एक या ज़्यादा'),
    ('मेरा परिवार', 'घर के सभी लोगों के साथ साझा'),
    ('हमारा ट्रस्ट', 'गुरुद्वारा, मंदिर, सभा या रजिस्टर्ड ट्रस्ट'),
  ],
};

Finder _card(OnboardingPurpose p) => find.byKey(purposeCardKey(p));

/// The cards' rectangles in reading order.
List<Rect> _rects(WidgetTester tester) => [
  for (final p in OnboardingPurpose.values) tester.getRect(_card(p)),
];

/// Myself · My business / My family · Our trust — two per row.
void _expectTwoColumns(WidgetTester tester, String reason) {
  final r = _rects(tester);
  expect(r[0].top, r[1].top, reason: 'row 1 shares a top — $reason');
  expect(r[0].left, lessThan(r[1].left), reason: 'Myself left — $reason');
  expect(r[2].top, r[3].top, reason: 'row 2 shares a top — $reason');
  expect(r[2].left, lessThan(r[3].left), reason: 'family left — $reason');
  expect(r[2].top, greaterThan(r[0].bottom), reason: 'row 2 below — $reason');
  expect(r[0].left, r[2].left, reason: 'columns align — $reason');
  expect(r[1].left, r[3].left, reason: 'columns align — $reason');
}

/// Four full-width cards, one under another.
void _expectOneColumn(WidgetTester tester, String reason) {
  final r = _rects(tester);
  for (var i = 1; i < r.length; i++) {
    expect(r[i].left, r[0].left, reason: 'same left edge — $reason');
    expect(r[i].width, r[0].width, reason: 'same full width — $reason');
    expect(r[i].top, greaterThan(r[i - 1].bottom), reason: 'stacked — $reason');
  }
}

/// Takes [purpose]'s card on the real S0.3 through the real router, then the
/// production hand-off into its branch — S0.5b's *Skip for now* calls
/// `afterSetPin` (S0.4, S0.8 and S0.5 are the shared steps every card takes,
/// so they are jumped) — and walks the branch with its defaults until its
/// opening host commits. Returns the type of every book the walk created,
/// read back from the ledger, so the assertion is on what was committed and
/// not on any flag the screen exposes.
Future<List<BookType>> _bookTypesCommittedBy(
  WidgetTester tester,
  OnboardingPurpose purpose,
) async {
  resetOnboardingFlow();
  final ledger = await openTestLedger();
  await ledger.bootstrapSolo();
  final before = (await ledger.mirror.bookIds()).toSet();
  final router = await pumpOnboardingRouter(
    tester,
    ledger,
    initialLocation: OnboardingPaths.purpose,
  );

  await tester.tap(find.byKey(purposeCardKey(purpose)));
  await tester.pumpAndSettle();
  expect(onboardingFlow.purpose, purpose, reason: purpose.name);
  expect(router.state.uri.path, OnboardingPaths.namePhoto);

  router.go(OnboardingPaths.recoverySheet);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Skip for now'));
  await tester.pumpAndSettle();

  final path = router.state.uri.path;
  switch (purpose) {
    case OnboardingPurpose.myself:
      expect(path, HomePaths.home, reason: 'Myself makes no further book');
    case OnboardingPurpose.businesses:
      expect(path, OnboardingPaths.business);
      await tester.enterText(find.byType(TextField).first, 'Sharma Traders');
      await tapContinue(tester); // S0.6a, *Just me* → S0.6b's host
      expect(router.state.uri.path, OnboardingPaths.businessOpening);
    case OnboardingPurpose.family:
      expect(path, OnboardingPaths.family);
      await tester.enterText(find.byType(TextField).first, 'Sharma Parivar');
      await tapContinue(tester); // S0.6d → S0.6e
      await tester.tap(find.text('Skip for now')); // S0.6e → S0.6f's host
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.familyAccounts);
    case OnboardingPurpose.trust:
      expect(path, OnboardingPaths.trust);
      await tester.enterText(find.byType(TextField).first, 'Guru Nanak Sabha');
      await tapContinue(tester); // S0.6g → S0.6h
      await tester.tap(find.text('Skip for now')); // S0.6h → S0.6i's host
      await tester.pumpAndSettle();
      expect(router.state.uri.path, OnboardingPaths.trustAccounts);
  }

  return [
    for (final id in await ledger.mirror.bookIds())
      if (!before.contains(id)) (await ledger.configOf(id))!.type,
  ];
}

void main() {
  group('S0.3 Purpose (07 §3.1 step 3, 07 §3.1.1, ADR 2026-10-04c)', () {
    testWidgets(
      'F1-04c-1 four cards render — Myself · My business · My family · Our '
      'trust — each with an icon, a label and a description, in EN/PA/HI',
      (tester) async {
        for (final locale in rkLocales) {
          await pumpRk(
            tester,
            const PurposeScreen(),
            locale: locale,
            viewport: rkPhone360,
          );
          final words = _cards[locale.languageCode]!;
          for (final (label, description) in words) {
            expect(find.text(label), findsOneWidget, reason: label);
            expect(find.text(description), findsOneWidget, reason: description);
          }
          // Exactly four cards, and each pairs an icon with its words so no
          // card is told apart by colour alone (07 §1 rule 3).
          expect(OnboardingPurpose.values, hasLength(4));
          for (final p in OnboardingPurpose.values) {
            expect(_card(p), findsOneWidget);
            expect(
              find.descendant(of: _card(p), matching: find.byType(Icon)),
              findsOneWidget,
              reason: '${p.name} carries an icon',
            );
          }
          expect(find.byType(Icon), findsNWidgets(4));
        }
        // The two retired cards are gone (ADR 2026-10-04c §1).
        await pumpRk(tester, const PurposeScreen(), viewport: rkPhone360);
        expect(find.text('My shop'), findsNothing);
        expect(find.text('My businesses'), findsNothing);
      },
    );

    testWidgets(
      'F1-04c-3 no shop purpose remains; My business hands over the business '
      'branch and commits a business book, never an organization',
      (tester) async {
        expect(OnboardingPurpose.values.map((p) => p.name), [
          'myself',
          'businesses',
          'family',
          'trust',
        ], reason: 'ADR 2026-10-04c §1 retires the shop purpose');

        OnboardingPurpose? picked;
        await pumpRk(
          tester,
          PurposeScreen(onSelected: (p) => picked = p),
          viewport: rkPhone360,
        );
        await tester.tap(find.text('My business'));
        await tester.pumpAndSettle();
        expect(picked, OnboardingPurpose.businesses);

        // 🔒 07 §3.1.1 (unchanged by the ADR): through the router, the My
        // business card's branch commits exactly one book, of type business.
        expect(
          await _bookTypesCommittedBy(tester, OnboardingPurpose.businesses),
          [BookType.business],
        );
      },
    );

    testWidgets(
      'F1-04c-4 one column below the medium breakpoint (both F1 phones and '
      '599 px), a two-column grid from 600 px and on every iPad viewport — '
      'no text cut or overflow at 1.0, 1.3x and 200% in EN/PA/HI',
      (tester) async {
        const narrow = [rkPhone360, rkPhone375, Size(599, 900)];
        // iPad mini portrait (744) is the narrowest iPad; 834 × 1194 and its
        // landscape are the suite's tablet viewports.
        const ipads = [Size(744, 1133), rkTabletPortrait, rkTabletLandscape];
        const edge = Size(600, 960);
        for (final locale in rkLocales) {
          for (final scale in [1.0, ...rkTextScales]) {
            for (final vp in [...narrow, edge, ...ipads]) {
              final reason = '${locale.languageCode} @ $scale on $vp';
              await pumpRk(
                tester,
                const PurposeScreen(),
                locale: locale,
                textScale: scale,
                viewport: vp,
              );
              expect(tester.takeException(), isNull, reason: reason);
              expectTextFits(tester, reason: reason);
              for (final p in OnboardingPurpose.values) {
                expect(_card(p), findsOneWidget, reason: reason);
              }
              if (narrow.contains(vp)) {
                _expectOneColumn(tester, reason);
              } else if (vp == edge && scale == 2.0) {
                // ⚠️ SPEC (open item): at exactly 600 px and 200 % a card is
                // 238 px wide, and in EN "My business" alone needs 257 px
                // (HI's trust line 268), so the grid would cut a word. There
                // the cards stack rather than cut (07 §1, 13 §4); PA's words
                // fit and keep the grid. No iPad is this narrow. Either way
                // it is one clean layout, never a cut word.
                final r = _rects(tester);
                if (r[0].top == r[1].top) {
                  _expectTwoColumns(tester, reason);
                } else {
                  _expectOneColumn(tester, reason);
                }
                if (locale.languageCode == 'en') {
                  _expectOneColumn(tester, '$reason — My business is 257 px');
                }
              } else {
                _expectTwoColumns(tester, reason);
              }
            }
          }
        }
      },
    );

    testWidgets(
      'F1-04c-5 the plan with catalogue id shop is named Business Lite in EN, '
      'and follows Family Lite\'s pattern in PA/HI (ADR 2026-10-04c §3)',
      (tester) async {
        const expected = {
          'en': 'Business Lite',
          'pa': 'ਬਿਜ਼ਨਸ ਲਾਈਟ',
          'hi': 'बिज़नेस लाइट',
        };
        for (final locale in rkLocales) {
          String? name;
          await pumpRk(
            tester,
            Builder(
              builder: (context) {
                name = RkPlan.shop.name(AppLocalizations.of(context));
                return Text(name!);
              },
            ),
            locale: locale,
            viewport: rkPhone360,
          );
          // The catalogue id is unchanged: billing and tokens carry `shop`.
          expect(RkPlan.shop.id, 'shop');
          expect(
            name,
            expected[locale.languageCode],
            reason: locale.toString(),
          );
          expect(find.text(expected[locale.languageCode]!), findsOneWidget);
        }
      },
    );

    testWidgets(
      'F1-07-16 selecting a card records the branch and hands it to the caller',
      (tester) async {
        OnboardingPurpose? picked;
        await pumpRk(
          tester,
          PurposeScreen(onSelected: (p) => picked = p),
          viewport: rkPhone360,
        );

        await tester.tap(find.text('My family'));
        await tester.pumpAndSettle();

        expect(picked, OnboardingPurpose.family);
      },
    );

    testWidgets(
      'F1-07-16 🔒 the trust card alone sets tenant.type = organization '
      '(07 §3.1.1) — each card walked through the router to its committed '
      'book',
      (tester) async {
        final committed = {
          for (final p in OnboardingPurpose.values)
            p: await _bookTypesCommittedBy(tester, p),
        };
        expect(committed, {
          OnboardingPurpose.myself: <BookType>[],
          OnboardingPurpose.businesses: [BookType.business],
          OnboardingPurpose.family: [BookType.family],
          OnboardingPurpose.trust: [BookType.organization],
        });
        for (final MapEntry(key: p, value: types) in committed.entries) {
          expect(
            types.contains(BookType.organization),
            p == OnboardingPurpose.trust,
            reason: p.name,
          );
        }
      },
    );
  });
}
