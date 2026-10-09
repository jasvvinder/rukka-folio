// Phase 1 slice A (lane P1A) — desks 164, 172 and 171.
//
// F1-1006c-1  every purpose path makes the person's personal book at S0.4,
//             named after them, and reaches S0.6 after its branch steps.
// F1-1006c-2  never a second personal book: S0.4 answered twice, concurrent
//             makers, and S0.6's host all find the one book.
// F1-1006c-3  S0.6 *Finish* posts the typed Cash A/c figure (integer paise)
//             to the personal book, hands over to Home, and ticks the S0.7
//             *Opening balances* row — even at ₹0, where nothing posts.
// F1-1006c-4  (superseded by ADR 2026-10-07 §1 — S0.6 has no Skip; see
//             F1-1007-2) S0.6 *Skip for now* hands over with the row open.
// F1-1006c-5  (superseded by ADR 2026-10-06d §3 — the real maker is wired;
//             see F1-1006d-1) S0.5b with no sheet maker says why.
// F1-1006c-6  S0.6 strings resolve in EN/PA/HI and hold at 130 % / 200 % on
//             both phone floors.
// F1-1006c-14 (review 2) reopened after an entry moved an account with no
//             opening, S0.6 still asks its opening and Finish posts it; a
//             posted opening shows as the opening, never the running balance.
// F1-1006c-15 (review 6) the Finish record is per book: a business book in
//             scope keeps its row open and offers no S0.6 door.
// F1-1006c-16 (review 4) the field groups the figure as typed (₹ + Indian
//             grouping) and Finish still posts integer paise.
// F1-1006c-17 (review 5, 8) a ticked row is still a door — S0.6 reopens
//             from it — and its tick is a status colour, never `credit`.
//
// Every routed test drives the production `onboardingRoutes` and `homeRoot`
// over a real test ledger; the assertions read the ledger back, so a seam
// that silently made nothing fails here.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/home/home_paths.dart';
import 'package:rukka_folio/features/home/home_routes.dart' show homeRoot;
import 'package:rukka_folio/features/home/home_scope.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_cards.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart'
    show purposeCardKey;
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_settings.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/prefs.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';
import 'onboarding_router_harness.dart' show resetOnboardingFlow, tapContinue;

const _name = 'Amrit Kaur';

/// The app as `bootstrap` composes it for these steps: the onboarding routes,
/// the production Home tab root, and an [AppSettings] over [prefs].
Future<GoRouter> _pump(
  WidgetTester tester,
  LocalLedger ledger, {
  required String at,
  required MemoryPrefs prefs,
}) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = AppSettings(prefs: prefs);
  await settings.load();
  final router = buildRouter(
    featureRoutes: onboardingRoutes,
    home: homeRoot,
    initialLocation: at,
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    RukkaFolioApp(
      db: ledger.db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      keys: ledger.keys as FakeKeyStore,
      now: testNow,
      locale: const Locale('en'),
      router: router,
      ledger: ledger,
      settings: settings,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

String _where(GoRouter r) => r.state.uri.path;

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Every book of [type] the ledger holds, as (id, name).
Future<List<(String, String)>> _books(LocalLedger l, BookType type) async => [
  for (final b in await l.db.select(l.db.booksP).get())
    if (b.type == type.name) (b.id, b.name),
];

/// S0.4: type [name] and press Continue (the production `onSubmit`).
Future<void> _answerName(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField).first, name);
  await tapContinue(tester);
}

