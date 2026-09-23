// S12.5 at the entry Save path — read-only and book full (13 §3.2 row S12.5;
// 13 §6 *two graces, two copies*, *book full blocks posting only, drafts
// kept*, *lapse blocks new entry only*; 07 §5 *Book full*; 07 §20 🔒; ADR
// 2026-09-05f §B row *Book full*; ADR 2026-09-05g §3, §4, §5; ADR 2026-09-05b
// §7).
//
//   F1-07-491 read-only (a fresh token saying lapsed) blocks Save with the
//             S12.5 read-only sheet: nothing reaches the real ledger, and the
//             amount and both sides are still there after dismiss.
//   F1-07-492 the paired negatives — no token, offline grace (a stale token,
//             even one that said lapsed), dunning grace and trial all post,
//             raise no sheet and never show the lapse words.
//   F1-07-493 book full (`rejected:quota`) on this book blocks Save with the
//             book-full sheet, draft kept; quota on a different book posts;
//             read-only outranks book full.
//   F1-07-494 Move money between books: either book full blocks the pair and
//             neither book gets an envelope; neither full posts both halves.
//   F1-07-495 the sheet's way forward reaches S12.1 Plans at
//             `SubscriptionPaths.plans`, and S2 is still underneath with the
//             draft intact (07 §1 rule 6: no dead end).
//   F1-07-496 EN/PA/HI at 200 % on 360×800 — the sheet over S2 fits, nothing
//             cut.
//
// Every blocking test counts rows in the **real** in-memory ledger's
// projection; a sheet that appeared while the entry still posted would fail.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/entry/widgets/entry_preview_line.dart';
import 'package:rukka_folio/features/entry/widgets/entry_slot_field.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/subscription_paths.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/widgets/rk_restriction.dart';

import '../../shared/test_app.dart';

int _seq = 0;

/// A synthetic entitlement reading (CLAUDE.md rule 4 — no real tenant).
Entitlement _reading(
  EntitlementGraceKind grace, {
  EntitlementSourceKind source = EntitlementSourceKind.fresh,
}) => Entitlement(
  tenantId: 't-synthetic',
  plan: RkPlan.family,
  limits: rkTierFor(RkPlan.family).limits,
  periodEnd: DateTime(2026, 9, 1),
  graceKind: grace,
  source: source,
  activeMembers: 1,
);

/// The server has said lapsed, on a token this phone holds fresh.
Entitlement get _lapsed => _reading(EntitlementGraceKind.lapsed);

Widget _screen(
  SeededLedger s, {
  EntitlementSource? entitlement,
  EntryKind kind = EntryKind.moneyOut,
  VoidCallback? onPlans,
}) {
  final screen = AddEntryScreen(
    key: ValueKey('s12-5-${_seq++}'),
    bookId: s.bookId,
    kind: kind,
    onPlans: onPlans,
  );
  return entitlement == null
      ? screen
      : EntitlementScope(source: entitlement, child: screen);
}

Future<void> _pump(
  WidgetTester tester,
  SeededLedger s, {
  EntitlementSource? entitlement,
  FakeSyncClient? sync,
  EntryKind kind = EntryKind.moneyOut,
  VoidCallback? onPlans,
  Locale? locale,
  double textScale = 1,
  Size? viewport,
}) => pumpRk(
  tester,
  _screen(s, entitlement: entitlement, kind: kind, onPlans: onPlans),
  ledger: s.ledger,
  sync: sync,
  locale: locale,
  textScale: textScale,
  viewport: viewport,
);

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(AddEntryScreen)));

Future<void> _typeAmount(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.byKey(AddEntryKeys.pad(k)));
    await tester.pump();
  }
}

