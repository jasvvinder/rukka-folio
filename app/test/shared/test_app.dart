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
  await ledger.bootstrapSolo(firstBookName: 'Me');
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

/// Pumps [child] under MaterialApp (rkTheme light/dark, EN/PA/HI delegates)
/// and an [RkScope] carrying an in-memory ledger plus the given fakes. With
/// [ledger] the scope uses that facade's database and key store and a
/// [LedgerScope] is added beneath, so data screens find real postings.
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
}) async {
  final db = ledger?.db ?? await openTestDb();
  final app = MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: rkLocalizationsDelegates,
    theme: rkTheme(Brightness.light),
    darkTheme: rkTheme(Brightness.dark),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
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
}
