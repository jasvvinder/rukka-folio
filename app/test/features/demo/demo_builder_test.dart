// F1 tests for the debug-only demo builder (owner-directed, 4 Oct 2026).
//
// Every roster here is the FICTIONAL one (`demo_roster_fallback.dart`) or a
// synthetic one written below — never the owner's real roster, which is
// git-ignored and never read by a test (CLAUDE.md rule 4).
//
// (a) the gate — F1-DEMO-9; (b) building on the REAL in-memory LocalLedger —
// F1-DEMO-10, F1-DEMO-11; (c) the define decodes, a malformed one falls back —
// F1-DEMO-12; the card's own state machine — F1-DEMO-13; no Money account
// ever closes a day below zero — F1-DEMO-15; a person with nothing to build
// gets an inert card naming what is shared — F1-DEMO-16. The route and root
// wiring that make the card reachable are pinned in
// demo_route_wiring_test.dart (F1-DEMO-17, F1-DEMO-18).
@Tags(['F1'])
library;

import 'dart:collection';
import 'dart:convert';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/demo/demo_builder.dart';
import 'package:rukka_folio/features/demo/demo_gate.dart';
import 'package:rukka_folio/features/demo/demo_roster.dart';
import 'package:rukka_folio/features/demo/demo_roster_fallback.dart';
import 'package:rukka_folio/features/demo/widgets/demo_build_card.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

// The fictional joint-family head, his number spelt as S0.2 sends it (E.164).
const _rakeshPhone = '+915000081001';
const _simranPhone = '+915000082001';
const _vijayPhone = '+915000083001';

/// A number on no roster, from the reserved test block (ADR 2026-09-05i §7:
/// `+91 99999 xxxxx`) — never a real-shaped mobile.
const _offRosterPhone = '+919999900001';

/// A synthetic case for F1-DEMO-15: one person keeping books of every kind
/// under many keys, so the invented figures are checked over a spread of
/// seeds, not just the fictional roster's dozen. Trusts 0–1 have a second
/// name (collection counts), 2–3 none (receipted donations); businesses 0–1
/// are *Just me*, 2–3 shared half and half with an outside partner.
final DemoCase _sweep = DemoCase(
  people: const [
    DemoPerson(key: 'sw', name: 'Sweep Person', phone: '+91 5000 099 001'),
    DemoPerson(key: 'sw2', name: 'Sweep Second', phone: '+91 5000 099 002'),
  ],
  books: [
    for (final (kind, label) in const [
      (DemoBookKind.personal, 'Personal'),
      (DemoBookKind.family, 'Family'),
      (DemoBookKind.joint, 'Joint'),
    ])
      for (var i = 0; i < 4; i++)
        DemoBook(
          key: 'sweep.${label.toLowerCase()}.$i',
          name: 'Sweep $label $i',
          kind: kind,
          roles: const {'sw': DemoRole.head},
        ),
    for (var i = 0; i < 4; i++)
      DemoBook(
        key: 'sweep.trust.$i',
        name: 'Sweep Trust $i',
        kind: DemoBookKind.organization,
        roles: i < 2
            ? const {'sw': DemoRole.admin, 'sw2': DemoRole.operator}
            : const {'sw': DemoRole.admin},
      ),
    for (var i = 0; i < 4; i++)
      DemoBook(
        key: 'sweep.business.$i',
        name: 'Sweep Business $i',
        kind: DemoBookKind.business,
        shares: i < 2 ? const [] : const [('sw', '50%'), ('sw2', '50%')],
        roles: const {'sw': DemoRole.admin},
      ),
  ],
);

DemoWords get _en => DemoWords.of(lookupAppLocalizations(const Locale('en')));

(DemoPerson, DemoCase) _who(String phone) =>
    fictionalDemoRoster.personForPhone(phone)!;

/// Σ Dr and Σ Cr of [bookId]'s trial balance, from the projected balances.
Future<(int, int)> _trialTotals(LocalLedger ledger, String bookId) async {
  final ids = {for (final a in (await ledger.chartOf(bookId)).accounts) a.id};
  var dr = 0;
  var cr = 0;
  for (final r in await ledger.db.select(ledger.db.balances).get()) {
    if (!ids.contains(r.accountId)) continue;
    if (r.balancePaise > 0) dr += r.balancePaise;
    if (r.balancePaise < 0) cr -= r.balancePaise;
  }
  return (dr, cr);
}

