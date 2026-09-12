// Shared widget-test harness: theme + l10n + RkScope over an in-memory ledger.
// Every UI lane pumps its screen through here so tests see the real theme,
// real strings and swappable fakes — and, with `ledger:`, a seeded
// `LocalLedger` under a `LedgerScope` so screens run against real postings.
//
// Test code may use the clock and `package:sodium` directly — the purity rule
// (CLAUDE.md rule 3) binds lib/, not test/.
import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/ledger/ledger_scope.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';
// sodium_libs (app pubspec) re-exports this; pubspec is the shell lane's file.
// ignore: depend_on_referenced_packages
import 'package:sodium/sodium.dart';

/// A fixed clock for tests: 2026-09-07 10:00 IST.
DateTime testNow() => DateTime(2026, 9, 7, 10);

/// A settable clock: `clock()` is what the code under test reads.
final class TestClock {
  /// Starts at [now] (defaults to [testNow]).
  TestClock([DateTime? now]) : now = now ?? testNow();

  /// Current reading.
  DateTime now;

  /// Reads the clock.
  DateTime call() => now;

  /// Moves the clock forward.
  void advance(Duration d) => now = now.add(d);
}

Sodium? _sodium;

/// The process-wide libsodium binding (built by `package:sodium`'s build hook
/// under `flutter test`, same as core_crypto's suite B helper).
Future<Sodium> testSodium() async => _sodium ??= await SodiumInit.init();

/// A [CryptoSuite] over libsodium's real CSPRNG.
Future<CryptoSuite> testSuite() async => CryptoSuite(await testSodium());

/// Opens an in-memory ledger database, closed automatically at tear-down.
Future<LedgerDatabase> openTestDb() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final r = await openLedgerDatabase(NativeDatabase.memory());
  final db = switch (r) {
    Opened(:final db) => db,
    _ => throw StateError('in-memory ledger did not open: $r'),
  };
  addTearDown(db.close);
  return db;
}

/// An un-bootstrapped [LocalLedger] over a fresh in-memory database and
/// [keys] (a new [FakeKeyStore] by default); disposed at tear-down.
Future<LocalLedger> openTestLedger({
  DateTime Function() now = testNow,
  FakeKeyStore? keys,
  LedgerDatabase? db,
}) async {
  final ledger = LocalLedger(
    db: db ?? await openTestDb(),
    keys: keys ?? FakeKeyStore(),
    suite: await testSuite(),
    now: now,
  );
  addTearDown(ledger.dispose);
  return ledger;
}

/// A bootstrapped solo ledger with one book and a small synthetic chart —
/// what [seedSoloLedger] returns. Amounts are synthetic (CLAUDE.md rule 4).
final class SeededLedger {
  /// Creates the handle.
  const SeededLedger({
    required this.ledger,
    required this.bookId,
    required this.cashId,
    required this.bankId,
    required this.partyId,
    required this.salesId,
    required this.fuelId,
    required this.entries,
  });

  /// The facade (open).
  final LocalLedger ledger;

  /// The one book (personal, FY from April).
  final String bookId;

  /// *Cash in hand* — money · cash.
  final String cashId;

  /// *SBI Saving* — money · saving.
  final String bankId;

  /// *Ramesh* — a party.
  final String partyId;

  /// *Shop sales* — income category.
  final String salesId;

  /// *Diesel* — expense category.
  final String fuelId;

  /// The posted entries, oldest first: opening balances (cash, bank), money
  /// in (sales → bank), money out (diesel ← cash), gave on credit (Ramesh ←
  /// cash), money in (Ramesh → cash, partial repayment), transfer (bank →
  /// cash).
  final List<Entry> entries;
}