/// Picks [name] for [slot] through the in-place list (S2.1).
Future<void> _pick(WidgetTester tester, EntrySlot slot, String name) async {
  await tester.tap(find.byKey(AddEntryKeys.slot(slot)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

/// ₹2,400 · Money out · Cash in hand → Diesel.
Future<void> _fillMoneyOut(WidgetTester tester) async {
  await _typeAmount(tester, '2400');
  await _pick(tester, EntrySlot.money, 'Cash in hand');
  await _pick(tester, EntrySlot.ledger, 'Diesel');
}

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byKey(AddEntryKeys.save)).enabled;

String? _slotValue(WidgetTester tester, EntrySlot slot) =>
    tester.widget<EntrySlotField>(find.byKey(AddEntryKeys.slot(slot))).value;

/// The draft is exactly as the user left it: the amount, both sides, and a
/// Save that is still offered.
void _expectDraftKept(
  WidgetTester tester, {
  required int paise,
  required String money,
  required String other,
}) {
  final preview = tester.widget<EntryPreviewLine>(
    find.byType(EntryPreviewLine),
  );
  expect(preview.amountPaise, paise, reason: 'the amount survives');
  expect(preview.complete, isTrue);
  expect(_slotValue(tester, EntrySlot.money), money);
  expect(_slotValue(tester, EntrySlot.ledger), other);
  expect(_saveEnabled(tester), isTrue);
}

/// Real event-loop turns: a ledger write is sqlite I/O, which `pumpAndSettle`
/// alone never lets finish.
Future<void> _settleIo(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

/// Every projected entry's book, read from the real ledger.
Future<List<String>> _entryBooks(WidgetTester tester, SeededLedger s) async {
  final rows = (await tester.runAsync(
    () => s.ledger.db.customSelect('SELECT book_id FROM entries_p').get(),
  ))!;
  return [for (final r in rows) r.read<String>('book_id')];
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.byKey(AddEntryKeys.save));
  await _settleIo(tester);
}

RkRestrictionKind? _sheetKind(WidgetTester tester) {
  final f = find.byType(RkBlockedEntrySheet);
  if (f.evaluate().isEmpty) return null;
  return tester.widget<RkBlockedEntrySheet>(f).kind;
}

Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tap(find.text(_l10n(tester).subscriptionSheetDismiss));
  await tester.pumpAndSettle();
}

/// A seeded book plus a second book this device holds (07 §10 🔒).
Future<({SeededLedger s, String familyId})> _twoBooks() async {
  final s = await seedSoloLedger();
  final familyId = await s.ledger.createBook(
    name: 'Sharma Family',
    type: BookType.family,
    cashName: 'Family Cash',
  );
  return (s: s, familyId: familyId);
}

/// ₹5,000 · Move money · SBI Saving → Sharma Family · Family Cash.
Future<void> _fillBetweenBooks(WidgetTester tester, String familyId) async {
  await _typeAmount(tester, '5000');
  // The FROM side from its chip row (07 §5 step 2), as F1-07-119 does.
  await tester.tap(find.text('SBI Saving').first);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(AddEntryKeys.book(familyId)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Family Cash').last);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => EditableText.debugDeterministicCursor = true);
  tearDownAll(() => EditableText.debugDeterministicCursor = false);

  group('F1-07-491 read-only blocks Save (13 §6, 07 §20 🔒)', () {
    testWidgets('F1-07-491 a server-declared lapse raises the read-only sheet, '
        'posts nothing, and leaves the draft filled after dismiss', (
      tester,
    ) async {
      final s = await seedSoloLedger();
      await _pump(
        tester,
        s,
        entitlement: FakeEntitlementSource(entitlement: _lapsed),
      );
      final l10n = _l10n(tester);
      final before = await _entryBooks(tester, s);
      await _fillMoneyOut(tester);
      await _tapSave(tester);

      expect(_sheetKind(tester), RkRestrictionKind.readOnly);
      // DESIGN-PACK §11 S12.5's words — and never the book-full ones.
      expect(find.text(l10n.subscriptionSheetReadOnlyTitle), findsOneWidget);
      expect(find.text(l10n.subscriptionSheetReadOnlyBlocked), findsOneWidget);
      expect(
        find.text(l10n.subscriptionSheetReadOnlyStillWorks),
        findsOneWidget,
      );
      expect(find.text(l10n.subscriptionActionRenew), findsOneWidget);
      expect(find.text(l10n.subscriptionSheetBookFullTitle), findsNothing);
      expect(await _entryBooks(tester, s), before, reason: 'nothing posted');

      await _dismissSheet(tester);
      expect(find.byType(RkBlockedEntrySheet), findsNothing);
      _expectDraftKept(
        tester,
        paise: 240000,
        money: 'Cash in hand',
        other: 'Diesel',
      );
      expect(find.text(l10n.entrySaved), findsNothing);

      // Still blocked on the second try — the sheet is not a one-off.
      await _tapSave(tester);
      expect(_sheetKind(tester), RkRestrictionKind.readOnly);
      await _dismissSheet(tester);
      expect(await _entryBooks(tester, s), before);
      _expectDraftKept(
        tester,
        paise: 240000,
        money: 'Cash in hand',
        other: 'Diesel',
      );
      await _unmount(tester);
    });
  });

  group('F1-07-492 nothing else blocks (ADR 2026-09-05g §1, §4 🔒)', () {
    testWidgets('F1-07-492 no token, offline grace (even a stale token that '
        'said lapsed), dunning grace and trial all post, raise no sheet, and '
        'never show the lapse words', (tester) async {
      final cases = <String, EntitlementSource?>{
        'no scope (production today)': null,
        'untokened source': const UntokenedEntitlementSource(),
        'offline grace (stale, said lapsed)': FakeEntitlementSource(
          entitlement: _reading(
            EntitlementGraceKind.lapsed,
            source: EntitlementSourceKind.stale,
          ),
        ),
        'dunning grace': FakeEntitlementSource(
          entitlement: _reading(EntitlementGraceKind.dunning),
        ),
        'trial': FakeEntitlementSource(
          entitlement: _reading(EntitlementGraceKind.trial),
        ),
      };
      for (final MapEntry(key: name, value: source) in cases.entries) {
        final s = await seedSoloLedger();
        await _pump(tester, s, entitlement: source);
        final l10n = _l10n(tester);
        final before = await _entryBooks(tester, s);
        await _fillMoneyOut(tester);
        await _tapSave(tester);

        expect(_sheetKind(tester), isNull, reason: name);
        expect(await _entryBooks(tester, s), [
          ...before,
          s.bookId,
        ], reason: '$name: exactly one entry posted');
        expect(find.text(l10n.entrySaved), findsOneWidget, reason: name);
        // 07 §20 🔒: never "your plan lapsed" before the server has said so;
        // 07 §5 *States*: offline = identical, so S2 carries no banner.
        expect(find.text(l10n.subscriptionSheetReadOnlyTitle), findsNothing);
        expect(find.text(l10n.subscriptionBannerReadOnlyTitle), findsNothing);
        expect(find.byType(RkRestrictionBanner), findsNothing, reason: name);
        await _unmount(tester);
      }
    });
  });

  group('F1-07-493 book full blocks posting only (ADR 2026-09-05b §7)', () {
    testWidgets('F1-07-493 rejected:quota on this book raises the book-full '
        'sheet, posts nothing, and keeps the draft', (tester) async {
      final s = await seedSoloLedger();
      final sync = FakeSyncClient()..fullBooks.add(s.bookId);
      await _pump(tester, s, sync: sync);
      final l10n = _l10n(tester);
      final before = await _entryBooks(tester, s);
      await _fillMoneyOut(tester);
      await _tapSave(tester);

      expect(_sheetKind(tester), RkRestrictionKind.bookFull);
      expect(find.text(l10n.subscriptionSheetBookFullTitle), findsOneWidget);
      expect(find.text(l10n.subscriptionSheetBookFullBlocked), findsOneWidget);
      expect(
        find.text(l10n.subscriptionSheetBookFullStillWorks),
        findsOneWidget,
      );
      expect(find.text(l10n.subscriptionActionPlans), findsOneWidget);
      expect(find.text(l10n.subscriptionSheetReadOnlyTitle), findsNothing);
      expect(await _entryBooks(tester, s), before, reason: 'nothing posted');
      expect(sync.syncNowCalls, 0, reason: 'no save, so no save trigger');

      await _dismissSheet(tester);
      _expectDraftKept(
        tester,
        paise: 240000,
        money: 'Cash in hand',
        other: 'Diesel',
      );
      await _unmount(tester);
    });

    testWidgets('F1-07-493 quota on a different book does not block this one', (
      tester,
    ) async {
      final s = await seedSoloLedger();
      final sync = FakeSyncClient()..fullBooks.add('b-some-other-book');
      await _pump(tester, s, sync: sync);
      final before = await _entryBooks(tester, s);
      await _fillMoneyOut(tester);
      await _tapSave(tester);

      expect(_sheetKind(tester), isNull);
      expect(await _entryBooks(tester, s), [...before, s.bookId]);
      expect(sync.syncNowCalls, 1, reason: 'the 05 §7 save trigger ran');
      await _unmount(tester);
    });

    testWidgets('F1-07-493 read-only is asked first: a lapsed tenant whose '
        'book is also full sees the read-only sheet', (tester) async {
      final s = await seedSoloLedger();
      await _pump(
        tester,
        s,
        entitlement: FakeEntitlementSource(entitlement: _lapsed),
        sync: FakeSyncClient()..fullBooks.add(s.bookId),
      );
      final before = await _entryBooks(tester, s);
      await _fillMoneyOut(tester);
      await _tapSave(tester);
      expect(_sheetKind(tester), RkRestrictionKind.readOnly);
      expect(await _entryBooks(tester, s), before);
      await _unmount(tester);
    });
  });

  group('F1-07-494 between books: either book full blocks the pair', () {
    testWidgets('F1-07-494 destination full, then source full — no envelope '
        'in either book; neither full posts both halves', (tester) async {
      for (final full in ['to', 'from', 'neither']) {
        final two = await _twoBooks();
        final s = two.s;
        final sync = FakeSyncClient();
        switch (full) {
          case 'to':
            sync.fullBooks.add(two.familyId);
          case 'from':
            sync.fullBooks.add(s.bookId);
          default:
            sync.fullBooks.add('b-some-other-book');
        }
        await _pump(tester, s, sync: sync, kind: EntryKind.transfer);
        final before = await _entryBooks(tester, s);
        await _fillBetweenBooks(tester, two.familyId);
        expect(_saveEnabled(tester), isTrue, reason: 'the draft is complete');
        final money = _slotValue(tester, EntrySlot.money);
        final other = _slotValue(tester, EntrySlot.ledger);
        await _tapSave(tester);

        if (full == 'neither') {
          expect(_sheetKind(tester), isNull);
          final after = await _entryBooks(tester, s);
          expect(after.length, before.length + 2, reason: 'both halves');
          expect(after.where((b) => b == two.familyId).length, 1);
        } else {
          expect(_sheetKind(tester), RkRestrictionKind.bookFull, reason: full);
          expect(
            await _entryBooks(tester, s),
            before,
            reason: '$full full: neither half posted',
          );
          await _dismissSheet(tester);
          _expectDraftKept(tester, paise: 500000, money: money!, other: other!);
        }
        await _unmount(tester);
      }
    });
  });

  group('F1-07-495 the way forward is S12.1 Plans (07 §1 rule 6)', () {
    testWidgets('F1-07-495 the sheet\'s primary action hands off once and the '
        'draft is still there', (tester) async {
      final s = await seedSoloLedger();
      var plans = 0;
      await _pump(
        tester,
        s,
        sync: FakeSyncClient()..fullBooks.add(s.bookId),
        onPlans: () => plans++,
      );
      final l10n = _l10n(tester);
      final before = await _entryBooks(tester, s);
      await _fillMoneyOut(tester);
      await _tapSave(tester);
      await tester.tap(find.text(l10n.subscriptionActionPlans));
      await tester.pumpAndSettle();
      expect(plans, 1);
      expect(find.byType(RkBlockedEntrySheet), findsNothing);
      expect(await _entryBooks(tester, s), before);
      _expectDraftKept(
        tester,
        paise: 240000,
        money: 'Cash in hand',
        other: 'Diesel',
      );
      await _unmount(tester);
    });

    testWidgets('F1-07-495 under a real router the default pushes '
        'SubscriptionPaths.plans over S2, and Back returns to the draft', (
      tester,
    ) async {
      final s = await seedSoloLedger();
      final router = GoRouter(
        initialLocation: '/entry',
        routes: [
          GoRoute(
            path: '/entry',
            builder: (_, _) => EntitlementScope(
              source: FakeEntitlementSource(entitlement: _lapsed),
              child: AddEntryScreen(bookId: s.bookId, kind: EntryKind.moneyOut),
            ),
          ),
          GoRoute(
            path: SubscriptionPaths.plans,
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('plans-landed'))),
          ),
        ],
      );
      rkViewport(tester, rkPhone375);
      await tester.pumpWidget(
        RkScope(
          db: s.ledger.db,
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          keys: s.ledger.keys as FakeKeyStore,
          now: s.ledger.now,
          child: LedgerScope(
            ledger: s.ledger,
            child: MaterialApp.router(
              routerConfig: router,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: rkLocalizationsDelegates,
              theme: rkTheme(Brightness.light),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = _l10n(tester);
      final before = await _entryBooks(tester, s);
      await _fillMoneyOut(tester);
      await _tapSave(tester);
      await tester.tap(find.text(l10n.subscriptionActionRenew));
      await tester.pumpAndSettle();
      // Only the route registered at SubscriptionPaths.plans builds this.
      expect(find.text('plans-landed'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AddEntryScreen), findsOneWidget);
      expect(await _entryBooks(tester, s), before);
      _expectDraftKept(
        tester,
        paise: 240000,
        money: 'Cash in hand',
        other: 'Diesel',
      );
      await _unmount(tester);
    });
  });

  group('F1-07-496 the sheet over S2 at 200 % (07 §1, 07 §18)', () {
    testWidgets('F1-07-496 EN, PA and HI at 200 % on 360×800: both sheets fit '
        'over S2 and nothing is cut', (tester) async {
      for (final locale in rkLocales) {
        for (final kind in [
          RkRestrictionKind.readOnly,
          RkRestrictionKind.bookFull,
        ]) {
          final s = await seedSoloLedger();
          await _pump(
            tester,
            s,
            entitlement: kind == RkRestrictionKind.readOnly
                ? FakeEntitlementSource(entitlement: _lapsed)
                : null,
            sync: kind == RkRestrictionKind.bookFull
                ? (FakeSyncClient()..fullBooks.add(s.bookId))
                : null,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          await _fillMoneyOut(tester);
          await _tapSave(tester);
          final tag = '${locale.languageCode} · ${kind.name} at 200 %';
          expect(tester.takeException(), isNull, reason: tag);
          expect(_sheetKind(tester), kind, reason: tag);
          expectTextFits(tester, reason: tag);
          // The dismiss sits at the foot of the sheet — reachable, so the
          // sheet is never a dead end at this size.
          final dismiss = find.text(_l10n(tester).subscriptionSheetDismiss);
          await tester.ensureVisible(dismiss);
          await tester.pumpAndSettle();
          await tester.tap(dismiss);
          await tester.pumpAndSettle();
          expect(find.byType(RkBlockedEntrySheet), findsNothing, reason: tag);
          await _unmount(tester);
        }
      }
    });
  });
}