Future<int> _entryCount(LocalLedger ledger, String bookId) async =>
    (await (ledger.db.select(
      ledger.db.entriesP,
    )..where((e) => e.bookId.equals(bookId))).get()).length;

/// The book's partner weights in the order of [owners], read back from the
/// `book_config` envelope (02 §7.1: keyed by Partner Current A/c id).
Future<List<int>> _weights(
  LocalLedger ledger,
  String bookId,
  List<String> owners,
) async {
  final config = (await ledger.configOf(bookId))!;
  final chart = await ledger.chartOf(bookId);
  return [
    for (final o in owners)
      config.partnerShares[chart.accounts
          .firstWhere((a) => a.name == LocalLedger.partnerCurrentAccountName(o))
          .id]!,
  ];
}

/// Every Money account of [bookId] that has postings (name → lowest
/// end-of-day balance, in paise), read from the projected posting lines in
/// date order. An account with no line is left out rather than reported as
/// zero, so the caller asserts which accounts must be there — an empty read
/// can never pass for a healthy book.
Future<Map<String, int>> _lowestDailyClose(
  LocalLedger ledger,
  String bookId,
) async {
  final money = {
    for (final a in (await ledger.chartOf(bookId)).byClass(AccountClass.money))
      a.id: a.name,
  };
  final lines = await (ledger.db.select(
    ledger.db.entryLinesP,
  )..where((l) => l.bookId.equals(bookId))).get();
  final days = <String, SplayTreeMap<String, int>>{};
  for (final l in lines) {
    if (!money.containsKey(l.accountId)) continue;
    (days[l.accountId] ??= SplayTreeMap()).update(
      l.accountingDate,
      (v) => v + l.amountPaise,
      ifAbsent: () => l.amountPaise,
    );
  }
  final lowest = <String, int>{};
  for (final MapEntry(key: id, value: name) in money.entries) {
    final byDay = days[id];
    if (byDay == null) continue;
    var running = 0;
    var low = 0;
    var first = true;
    for (final delta in byDay.values) {
      running += delta;
      if (first || running < low) low = running;
      first = false;
    }
    lowest[name] = low;
  }
  return lowest;
}

Future<String> _bookId(LocalLedger ledger, String name) async =>
    (await ledger.db.select(ledger.db.booksP).get())
        .firstWhere((b) => b.name == name)
        .id;