/// Seeds an in-memory solo ledger the U1/U2/U3 lanes can pump screens
/// against. Balances after seeding (engine sign, paise): cash +21_600_00,
/// bank +1_14_600_00, Ramesh +5_000_00 (they owe), sales −18_600_00, diesel
/// +2_400_00, Opening Balance −1_25_000_00. Dates run over the week before
/// [clock] (default [testNow]), newest last.
Future<SeededLedger> seedSoloLedger({
  DateTime Function() clock = testNow,
  FakeKeyStore? keys,
}) async {
  final ledger = await openTestLedger(now: clock, keys: keys);
  // The seeded history runs over the week before [clock], so the book's start
  // date (ADR 2026-09-09d §4) sits a week back too — otherwise every
  // back-dated fixture entry would be refused as before the books began.
  final start = ledger.today().addDays(-7);
  await ledger.bootstrapSolo(firstBookName: 'Me', startDate: start);
  final bookId = (await ledger.mirror.bookIds()).single;
  final cash = await ledger.addAccount(
    bookId,
    name: 'Cash in hand',
    accountClass: AccountClass.money,
    subtype: MoneySubtype.cash,
  );
  final bank = await ledger.addAccount(
    bookId,
    name: 'SBI Saving',
    accountClass: AccountClass.money,
    subtype: MoneySubtype.saving,
  );
  final party = await ledger.addAccount(
    bookId,
    name: 'Ramesh',
    accountClass: AccountClass.party,
  );
  final sales = await ledger.addAccount(
    bookId,
    name: 'Shop sales',
    accountClass: AccountClass.categoryIncome,
  );
  final fuel = await ledger.addAccount(
    bookId,
    name: 'Diesel',
    accountClass: AccountClass.categoryExpense,
  );
  final today = ledger.today();
  final entries = <Entry>[
    ...await ledger.openingBalances(
      bookId,
      balances: {cash.id: 2_500_000, bank.id: 10_000_000},
      date: today.addDays(-7),
    ),
    await ledger.moneyIn(
      bookId: bookId,
      into: bank.id,
      from: sales.id,
      paise: 1_860_000,
      date: today.addDays(-5),
      note: 'Saturday sales',
      channel: 'upi',
    ),
    await ledger.moneyOut(
      bookId: bookId,
      from: cash.id,
      forWhat: fuel.id,
      paise: 240_000,
      date: today.addDays(-3),
      note: 'Diesel A/C',
    ),
    await ledger.gaveCredit(
      bookId: bookId,
      toWhom: party.id,
      gave: cash.id,
      paise: 1_000_000,
      date: today.addDays(-2),
    ),
    await ledger.moneyIn(
      bookId: bookId,
      into: cash.id,
      from: party.id,
      paise: 500_000,
      date: today.addDays(-1),
      note: 'part repayment',
    ),
    await ledger.transfer(
      bookId: bookId,
      from: bank.id,
      to: cash.id,
      paise: 400_000,
      date: today,
      channel: 'netbanking',
    ),
  ];
  return SeededLedger(
    ledger: ledger,
    bookId: bookId,
    cashId: cash.id,
    bankId: bank.id,
    partyId: party.id,
    salesId: sales.id,
    fuelId: fuel.id,
    entries: entries,
  );
}

/// The narrow modern phone of 09 suite F — the harder of the two widths.
const rkPhone360 = Size(360, 800);

/// The short small phone of 09 suite F (ADR 2026-09-05f §H).
const rkPhone375 = Size(375, 667);

/// Both F1 phone viewports, in the order the suite names them.
const rkPhones = [rkPhone360, rkPhone375];

/// The three languages every user-facing string ships in (CLAUDE.md rule 8).
const rkLocales = [Locale('en'), Locale('pa'), Locale('hi')];

/// The scales an F1 layout case sweeps. 1.3 matters as much as 2.0: at 200 %
/// a bar has usually dropped its labels for icons, so **1.3 is where a word
/// is still drawn and is widest**. A threshold alone can never stand in for
/// it — it cannot know how wide a word is in a font it has not measured
/// (U3g, S8.2: green at 200 %, 88 px of overflow at 1.3).
const rkTextScales = [1.3, 2.0];

/// A viewport tall enough that a lazy list builds every row — a sliver below
/// the fold has no element, so `find` cannot see it. Use it for *content*
/// assertions; use [pumpRk]'s `viewport` for layout ones.
const rkTallViewport = Size(400, 3000);

/// Sets the test view to [size] at 1 logical pixel per physical pixel and
/// restores it at tear-down. [pumpRk] calls this for its `viewport:`; call it
/// directly only when the size must change between pumps.
void rkViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Fails if any text in the tree is drawn narrower than its longest
/// unbreakable word — the *silent* cut, the one no exception reports.
///
/// A `RenderFlex` overflow throws and `tester.takeException()` catches it. A
/// paragraph does not: given less width than one of its words needs, it lays
/// that word out at the box width and draws the rest past the edge. Nothing
/// is thrown, `findsOneWidget` passes, and an amount reads as `+₹1,14,6` on
/// the phone. `+₹1,14,600` has no break opportunity at all, so this is how
/// every squeezed money figure fails.
///
/// The check is font-measured, never a text-scale threshold: the question is
/// whether *this* word in *this* font needs more room than it was given, which
/// a scale number cannot answer (U3g, S8.2). Text that opted into
/// [TextOverflow.ellipsis] (or fade) is skipped — truncating there is the
/// design, and it shows the reader a `…`.
void expectTextFits(WidgetTester tester, {String? reason}) {
  final cut = <String>[];
  void visit(RenderObject o) {
    if (o is RenderParagraph && o.overflow == TextOverflow.clip) {
      final word = o.getMinIntrinsicWidth(double.infinity);
      if (word > o.size.width + 0.5) {
        cut.add(
          '  "${o.text.toPlainText()}" needs ${word.toStringAsFixed(1)}px for '
          'its longest word, drawn in ${o.size.width.toStringAsFixed(1)}px',
        );
      }
    }
    o.visitChildren(visit);
  }

  final root = tester.binding.rootElement?.renderObject;
  if (root != null) visit(root);
  if (cut.isNotEmpty) {
    fail(
      'Text is cut off${reason == null ? '' : ' ($reason)'}:\n'
      '${cut.join('\n')}',
    );
  }
}