/// S0.5b's *Skip for now* → `afterSetPin`, then the branch with its defaults:
/// invites skipped (still skippable, ADR 2026-10-07 ruling 2) and every
/// opening-balances step saved at ₹0 (required, ruling 1), up to S0.6.
Future<void> _walkBranch(
  WidgetTester tester,
  GoRouter router,
  OnboardingPurpose purpose,
) async {
  router.go(OnboardingPaths.recoverySheet);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Skip for now'));
  await tester.pumpAndSettle();
  switch (purpose) {
    case OnboardingPurpose.myself:
      break;
    case OnboardingPurpose.businesses:
      await tester.enterText(find.byType(TextField).first, 'Kaur Traders');
      await tapContinue(tester); // S0.6a → S0.6b
      await tester.tap(find.text('Save and continue')); // S0.6b → S0.6c
      await tester.pumpAndSettle();
      await tester.tap(find.text('No, that’s all')); // S0.6c → S0.6
      await tester.pumpAndSettle();
    case OnboardingPurpose.family:
      await tester.enterText(find.byType(TextField).first, 'Kaur Parivar');
      await tapContinue(tester); // S0.6d → S0.6e
      await tester.tap(find.text('Skip for now')); // S0.6e → S0.6f
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save')); // S0.6f at ₹0 → S0.6
      await tester.pumpAndSettle();
    case OnboardingPurpose.trust:
      await tester.enterText(find.byType(TextField).first, 'Guru Nanak Sabha');
      await tapContinue(tester); // S0.6g → S0.6h
      await tester.tap(find.text('Skip for now')); // S0.6h → S0.6i
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save')); // S0.6i at ₹0 → S0.6
      await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    onboardingFlow.reset();
    resetOnboardingFlow();
  });
  tearDown(onboardingFlow.reset);

  group('F1-1006c-1 every path makes the personal book and reaches S0.6', () {
    const branchBook = {
      OnboardingPurpose.myself: null,
      OnboardingPurpose.businesses: BookType.business,
      OnboardingPurpose.family: BookType.family,
      OnboardingPurpose.trust: BookType.organization,
    };
    for (final purpose in OnboardingPurpose.values) {
      testWidgets('F1-1006c-1 ${purpose.name}: S0.4 makes "$_name"\'s personal '
          'book; the branch ends at S0.6 over it; Finish hands over', (
        tester,
      ) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo();
        expect(await _books(ledger, BookType.personal), isEmpty);
        final router = await _pump(
          tester,
          ledger,
          at: OnboardingPaths.purpose,
          prefs: MemoryPrefs(),
        );
        await tester.tap(find.byKey(purposeCardKey(purpose)));
        await tester.pumpAndSettle();
        expect(_where(router), OnboardingPaths.namePhoto);

        await _answerName(tester, _name);
        expect(_where(router), OnboardingPaths.setPin);
        // Made at S0.4, before any branch step (canvas 1: "One private book
        // is already made").
        final personal = await _books(ledger, BookType.personal);
        expect(personal, hasLength(1));
        expect(personal.single.$2, _name);

        await _walkBranch(tester, router, purpose);
        expect(_where(router), OnboardingPaths.openingBalances);
        expect(find.text('What do you have?'), findsOneWidget);
        // S0.6 is over the personal book: its seeded Cash A/c is the row.
        expect(find.text('Cash A/c'), findsOneWidget);
        expect(find.text('money in hand'), findsOneWidget);

        // ADR 2026-10-07 ruling 1: S0.6 has no Skip; ₹0 + Finish hands over.
        expect(find.text('Skip for now'), findsNothing);
        await tester.tap(find.text('Finish'));
        await tester.pumpAndSettle();
        expect(_where(router), HomePaths.home);
        expect(find.byType(HomeSetupChecklist), findsOneWidget);
        expect(find.text('Couldn’t load your position'), findsNothing);

        // One personal book, plus the branch's own book.
        expect(await _books(ledger, BookType.personal), hasLength(1));
        if (branchBook[purpose] case final type?) {
          expect(await _books(ledger, type), hasLength(1), reason: type.name);
        }
        await _unmount(tester);
      });
    }
  });

  group('F1-1006c-2 never a second personal book', () {
    testWidgets('F1-1006c-2 S0.4 answered twice (Back from S0.8, a new name) '
        'keeps the one book', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      final router = await _pump(
        tester,
        ledger,
        at: OnboardingPaths.namePhoto,
        prefs: MemoryPrefs(),
      );
      await _answerName(tester, _name);
      router.go(OnboardingPaths.namePhoto);
      await tester.pumpAndSettle();
      await _answerName(tester, 'Amrit');
      router.go(OnboardingPaths.openingBalances);
      await tester.pumpAndSettle();
      final personal = await _books(ledger, BookType.personal);
      expect(personal, hasLength(1));
      expect(personal.single.$2, _name, reason: 'the first answer made it');
      await _unmount(tester);
    });

    test('F1-1006c-2 concurrent makers share one creation', () async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      final start = ledger.today();
      final ids = await Future.wait([
        ensurePersonalBook(ledger, name: _name, startDate: start),
        ensurePersonalBook(ledger, name: 'Other', startDate: start),
      ]);
      expect(ids.toSet(), hasLength(1));
      final again = await ensurePersonalBook(
        ledger,
        name: 'Third',
        startDate: start,
      );
      expect(again, ids.first);
      expect(await _books(ledger, BookType.personal), hasLength(1));
    });

    testWidgets('F1-1006c-2 S0.6 reached with no book (S0.4 lost to a cold '
        'start) makes exactly one, named from the flow', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      onboardingFlow.setYourName(_name);
      await _pump(
        tester,
        ledger,
        at: OnboardingPaths.openingBalances,
        prefs: MemoryPrefs(),
      );
      expect(find.text('What do you have?'), findsOneWidget);
      final personal = await _books(ledger, BookType.personal);
      expect(personal, hasLength(1));
      expect(personal.single.$2, _name);
      await _unmount(tester);
    });
  });

  group('F1-1006c-3 Finish posts, hands over and ticks the row', () {
    testWidgets('F1-1006c-3 ₹1,500 typed into Cash A/c posts 150000 paise to '
        'the personal book; Home shows the row ticked', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      onboardingFlow.setYourName(_name);
      final prefs = MemoryPrefs();
      final router = await _pump(
        tester,
        ledger,
        at: OnboardingPaths.openingBalances,
        prefs: prefs,
      );
      final bookId = (await _books(ledger, BookType.personal)).single.$1;

      await tester.enterText(find.byType(TextField).first, '1500');
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(_where(router), HomePaths.home);
      expect(prefs.values[RkPrefKeys.onboarded], '1');
      expect(prefs.values[OpeningSetupRecord.keyFor(bookId)], '1');
      final accounts = (await tester.runAsync(
        () => ledger.watchAccounts(bookId).first,
      ))!;
      final cash = accounts.firstWhere(
        (a) => a.account.accountClass == AccountClass.money,
      );
      expect(cash.balancePaise, 150000);
      // Desk 172: Finish lands on the O8 checklist with the row ticked,
      // whatever was typed. An opening is setup, not the first entry
      // (HomeSnapshot.firstRun; P1A review, finding 1).
      expect(find.byType(HomeSetupChecklist), findsOneWidget);
      expect(find.byType(HomePositionCard), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Opening balances')).style?.decoration,
        TextDecoration.lineThrough,
      );
      expect(
        tester
            .widget<Text>(find.text('Write your first entry'))
            .style
            ?.decoration,
        isNot(TextDecoration.lineThrough),
      );
      await _unmount(tester);
    });

    testWidgets('F1-1006c-3 Finish at ₹0 posts nothing yet still ticks the '
        'row (desk 172)', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      onboardingFlow.setYourName(_name);
      final prefs = MemoryPrefs();
      final router = await _pump(
        tester,
        ledger,
        at: OnboardingPaths.openingBalances,
        prefs: prefs,
      );
      final bookId = (await _books(ledger, BookType.personal)).single.$1;
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(_where(router), HomePaths.home);
      final accounts = (await tester.runAsync(
        () => ledger.watchAccounts(bookId).first,
      ))!;
      expect(accounts.every((a) => a.balancePaise == 0), isTrue);
      expect(prefs.values[OpeningSetupRecord.keyFor(bookId)], '1');
      // The row is ticked: struck through beside a filled tick.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Opening balances')).style?.decoration,
        TextDecoration.lineThrough,
      );
      await _unmount(tester);
    });
  });

  // ADR 2026-10-07 §1 removed S0.6's *Skip for now*: the body (git history)
  // drove a button that no longer exists. What it also proved — the row opens
  // S0.6 alone on an onboarded install, Back returns Home, Finish ticks it —
  // re-lands in F1-1007-2 (f1_1007_required_steps_test.dart).
  group('F1-1006c-4 Skip leaves the row open as the way back', () {
    test(
      'F1-1006c-4 Skip → Home with the row open; the row opens S0.6 '
      'alone; Back returns Home; Finish there ticks it',
      () {},
      skip: 'superseded by ADR 2026-10-07 §1; re-lands at M13',
    );
  });

  // F1-1006c-5 is superseded (ADR 2026-09-05i §4): it pinned S0.5b with no
  // sheet maker as the *production* wiring (desk 171). RUNG3B wires the real
  // maker (ADR 2026-10-06d ruling 3), so the copy it asserted ("can't make
  // the sheet yet … once an update adds it") no longer describes production.
  // What it also proved — with no maker the reason sits under the sleeping
  // button and *Skip for now* carries on — re-lands in F1-1006d-1
  // (f1_1006d_recovery_sheet_test.dart).
  group('F1-1006c-5 S0.5b disabled with its reason (desk 171)', () {
    test(
      'F1-1006c-5 no sheet maker: the reason sits under the disabled Make '
      'the sheet, and Skip for now carries on',
      () {},
      skip: 'superseded by ADR 2026-10-06d §3; re-lands at M13 as F1-1006d-1',
    );
  });
  group('F1-1006c-6 S0.6 in EN/PA/HI at large text', () {
    const rows = [
      FirstRunRow(
        accountId: 'cash',
        name: 'Cash A/c',
        group: OpeningGroup.have,
        isCash: true,
      ),
      FirstRunRow(
        accountId: 'p1',
        name: 'Sunil Dairy',
        group: OpeningGroup.youOwe,
        postedPaise: -137000,
      ),
    ];
    final expected = {
      'en': ('What do you have?', 'Finish', 'Skip for now'),
      'pa': ('ਤੁਹਾਡੇ ਕੋਲ ਕੀ ਹੈ?', 'ਪੂਰਾ ਕਰੋ', 'ਹੁਣੇ ਲਈ ਛੱਡੋ'),
      'hi': ('आपके पास क्या है?', 'पूरा करें', 'अभी के लिए छोड़ें'),
    };
    for (final locale in rkLocales) {
      testWidgets('F1-1006c-6 strings resolve in ${locale.languageCode}', (
        tester,
      ) async {
        await pumpRk(
          tester,
          OpeningBalancesScreen(
            rows: rows,
            asOn: LocalDate(2026, 9, 7),
            onFinish: (_) {},
            onAddAccount: () {},
            onBack: () {},
          ),
          locale: locale,
          viewport: rkPhone360,
        );
        final (title, finish, skip) = expected[locale.languageCode]!;
        expect(find.text(title), findsOneWidget);
        expect(find.text(finish), findsOneWidget);
        // ADR 2026-10-07 ruling 1 (F1-1007-2): S0.6 is required — the
        // *Skip for now* this test once found is gone in every language.
        expect(find.text(skip), findsNothing);
        // The posted party figure is shown, not asked again; it is magnitude
        // under its *who you owe* heading (07 §1 rule 3).
        expect(find.text('₹1,370'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      });
      for (final size in rkPhones) {
        for (final scale in rkTextScales) {
          testWidgets('F1-1006c-6 S0.6 holds in ${locale.languageCode} at '
              '${(scale * 100).round()}% on ${size.width.toInt()}x'
              '${size.height.toInt()}', (tester) async {
            await pumpRk(
              tester,
              OpeningBalancesScreen(
                rows: rows,
                asOn: LocalDate(2026, 9, 7),
                onFinish: (_) {},
                onAddAccount: () {},
                onBack: () {},
              ),
              locale: locale,
              textScale: scale,
              viewport: size,
            );
            expect(tester.takeException(), isNull);
            expectTextFits(tester, reason: 'S0.6');
          });
        }
      }
    }
  });

  test('F1-1006c-1 the chain routes every branch end to S0.6', () {
    for (final p in [null, OnboardingPurpose.myself]) {
      final flow = OnboardingFlow();
      if (p != null) flow.setPurpose(p);
      expect(afterSetPin(flow), OnboardingPaths.openingBalances);
    }
    expect(
      afterBusinessOpening(
        OnboardingFlow()..setPurpose(OnboardingPurpose.family),
      ),
      OnboardingPaths.openingBalances,
    );
  });

  group('F1-1006c-14 S0.6 shows openings, never running balances', () {
    testWidgets('F1-1006c-14 an entry moved Cash A/c before any opening: '
        'reopened, S0.6 still asks Cash A/c its opening and Finish posts it', (
      tester,
    ) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo(firstBookName: _name);
      final bookId = (await _books(ledger, BookType.personal)).single.$1;
      final cash = (await ledger.chartOf(bookId))
          .byClass(AccountClass.money)
          .first;
      final tea = await ledger.addAccount(
        bookId,
        name: 'Tea',
        accountClass: AccountClass.categoryExpense,
      );
      await ledger.moneyOut(
        bookId: bookId,
        from: cash.id,
        forWhat: tea.id,
        paise: 20000,
        date: ledger.today(),
      );
      final prefs = MemoryPrefs()..values[RkPrefKeys.onboarded] = '1';
      final router = await _pump(
        tester,
        ledger,
        at: OnboardingPaths.openingBalances,
        prefs: prefs,
      );

      // Running balance −₹200 is not an opening: the row takes a figure,
      // and the spend is not shown as something the person has.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('₹200'), findsNothing);
      await tester.enterText(find.byType(TextField), '1000');
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      final balances = (await tester.runAsync(
        () => ledger.watchAccounts(bookId).first,
      ))!;
      // 100000 opening − 20000 spent, integer paise.
      expect(
        balances.firstWhere((a) => a.account.id == cash.id).balancePaise,
        80000,
      );
      expect(prefs.values[OpeningSetupRecord.keyFor(bookId)], '1');

      // Reopened once more (the checklist has gone — openings in and an
      // ordinary entry made — so by its route): the row now shows its
      // opening, ₹1,000 — not the running ₹800 — read-only.
      router.go(OnboardingPaths.openingBalances);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('₹1,000'), findsOneWidget);
      expect(find.text('₹800'), findsNothing);
      await _unmount(tester);
    });
  });

  group('F1-1006c-15 the Finish record is per book', () {
    testWidgets('F1-1006c-15 S0.6 finished over the personal book leaves a '
        'business book\'s row open, with no door to S0.6', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo(firstBookName: _name);
      final personal = (await _books(ledger, BookType.personal)).single.$1;
      final shop = await ledger.createBook(
        name: 'Kaur Traders',
        type: BookType.business,
        startDate: ledger.today(),
      );
      final prefs = MemoryPrefs()
        ..values[OpeningSetupRecord.keyFor(personal)] = '1';
      final settings = AppSettings(prefs: prefs);
      await settings.load();
      Future<List<SetupStep>> open(String bookId) async {
        final steps = <SetupStep>[];
        await pumpRk(
          tester,
          AppSettingsScope(
            settings: settings,
            child: HomeScreen(
              scopeController: HomeScopeController()
                ..select(HomeScope.book(bookId)),
              onSetupStep: steps.add,
            ),
          ),
          ledger: ledger,
          viewport: const Size(420, 3200),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Opening balances'), warnIfMissed: false);
        await tester.pumpAndSettle();
        return steps;
      }

      // The personal book: ticked by its own record, and a door to S0.6.
      expect(await open(personal), [SetupStep.openingBalances]);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await _unmount(tester);

      // The business book: nothing recorded for it, nothing posted — the row
      // is open, and S0.6 (which fills the personal book) is not its door.
      expect(await open(shop), isEmpty);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      final row = find.ancestor(
        of: find.text('Opening balances'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
        findsNothing,
      );
      await _unmount(tester);
    });
  });

  group('F1-1006c-16 the S0.6 field groups as typed', () {
    test('F1-1006c-16 IndianGroupingFormatter.group', () {
      expect(IndianGroupingFormatter.group(''), '');
      expect(IndianGroupingFormatter.group('500'), '500');
      expect(IndianGroupingFormatter.group('14500'), '14,500');
      expect(IndianGroupingFormatter.group('1500000'), '15,00,000');
      expect(IndianGroupingFormatter.group('15,00,000.5'), '15,00,000.5');
      expect(IndianGroupingFormatter.group('1234.567'), '1,234.56');
      expect(IndianGroupingFormatter.group('00120'), '120');
      expect(IndianGroupingFormatter.group('0.5'), '0.5');
      expect(IndianGroupingFormatter.group('1.2.3'), '1.23');
      expect(IndianGroupingFormatter.group('₹ 12a4'), '124');
      expect(IndianGroupingFormatter.withSign(''), '');
      expect(IndianGroupingFormatter.withSign('₹14500'), '₹14,500');
    });

    testWidgets('F1-1006c-16 typed 1500000 reads ₹15,00,000 and posts '
        '150000000 paise', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      onboardingFlow.setYourName(_name);
      await _pump(
        tester,
        ledger,
        at: OnboardingPaths.openingBalances,
        prefs: MemoryPrefs(),
      );
      final bookId = (await _books(ledger, BookType.personal)).single.$1;
      await tester.enterText(find.byType(TextField), '1500000');
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      // ₹ tight against the digits (canvas 11 O6a `₹14,500`).
      expect(field.controller!.text, '₹15,00,000');
      expect(field.decoration!.prefixText, isNull);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      final accounts = (await tester.runAsync(
        () => ledger.watchAccounts(bookId).first,
      ))!;
      expect(
        accounts
            .firstWhere((a) => a.account.accountClass == AccountClass.money)
            .balancePaise,
        150000000,
      );
      await _unmount(tester);
    });
  });

  group('F1-1006c-17 a ticked row is still a door', () {
    testWidgets('F1-1006c-17 after Finish the struck Opening balances row '
        'reopens S0.6; its tick wears success, never credit', (tester) async {
      final ledger = await openTestLedger();
      await ledger.bootstrapSolo();
      onboardingFlow.setYourName(_name);
      final router = await _pump(
        tester,
        ledger,
        at: OnboardingPaths.openingBalances,
        prefs: MemoryPrefs(),
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(_where(router), HomePaths.home);

      final tick = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      final status = RkStatusColors.of(
        tester.element(find.byIcon(Icons.check_circle)),
      );
      expect(tick.color, status.success);
      expect(tick.color, isNot(status.credit));
      // Every row that draws a chevron answers a tap (07 §1 rule 6).
      final row = find.ancestor(
        of: find.text('Opening balances'),
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.chevron_right)),
        findsOneWidget,
      );
      await tester.tap(find.text('Opening balances'));
      await tester.pumpAndSettle();
      expect(_where(router), OnboardingPaths.openingBalances);
      expect(find.text('What do you have?'), findsOneWidget);
      await _unmount(tester);
    });
  });
}