void main() {
  tearDown(() {
    debugDemoBuilderOverride = null;
    demoSignedInPhone.value = null;
  });

  group('F1-DEMO-9 the gate (release · switch · roster)', () {
    test('F1-DEMO-9 a release build is closed whatever the switch and phone '
        'say; the switch off or an unknown phone closes it; all three open it '
        '(control)', () {
      // Release: closed, and the roster it would read is empty.
      expect(demoBuilderOn(demoPhones: true, releaseMode: true), isFalse);
      expect(activeDemoRoster(releaseMode: true).cases, isEmpty);
      expect(
        demoPersonFor(
          signedInPhone: _rakeshPhone,
          roster: fictionalDemoRoster,
          demoPhones: true,
          releaseMode: true,
        ),
        isNull,
      );
      // Switch off.
      expect(
        demoPersonFor(
          signedInPhone: _rakeshPhone,
          roster: fictionalDemoRoster,
          demoPhones: false,
          releaseMode: false,
        ),
        isNull,
      );
      // A number not on the roster, and no number.
      for (final phone in [_offRosterPhone, null]) {
        expect(
          demoPersonFor(
            signedInPhone: phone,
            roster: fictionalDemoRoster,
            demoPhones: true,
            releaseMode: false,
          ),
          isNull,
          reason: '$phone',
        );
      }
      // Control: all three hold.
      final match = demoPersonFor(
        signedInPhone: _rakeshPhone,
        roster: fictionalDemoRoster,
        demoPhones: true,
        releaseMode: false,
      );
      expect(match?.$1.name, 'Rakesh Sharma');
    });

    test(
      'F1-DEMO-9 the sign-in watcher listens to nothing when the gate is '
      'closed, and names the number that signed in when it is open',
      () async {
        final closed = FakeAuthClient();
        expect(watchDemoSignIn(closed, demoPhones: false), isNull);
        expect(
          watchDemoSignIn(closed, demoPhones: true, releaseMode: true),
          isNull,
        );

        final auth = FakeAuthClient();
        final sub = watchDemoSignIn(
          auth,
          demoPhones: true,
          releaseMode: false,
        )!;
        addTearDown(sub.cancel);
        await auth.requestOtp(_rakeshPhone);
        await pumpEventQueue();
        expect(demoSignedInPhone.value, isNull, reason: 'not signed in yet');
        await auth.activateDevice(await auth.verifyOtp('123456'));
        await pumpEventQueue();
        expect(demoSignedInPhone.value, _rakeshPhone);
      },
    );

    testWidgets('F1-DEMO-9 S0.3 shows the demo card above the five only when '
        'the switch is on AND the signed-in phone is on the roster', (
      tester,
    ) async {
      Future<void> pumpPurpose() async {
        await pumpRk(
          tester,
          PurposeScreen(debugDemoCard: demoPurposeCard(onContinue: (_) {})),
        );
      }

      final title = find.text("Demo: build Rakesh Sharma's books");

      // Switch off, roster phone signed in.
      debugDemoBuilderOverride = false;
      demoSignedInPhone.value = _rakeshPhone;
      await pumpPurpose();
      expect(title, findsNothing);
      expect(find.text('Myself'), findsOneWidget);

      // Switch on, phone not on the roster.
      debugDemoBuilderOverride = true;
      demoSignedInPhone.value = _offRosterPhone;
      await pumpPurpose();
      expect(find.textContaining('Demo: build'), findsNothing);

      // Control: both hold.
      demoSignedInPhone.value = _rakeshPhone;
      await pumpPurpose();
      expect(title, findsOneWidget);
      expect(find.text('Debug'), findsOneWidget);
      // The five are still there beneath it.
      expect(find.text('Our trust'), findsOneWidget);
    });
  });

  group('F1-DEMO-10/11 building on the real LocalLedger', () {
    testWidgets('F1-DEMO-10 the joint-family head gets his personal book and '
        'every book he heads or administers — partner weights 1/3×3 → 1,1,1, '
        '50/30/20 → 5,3,2, 25%×4 → 1,1,1,1, the outside partner with no '
        'member id — each with a balanced trial balance; the book he is only '
        'a member of is not built', (tester) async {
      await tester.runAsync(() async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo();
        final (person, demoCase) = _who(_rakeshPhone);
        final plan = planDemoBooks(person, demoCase, _en);
        final result = await buildDemoBooks(ledger, plan, words: _en);

        expect(
          [for (final b in result.built) b.name],
          [
            'Rakesh Sharma — personal',
            'Sharma Joint Family',
            'Sharma Dairy',
            'Sharma Farm',
            'Sharma Brick Kiln',
            "Rakesh's Household",
          ],
        );
        expect(result.sharedOnly, ['Sharma Transport']);
        final names = {
          for (final b in await ledger.db.select(ledger.db.booksP).get())
            b.name,
        };
        expect(names, isNot(contains('Sharma Transport')));
        // Households he has no role in are neither built nor listed.
        expect(names, isNot(contains("Mukesh's Household")));

        final dairy = await _bookId(ledger, 'Sharma Dairy');
        expect(
          await _weights(ledger, dairy, [
            'Rakesh Sharma',
            'Mukesh Sharma',
            'Suresh Sharma',
          ]),
          [1, 1, 1],
        );
        final farm = await _bookId(ledger, 'Sharma Farm');
        expect(
          await _weights(ledger, farm, [
            'Rakesh Sharma',
            'Mukesh Sharma',
            'Suresh Sharma',
          ]),
          [5, 3, 2],
        );
        final kiln = await _bookId(ledger, 'Sharma Brick Kiln');
        expect(
          await _weights(ledger, kiln, [
            'Rakesh Sharma',
            'Mukesh Sharma',
            'Suresh Sharma',
            'Anil Gupta',
          ]),
          [1, 1, 1, 1],
        );
        // All-or-none member ids (local_ledger.dart createBook): the outside
        // partner has none, so no partner account carries one.
        final kilnPartners = (await ledger.chartOf(kiln))
            .byClass(AccountClass.partner);
        expect(kilnPartners, hasLength(4));
        expect(kilnPartners.every((a) => a.memberId == null), isTrue);

        expect(
          (await ledger.configOf(await _bookId(ledger, 'Sharma Joint Family')))!
              .type,
          BookType.joint,
        );
        for (final b in result.built) {
          final (dr, cr) = await _trialTotals(ledger, b.bookId);
          expect(dr, greaterThan(0), reason: '${b.name} has money in it');
          expect(dr, cr, reason: '${b.name} trial balance');
          expect(
            await _entryCount(ledger, b.bookId),
            greaterThanOrEqualTo(8),
            reason: '${b.name} has a history, not just an opening',
          );
        }
      });
    });

    testWidgets('F1-DEMO-11 a trust (collection counts, deposits, donations) '
        'and a just-me business (capital as Money in, own drawing) both '
        'balance; a second run makes no duplicate; the same key gives the '
        'same figures', (tester) async {
      await tester.runAsync(() async {
        Future<List<int>> figures(LocalLedger l, String bookId) async {
          final ids = {
            for (final a in (await l.chartOf(bookId)).accounts) a.id,
          };
          return [
            for (final r in await l.db.select(l.db.balances).get())
              if (ids.contains(r.accountId)) r.balancePaise,
          ]..sort();
        }

        final ledger = await openTestLedger();
        await ledger.bootstrapSolo();
        final (vijay, trustCase) = _who(_vijayPhone);
        final trustPlan = planDemoBooks(vijay, trustCase, _en);
        expect(trustPlan.toBuild.single.witness, 'Deepak Verma');
        final trust = await buildDemoBooks(ledger, trustPlan, words: _en);
        final trustId = trust.built.single.bookId;
        expect((await ledger.configOf(trustId))!.type, BookType.organization);
        final gollak = (await ledger.chartOf(trustId))
            .byClass(AccountClass.money)
            .firstWhere((a) => a.isCollection);
        expect(await ledger.lastCashCount(gollak.id), isNotNull);

        final (simran, kaurCase) = _who(_simranPhone);
        final kaurPlan = planDemoBooks(simran, kaurCase, _en);
        final kaur = await buildDemoBooks(ledger, kaurPlan, words: _en);
        expect(
          [for (final b in kaur.built) b.name],
          ['Simran Kaur', 'Kaur Boutique'],
        );
        expect(kaur.sharedOnly, isEmpty);
        final boutique = kaur.built.last.bookId;
        final drawings = (await ledger.chartOf(boutique))
            .byClass(AccountClass.equitySystem)
            .firstWhere((a) => a.systemRole == SystemRole.drawings);
        final balances = {
          for (final r in await ledger.db.select(ledger.db.balances).get())
            r.accountId: r.balancePaise,
        };
        expect(balances[drawings.id], greaterThan(0));

        for (final id in [trustId, ...kaur.built.map((b) => b.bookId)]) {
          final (dr, cr) = await _trialTotals(ledger, id);
          expect(dr, cr);
          expect(dr, greaterThan(0));
        }

        // Again: nothing new, everything reported as already here.
        final again = await buildDemoBooks(ledger, kaurPlan, words: _en);
        expect(again.built, isEmpty);
        expect(again.alreadyHere, ['Simran Kaur', 'Kaur Boutique']);

        // Determinism: a second device building the same book posts the
        // same figures (no Random, no clock beyond the injected one).
        final other = await openTestLedger();
        await other.bootstrapSolo();
        final kaur2 = await buildDemoBooks(other, kaurPlan, words: _en);
        expect(
          await figures(other, kaur2.built.last.bookId),
          await figures(ledger, boutique),
        );
      });
    });
  });

  group('F1-DEMO-12 the RF_DEMO_ROSTER define', () {
    const synthetic = {
      'cases': [
        {
          'case': 7,
          'people': [
            {'key': 'p1', 'name': 'Test Person', 'phone': '+91 5000 097 001'},
          ],
          'books': [
            {
              'key': 'b1',
              'name': 'Test Shop',
              'kind': 'business',
              'note': 'unknown fields are ignored',
              'roles': {'p1': 'admin'},
            },
          ],
          'personal_books_for': ['p1'],
        },
      ],
    };

    test('F1-DEMO-12 a base64 roster decodes; empty falls back to the '
        'fictional roster; a malformed define falls back without throwing', () {
      final good = base64.encode(utf8.encode(jsonEncode(synthetic)));
      final (roster, source) = decodeDemoRosterDefine(
        good,
        fallback: fictionalDemoRoster,
      );
      expect(source, DemoRosterSource.define);
      final (person, demoCase) = roster.personForPhone('+915000097001')!;
      expect(person.name, 'Test Person');
      expect(demoCase.personalBooksFor, ['p1']);
      expect(demoCase.books.single.kind, DemoBookKind.business);

      expect(
        decodeDemoRosterDefine('', fallback: fictionalDemoRoster).$2,
        DemoRosterSource.fallback,
      );
      for (final bad in [
        '%%% not base64 %%%',
        base64.encode(utf8.encode('not json')),
        base64.encode(utf8.encode('{"cases": []}')),
        base64.encode(
          utf8.encode(
            jsonEncode({
              'cases': [
                {
                  'people': <Object>[],
                  'books': [
                    {'key': 'x', 'name': 'X', 'kind': 'spaceship'},
                  ],
                },
              ],
            }),
          ),
        ),
      ]) {
        final (r, s) = decodeDemoRosterDefine(
          bad,
          fallback: fictionalDemoRoster,
        );
        expect(s, DemoRosterSource.malformed, reason: bad);
        expect(identical(r, fictionalDemoRoster), isTrue);
      }
    });

    test('F1-DEMO-12 share strings become 02 §7.1 integer weights in lowest '
        'terms', () {
      expect(shareWeights(['1/3', '1/3', '1/3']), [1, 1, 1]);
      expect(shareWeights(['50%', '30%', '20%']), [5, 3, 2]);
      expect(shareWeights(['25%', '25%', '25%', '25%']), [1, 1, 1, 1]);
      expect(shareWeights(['50%', '50%']), [1, 1]);
      expect(() => shareWeights(['half']), throwsFormatException);
    });
  });

  group('F1-DEMO-13 the card', () {
    testWidgets('F1-DEMO-13 tapping builds, the summary lists what was made '
        'and what is shared-only, and Continue hands on the roster name', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ledger = await tester.runAsync(() async {
        final l = await openTestLedger();
        await l.bootstrapSolo();
        return l;
      });
      final (person, demoCase) = fictionalDemoRoster.personForPhone(
        '+915000081002',
      )!;
      String? continued;
      await pumpRk(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: DemoBuildCard(
              person: person,
              demoCase: demoCase,
              onContinue: (name) => continued = name,
            ),
          ),
        ),
        ledger: ledger,
      );
      await tester.tap(find.text("Demo: build Mukesh Sharma's books"));
      for (var i = 0; i < 200; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.text('Continue').evaluate().isNotEmpty) break;
      }
      expect(find.text('Made on this phone'), findsOneWidget);
      expect(find.text('Sharma Transport'), findsOneWidget);
      expect(
        find.text('Shared with you — needs the multi-user release'),
        findsOneWidget,
      );
      // Mukesh is a member of the farm: listed, not built.
      expect(find.text('Sharma Farm'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      expect(continued, 'Mukesh Sharma');
    });
  });

  testWidgets('F1-DEMO-15 no Money account in any demo book closes a day '
      'below zero (02 §9: negative physical cash is always a missing entry) '
      '— every fictional roster person, and a sweep of synthetic book keys '
      'across every kind', (tester) async {
    await tester.runAsync(() async {
      final checked = <String>[];
      Future<void> buildAndCheck(DemoCase c) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo();
        for (final p in c.people) {
          final result = await buildDemoBooks(
            ledger,
            planDemoBooks(p, c, _en),
            words: _en,
          );
          for (final b in result.built) {
            final low = await _lowestDailyClose(ledger, b.bookId);
            // Cash and the bank account both moved: the read is not empty.
            expect(low.keys, contains(_en.bank), reason: b.name);
            expect(low.length, greaterThanOrEqualTo(2), reason: b.name);
            for (final MapEntry(key: account, value: paise) in low.entries) {
              expect(
                paise,
                greaterThanOrEqualTo(0),
                reason: '${b.name} · $account lowest daily close',
              );
            }
            checked.add(b.name);
          }
        }
      }

      for (final c in fictionalDemoRoster.cases) {
        await buildAndCheck(c);
      }
      await buildAndCheck(_sweep);
      // The books the review found below zero are among those checked.
      expect(
        checked,
        containsAll([
          'Sharma Joint Family',
          "Suresh's Household",
          "Rakesh's Household",
          'Rakesh Sharma — personal',
          'Suresh Sharma — personal',
          'Sunita Sharma — personal',
          'Simran Kaur',
          'Verma Seva Trust',
          'Sweep Trust 3',
        ]),
      );
    });
  });

  testWidgets('F1-DEMO-16 a person who keeps none of their books (viewer, '
      'operator, or a partner with a share and no role) gets a card that '
      'names the shared books and offers nothing to build — never a heading '
      'over an empty list; a roster person with no book at all gets no card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final (anil, sharma) = fictionalDemoRoster.personForPhone('+915000081006')!;
    final anilPlan = planDemoBooks(anil, sharma, _en);
    expect(anilPlan.nothingToBuild, isTrue);
    expect(anilPlan.sharedOnly, ['Sharma Brick Kiln'], reason: 'shares only');
    final (ravi, kaurCase) = fictionalDemoRoster.personForPhone(
      '+915000082002',
    )!;
    expect(planDemoBooks(ravi, kaurCase, _en).sharedOnly, ['Kaur Boutique']);
    expect(planDemoBooks(ravi, kaurCase, _en).nothingToBuild, isTrue);
    // Control: the head has books to build.
    final (rakesh, _) = _who(_rakeshPhone);
    expect(planDemoBooks(rakesh, sharma, _en).nothingToBuild, isFalse);

    // Who gets a card at all.
    const nobody = DemoPerson(
      key: 'nobody',
      name: 'Nobody',
      phone: '+91 5000 099 009',
    );
    expect(demoNamesAnyBook(nobody, sharma), isFalse);
    expect(demoNamesAnyBook(anil, sharma), isTrue);

    final ledger = await tester.runAsync(() async {
      final l = await openTestLedger();
      await l.bootstrapSolo();
      return l;
    });
    Future<int> bookCount() async => (await tester.runAsync(
      () => ledger!.db.select(ledger.db.booksP).get(),
    ))!.length;
    final before = await bookCount();

    final (neha, _) = fictionalDemoRoster.personForPhone('+915000081005')!;
    await pumpRk(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: DemoBuildCard(
            person: neha,
            demoCase: sharma,
            onContinue: (_) => fail('nothing to continue from'),
          ),
        ),
      ),
      ledger: ledger,
    );
    const noneTitle = 'Demo: no books to make for Neha Sharma';
    expect(find.text(noneTitle), findsOneWidget);
    expect(find.text("Suresh's Household"), findsOneWidget);
    expect(
      find.text('Shared with you — needs the multi-user release'),
      findsOneWidget,
    );
    expect(find.text('Made on this phone'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(find.byType(InkWell), findsNothing, reason: 'nothing to tap');
    await tester.tap(find.text(noneTitle), warnIfMissed: false);
    await tester.pump();
    expect(await bookCount(), before, reason: 'no book was made');

    // Control: the head's card is the tappable build card.
    await pumpRk(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: DemoBuildCard(
            person: rakesh,
            demoCase: sharma,
            onContinue: (_) {},
          ),
        ),
      ),
      ledger: ledger,
    );
    expect(find.text("Demo: build Rakesh Sharma's books"), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('F1-DEMO-14 the S0.3 demo card resolves in EN, PA and HI and '
      'lays out at 200 % text on 360×800 without overflow', (tester) async {
    debugDemoBuilderOverride = true;
    demoSignedInPhone.value = _rakeshPhone;
    for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
      await pumpRk(
        tester,
        PurposeScreen(debugDemoCard: demoPurposeCard(onContinue: (_) {})),
        locale: locale,
        textScale: 2,
        viewport: const Size(360, 800),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(locale);
      expect(
        find.text(l10n.demoCardTitle('Rakesh Sharma')),
        findsOneWidget,
        reason: '$locale',
      );
      expect(find.text(l10n.demoCardBadge), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$locale');
    }
  });
}