/// Flip to make an unconverted zero-sized screen fatal everywhere, not only
/// where [pumpRk] was given a `textScale:`/`viewport:`. It stays `false` only
/// while the 24 test files listed in the M5-T1 lane report still wrap their
/// own bare `MediaQueryData`; the lane that converts the last of them sets
/// this to `true` and deletes this comment.
const rkStrictViewport = false;

/// Rejects — or, for a not-yet-converted caller, denounces — a tree laying
/// itself out against an empty screen.
///
/// A freshly constructed `MediaQueryData` carries `size: Size.zero`, so a test
/// that wrapped its screen in a bare `MediaQuery(data: MediaQueryData(
/// textScaler: …))` was asserting against a **zero-sized** screen: a widget
/// that budgets itself against `MediaQuery.sizeOf` collapses to nothing,
/// nothing can overflow nothing, and `findsOneWidget` still passes. U3g found
/// its S8.2 app-bar action 0.0 px wide under a green assertion.
///
/// [pumpRk]'s `textScale:` is what makes that wrapper unnecessary. Where a
/// caller has taken it — or asked for a `viewport:` — a zero-sized MediaQuery
/// underneath is a contradiction and fails the test outright, so converted
/// code can never regress. Where a caller has not, the tree is still a lie,
/// but it is another lane's file this round: it gets a loud, greppable line
/// per test instead of a red that nobody owns.
void _checkScreenSize(WidgetTester tester, {required bool strict}) {
  for (final q in tester.widgetList<MediaQuery>(find.byType(MediaQuery))) {
    if (!q.data.size.isEmpty) continue;
    const what =
        'the screen under test has no area, so no layout assertion in it '
        'means anything.';
    const fix =
        'Almost always `MediaQuery(data: MediaQueryData(textScaler: …))`, '
        'which starts from a blank MediaQueryData rather than the real one. '
        'Use pumpRk(tester, screen, textScale: 2, viewport: rkPhone360) '
        'instead — it scales text from the live MediaQuery and keeps the '
        'viewport.';
    if (strict || rkStrictViewport) {
      throw FlutterError(
        'A MediaQuery in this tree has size ${q.data.size} — $what\n$fix',
      );
    }
    debugPrint('RK-HARNESS ZERO-SIZED SCREEN: $what $fix');
    return;
  }
}

/// Pumps [child] under MaterialApp (rkTheme light/dark, EN/PA/HI delegates)
/// and an [RkScope] carrying an in-memory ledger plus the given fakes. With
/// [ledger] the scope uses that facade's database and key store and a
/// [LedgerScope] is added beneath, so data screens find real postings.
///
/// [viewport] sets the screen size (see [rkPhone360], [rkPhone375],
/// [rkTallViewport]) and [textScale] the user's font scale. The scale is
/// applied by `copyWith` on the **live** MediaQuery, above the Navigator, so
/// the real viewport survives it and dialogs, sheets and snackbars are scaled
/// too. Every pump is checked by [_checkScreenSize].
Future<void> pumpRk(
  WidgetTester tester,
  Widget child, {
  Locale? locale,
  FakeSyncClient? sync,
  FakeAuthClient? auth,
  FakeKeyStore? keys,
  LocalLedger? ledger,
  DateTime Function() now = testNow,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size? viewport,
}) async {
  if (viewport != null) rkViewport(tester, viewport);
  final db = ledger?.db ?? await openTestDb();
  final app = MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: rkLocalizationsDelegates,
    theme: rkTheme(Brightness.light),
    darkTheme: rkTheme(Brightness.dark),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: textScale == 1
        ? null
        : (context, navigator) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: navigator!,
          ),
    home: child,
  );
  await tester.pumpWidget(
    RkScope(
      db: db,
      sync: sync ?? FakeSyncClient(),
      auth: auth ?? FakeAuthClient(),
      keys: keys ?? (ledger?.keys as FakeKeyStore?) ?? FakeKeyStore(),
      now: ledger?.now ?? now,
      child: ledger == null ? app : LedgerScope(ledger: ledger, child: app),
    ),
  );
  await tester.pumpAndSettle();
  _checkScreenSize(tester, strict: textScale != 1 || viewport != null);
}
