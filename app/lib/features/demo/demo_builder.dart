// The demo builder (owner-directed, 4 Oct 2026) — DEBUG ONLY.
//
// Builds a roster person's books on THIS device, through the real
// [LocalLedger] and only the verbs a user would reach — `createBook`,
// `addAccount`, `openingBalances`, `moneyIn`, `moneyOut`, `transfer`,
// `partnerPayOut`, `recordCashCount` — so every book balances and its
// statements and trial balance render exactly as real ones would. Nothing
// here posts a line by hand.
//
// What is built: every roster book where the person is `admin` or `head`,
// plus their personal book. A book where they are only member / operator /
// viewer is NOT built: on one device it could only be made as if they owned
// it, and their real standing there needs the owner's key — so it is listed
// as *shared with you — needs the multi-user release* instead.
//
// The entries are INVENTED, deterministic (derived from the book key — no
// `Random`), round, and integer paise throughout (CLAUDE.md rule 1). They run
// over the last two to three months: the books begin on the first day of the
// month two months back (ADR 2026-09-09d §4 — nothing is dated before the
// books begin, and `createBook(startDate:)` exists for fixtures and imports).
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BookOwnership;

import '../../l10n/gen/app_localizations.dart';
import '../../shared/ledger/local_ledger.dart';
import 'demo_roster.dart';

/// The words the builder names accounts with — user data once written, but
/// shown, so they come from ARB in the user's language (CLAUDE.md rule 8).
final class DemoWords {
  const DemoWords({
    required this.bank,
    required this.sales,
    required this.purchases,
    required this.wages,
    required this.electricity,
    required this.income,
    required this.groceries,
    required this.fuel,
    required this.medical,
    required this.personalBook,
  });

  factory DemoWords.of(AppLocalizations l10n) => DemoWords(
    bank: l10n.demoAccountBank,
    sales: l10n.demoCategorySales,
    purchases: l10n.demoCategoryPurchases,
    wages: l10n.demoCategoryWages,
    electricity: l10n.demoCategoryElectricity,
    income: l10n.demoCategoryIncome,
    groceries: l10n.demoCategoryGroceries,
    fuel: l10n.demoCategoryFuel,
    medical: l10n.demoCategoryMedical,
    personalBook: l10n.demoBookPersonal,
  );

  final String bank;
  final String sales;
  final String purchases;
  final String wages;
  final String electricity;
  final String income;
  final String groceries;
  final String fuel;
  final String medical;

  /// `{name} — personal`: the name of a personal book the roster lists only
  /// under `personal_books_for`.
  final String Function(String name) personalBook;
}

/// One owner of a shared business, with their 02 §7.1 integer weight.
typedef DemoOwner = ({String name, int weight});

/// One book the person will own here.
final class DemoPlannedBook {
  const DemoPlannedBook({
    required this.key,
    required this.name,
    required this.kind,
    this.owners = const [],
    this.witness,
  });

  final String key;
  final String name;
  final DemoBookKind kind;

  /// The partners of a shared business, the person first (ADR 2026-09-09
  /// §1: the creating user is the first owner row). Empty on every other
  /// book, and on a business with fewer than two shareholders (*Just me*).
  final List<DemoOwner> owners;

  /// A trust's second name for a collection count (02 §8.2: counted-by and
  /// witness). Null → the trust's donations are receipted instead.
  final String? witness;

  bool get sharedBusiness => kind == DemoBookKind.business && owners.length > 1;
}

/// What the builder will do for one person.
final class DemoPlan {
  const DemoPlan({
    required this.person,
    required this.toBuild,
    required this.sharedOnly,
  });

  final DemoPerson person;
  final List<DemoPlannedBook> toBuild;

  /// Names of the books where the person is only member / operator / viewer,
  /// or a partner with a share and no role.
  final List<String> sharedOnly;

  /// True when there is nothing to make on this phone: the card then names
  /// the shared books and offers no build (review finding DEMO1-4).
  bool get nothingToBuild => toBuild.isEmpty;
}

/// Works out [person]'s books in [demoCase]: their personal book first, then
/// every book they are `admin` or `head` of, in roster order.
DemoPlan planDemoBooks(DemoPerson person, DemoCase demoCase, DemoWords words) {
  final toBuild = <DemoPlannedBook>[];
  final sharedOnly = <String>[];
  final ownsListedPersonal = demoCase.books.any(
    (b) =>
        b.kind == DemoBookKind.personal && (b.roles[person.key]?.owns ?? false),
  );
  if (!ownsListedPersonal && demoCase.personalBooksFor.contains(person.key)) {
    toBuild.add(
      DemoPlannedBook(
        key: '${person.key}.personal',
        name: words.personalBook(person.name),
        kind: DemoBookKind.personal,
      ),
    );
  }
  for (final b in demoCase.books) {
    final role = b.roles[person.key];
    if (role == null) {
      // A partner who holds a share but no role (an outside partner not on
      // the app) still has a stake in the book: it is shared with them, and
      // like any other shared book it is named, never built.
      if (b.shares.any((s) => s.$1 == person.key)) sharedOnly.add(b.name);
      continue;
    }
    if (!role.owns) {
      sharedOnly.add(b.name);
      continue;
    }
    final planned = DemoPlannedBook(
      key: b.key,
      name: b.name,
      kind: b.kind,
      owners: b.kind == DemoBookKind.business
          ? _owners(person, demoCase, b)
          : const [],
      witness: b.kind == DemoBookKind.organization
          ? _witness(person, demoCase, b)
          : null,
    );
    // The personal book leads, whichever way the roster lists it.
    if (b.kind == DemoBookKind.personal) {
      toBuild.insert(0, planned);
    } else {
      toBuild.add(planned);
    }
  }
  return DemoPlan(person: person, toBuild: toBuild, sharedOnly: sharedOnly);
}

/// Whether the roster names any book for [person] in [demoCase] — one the
/// demo can build, or one it can only name as shared. A roster person with
/// neither gets no demo card at all: it would have nothing to say.
bool demoNamesAnyBook(DemoPerson person, DemoCase demoCase) =>
    demoCase.personalBooksFor.contains(person.key) ||
    demoCase.books.any(
      (b) =>
          b.roles.containsKey(person.key) ||
          b.shares.any((s) => s.$1 == person.key),
    );

List<DemoOwner> _owners(DemoPerson person, DemoCase c, DemoBook b) {
  if (b.shares.length < 2) return const [];
  final ordered = [
    ...b.shares.where((s) => s.$1 == person.key),
    ...b.shares.where((s) => s.$1 != person.key),
  ];
  final weights = shareWeights([for (final s in ordered) s.$2]);
  return [
    for (final (i, s) in ordered.indexed)
      (name: c.person(s.$1)?.name ?? s.$1, weight: weights[i]),
  ];
}

String? _witness(DemoPerson person, DemoCase c, DemoBook b) {
  for (final key in b.roles.keys) {
    if (key == person.key) continue;
    final other = c.person(key);
    if (other != null) return other.name;
  }
  return null;
}

/// One built book.
typedef DemoBuiltBook = ({String name, String bookId});

/// What [buildDemoBooks] did.
final class DemoBuildResult {
  const DemoBuildResult({
    required this.built,
    required this.alreadyHere,
    required this.sharedOnly,
  });

  final List<DemoBuiltBook> built;

  /// Books skipped because a book of that name is already on this device —
  /// a second tap, or a second run, never makes a duplicate.
  final List<String> alreadyHere;

  final List<String> sharedOnly;
}

/// The first day of the month two months before [today]: the books begin
/// here, so the invented entries span the last two to three months.
LocalDate demoStartDate(LocalDate today) {
  var year = today.year;
  var month = today.month - 2;
  if (month < 1) {
    month += 12;
    year -= 1;
  }
  return LocalDate(year, month, 1);
}

/// Builds [plan] on [ledger]. [onProgress] is told `(done, total)` after
/// each book.
Future<DemoBuildResult> buildDemoBooks(
  LocalLedger ledger,
  DemoPlan plan, {
  required DemoWords words,
  void Function(int done, int total)? onProgress,
}) async {
  final today = ledger.today();
  final start = demoStartDate(today);
  final existing = {
    for (final row in await ledger.db.select(ledger.db.booksP).get()) row.name,
  };
  final built = <DemoBuiltBook>[];
  final alreadyHere = <String>[];
  final total = plan.toBuild.length;
  for (final (i, book) in plan.toBuild.indexed) {
    if (existing.contains(book.name)) {
      alreadyHere.add(book.name);
    } else {
      final id = await _createBook(ledger, book, start);
      final poster = _Poster(ledger, id, start, today, _seed(book.key));
      switch (book.kind) {
        case DemoBookKind.business:
          await poster.business(book, words);
        case DemoBookKind.organization:
          await poster.trust(book, words, countedBy: plan.person.name);
        case DemoBookKind.personal:
          await poster.household(words, scale: 1);
        case DemoBookKind.family || DemoBookKind.joint:
          await poster.household(words, scale: 2);
      }
      built.add((name: book.name, bookId: id));
      existing.add(book.name);
    }
    onProgress?.call(i + 1, total);
  }
  return DemoBuildResult(
    built: built,
    alreadyHere: alreadyHere,
    sharedOnly: plan.sharedOnly,
  );
}

/// `createBook` with the arguments the onboarding hosts pass for the same
/// kind of book (business_opening_host.dart, family_opening_host.dart,
/// trust_opening_host.dart), plus the demo's start date.
Future<String> _createBook(
  LocalLedger ledger,
  DemoPlannedBook book,
  LocalDate start,
) => switch (book.kind) {
  DemoBookKind.business => ledger.createBook(
    name: book.name,
    type: BookType.business,
    ownership: book.sharedBusiness
        ? BookOwnership.shared
        : BookOwnership.justMe,
    ownerNames: [for (final o in book.owners) o.name],
    ownerShares: [for (final o in book.owners) o.weight],
    // 02 §7.1: an owner who has not joined has no member id, and the set is
    // all-or-none (local_ledger.dart createBook) — the same answer
    // `OnboardingFlow.ownerMemberIds` gives every shared business.
    ownerMemberIds: const [],
    startDate: start,
  ),
  // The roster names no trust type, and `createBook` keeps an uncollected
  // type as null rather than guessing one (07 §3.1.1).
  DemoBookKind.organization => ledger.createBook(
    name: book.name,
    type: BookType.organization,
    startDate: start,
  ),
  DemoBookKind.family => ledger.createBook(
    name: book.name,
    type: BookType.family,
    startDate: start,
  ),
  DemoBookKind.joint => ledger.createBook(
    name: book.name,
    type: BookType.joint,
    startDate: start,
  ),
  DemoBookKind.personal => ledger.createBook(
    name: book.name,
    type: BookType.personal,
    startDate: start,
  ),
};

/// FNV-1a over the key's code units: the same number on every run and every
/// platform (unlike `String.hashCode`), so a book's figures never change.
int _seed(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

int _rupees(int r) => r * 100;

/// Posts one book's invented history. Every amount is whole rupees, held as
/// paise.
final class _Poster {
  _Poster(this.ledger, this.bookId, this.start, this.today, this.seed);

  final LocalLedger ledger;
  final String bookId;
  final LocalDate start;
  final LocalDate today;
  final int seed;

  /// [offset] days after the books began. Every offset used is under 59 —
  /// the shortest two months (February + March) — so a date never passes
  /// [today]; the guard is for certainty, not for use.
  LocalDate? _day(int offset) {
    final d = start.addDays(offset);
    return d.isAfter(today) ? null : d;
  }

  /// A small deterministic pick in `0 ≤ n < span` that differs per [salt].
  int _pick(int salt, int span) => ((seed >> (salt % 24)) + salt) % span;

  Future<Chart> get _chart => ledger.chartOf(bookId);

  Future<String> _systemAccount(SystemRole role) async => (await _chart)
      .byClass(AccountClass.equitySystem)
      .firstWhere((a) => a.systemRole == role)
      .id;

  Future<String> _cash() async => (await _chart)
      .byClass(AccountClass.money)
      .firstWhere((a) => a.subtype == MoneySubtype.cash)
      .id;

  Future<String> _add(
    String name,
    AccountClass cls, {
    MoneySubtype? subtype,
  }) async => (await ledger.addAccount(
    bookId,
    name: name,
    accountClass: cls,
    subtype: subtype,
  )).id;

  Future<void> _in(String into, String from, int rupees, int offset) async {
    final d = _day(offset);
    if (d == null) return;
    await ledger.moneyIn(
      bookId: bookId,
      into: into,
      from: from,
      paise: _rupees(rupees),
      date: d,
    );
  }

  Future<void> _out(String from, String forWhat, int rupees, int offset) async {
    final d = _day(offset);
    if (d == null) return;
    await ledger.moneyOut(
      bookId: bookId,
      from: from,
      forWhat: forWhat,
      paise: _rupees(rupees),
      date: d,
    );
  }

  Future<void> _move(String from, String to, int rupees, int offset) async {
    final d = _day(offset);
    if (d == null) return;
    await ledger.transfer(
      bookId: bookId,
      from: from,
      to: to,
      paise: _rupees(rupees),
      date: d,
    );
  }

  /// A business: capital in, a bank account, sales, purchases, wages, a
  /// bill, and one drawing per partner.
  Future<void> business(DemoPlannedBook book, DemoWords words) async {
    final cash = await _cash();
    // Rupees per share weight: ₹50,000 to ₹1,25,000.
    final unit = (2 + seed % 4) * 25000;
    final partners = (await _chart).byClass(AccountClass.partner);
    final weightTotal = book.sharedBusiness
        ? book.owners.fold<int>(0, (t, o) => t + o.weight)
        : 2;
    final capital = unit * weightTotal;
    if (book.sharedBusiness) {
      // ADR 2026-09-09c §4: a partner's opening contribution posts to their
      // Partner Current A/c and never to a Capital account — the S0.6b
      // owner-contributions row, signed the way that screen signs it (−).
      final balances = <String, int>{cash: _rupees(capital)};
      for (final o in book.owners) {
        final account = partners.firstWhere(
          (a) => a.name == LocalLedger.partnerCurrentAccountName(o.name),
        );
        balances[account.id] = -_rupees(unit * o.weight);
      }
      await ledger.openingBalances(bookId, balances: balances);
    } else {
      // ADR 2026-09-13 §4: capital introduced is an ordinary Money in from
      // Opening Balance / Capital.
      await _in(
        cash,
        await _systemAccount(SystemRole.openingBalance),
        capital,
        0,
      );
    }
    final bank = await _add(
      words.bank,
      AccountClass.money,
      subtype: MoneySubtype.current,
    );
    final sales = await _add(words.sales, AccountClass.categoryIncome);
    final purchases = await _add(words.purchases, AccountClass.categoryExpense);
    final wages = await _add(words.wages, AccountClass.categoryExpense);
    final power = await _add(words.electricity, AccountClass.categoryExpense);

    await _move(cash, bank, capital * 6 ~/ 10, 1);
    await _out(bank, purchases, 10000 + _pick(1, 3) * 5000, 4);
    for (final (i, offset) in const [6, 13, 20, 33, 41, 52].indexed) {
      await _in(
        i.isEven ? bank : cash,
        sales,
        (3 + _pick(i + 2, 5)) * 5000,
        offset,
      );
    }
    await _out(bank, power, 2500, 15);
    await _out(cash, wages, 8000, 29);
    await _out(bank, purchases, 15000 + _pick(9, 3) * 5000, 35);
    await _out(bank, power, 3000, 45);
    await _out(cash, wages, 8000, 57);
    // One drawing per partner (02 §7.1 settlement route 1), or the owner's
    // own on a *Just me* business (ADR 2026-09-09b §3: Dr Drawings).
    final drawingDay = _day(55);
    if (drawingDay != null) {
      if (book.sharedBusiness) {
        for (final o in book.owners) {
          final account = partners.firstWhere(
            (a) => a.name == LocalLedger.partnerCurrentAccountName(o.name),
          );
          await ledger.partnerPayOut(
            bookId: bookId,
            partnerAccountId: account.id,
            fromAccountId: bank,
            paise: _rupees(2000 * o.weight),
            date: drawingDay,
          );
        }
      } else {
        await _out(bank, await _systemAccount(SystemRole.drawings), 10000, 55);
      }
    }
  }

  /// A personal, family or joint book: cash on hand, a bank account, money
  /// coming in and the household's spending. [scale] doubles a shared pool.
  ///
  /// No Money account ever closes a day below zero, for any seed: 02 §9 reads
  /// negative physical cash as *always a missing entry*, and a demo must not
  /// show a ledger that looks broken. Per unit of [scale], cash holds at
  /// least ₹10,000 after day 1 and is topped up by ₹10,000 from the bank on
  /// days 5 and 35, while it spends at most ₹10,500 before day 35 and ₹21,000
  /// in all; the bank holds at least ₹10,000 + ₹25,000 − ₹10,000 from day 5.
  /// F1-DEMO-15 reads every Money account's daily close to keep it so.
  Future<void> household(DemoWords words, {required int scale}) async {
    final cash = await _cash();
    final opening = (2 + seed % 3) * 10000 * scale;
    await ledger.openingBalances(bookId, balances: {cash: _rupees(opening)});
    final bank = await _add(
      words.bank,
      AccountClass.money,
      subtype: MoneySubtype.saving,
    );
    final income = await _add(words.income, AccountClass.categoryIncome);
    final groceries = await _add(words.groceries, AccountClass.categoryExpense);
    final power = await _add(words.electricity, AccountClass.categoryExpense);
    final fuel = await _add(words.fuel, AccountClass.categoryExpense);
    final medical = await _add(words.medical, AccountClass.categoryExpense);

    await _move(cash, bank, opening ~/ 2, 1);
    await _in(bank, income, 25000 * scale, 4);
    // Cash drawn from the bank for the month's spending, after each income.
    await _move(bank, cash, 10000 * scale, 5);
    await _in(bank, income, 25000 * scale, 34);
    await _move(bank, cash, 10000 * scale, 35);
    for (final (i, offset) in const [7, 21, 37, 51].indexed) {
      await _out(cash, groceries, (6 + _pick(i, 4)) * 500 * scale, offset);
    }
    await _out(bank, power, 2000 * scale, 12);
    await _out(bank, power, 2000 * scale, 42);
    await _out(cash, fuel, 1500 * scale, 17);
    await _out(cash, fuel, 1500 * scale, 47);
    await _out(bank, medical, 2500, 26);
  }

  /// A trust: weekly gollak counts recognised as donations and deposited,
  /// a couple of receipted donations, langar, a repair and an honorarium.
  ///
  /// As for a household, no Money account closes a day below zero (02 §9):
  /// cash opens at ₹10,000 and its lowest close is ₹2,000 (day 37, before
  /// the ₹11,000 donation on day 38); the bank opens at ₹20,000 so the
  /// ₹15,000 repair on day 30 never outruns the deposits; the gollak is
  /// emptied the same day it is counted.
  Future<void> trust(
    DemoPlannedBook book,
    DemoWords words, {
    required String countedBy,
  }) async {
    final chart = await _chart;
    final cash = await _cash();
    final gollak = chart
        .byClass(AccountClass.money)
        .firstWhere((a) => a.isCollection)
        .id;
    // The four category names createBook seeds for a trust (07 §3.1 step 3
    // 🔒), found by the seed's own names rather than by position.
    final seeded = LocalLedger.defaultCategorySeed(BookType.organization);
    String seededId(int i) =>
        chart.accounts.firstWhere((a) => a.name == seeded[i].name).id;
    final donations = seededId(0);
    final langar = seededId(1);
    final repair = seededId(2);
    final honorarium = seededId(3);

    final bank = await _add(
      words.bank,
      AccountClass.money,
      subtype: MoneySubtype.saving,
    );
    await ledger.openingBalances(
      bookId,
      balances: {cash: _rupees(10000), bank: _rupees(20000)},
    );

    for (final (i, offset) in const [6, 13, 20, 27, 34, 41, 48, 55].indexed) {
      final rupees = 2000 + _pick(i * 3, 6) * 500;
      final d = _day(offset);
      if (d == null) continue;
      final witness = book.witness;
      if (witness == null) {
        await _in(cash, donations, rupees, offset);
        continue;
      }
      // 02 §8.2: a collection count recognises the full counted amount as
      // income (Dr gollak · Cr Donation Income); the box then empties into
      // the bank by an ordinary Transfer before the next count.
      await ledger.recordCashCount(
        accountId: gollak,
        counted: Paise.rupees(rupees),
        date: d,
        sheet: _sheetFor(rupees),
        countedBy: countedBy,
        witness: witness,
        incomeAccountId: donations,
      );
      await _move(gollak, bank, rupees, offset);
    }
    await _in(cash, donations, 5000, 10);
    await _in(cash, donations, 11000, 38);
    for (final offset in const [9, 23, 37, 51]) {
      await _out(cash, langar, 3000, offset);
    }
    await _out(bank, repair, 15000, 30);
    await _out(cash, honorarium, 4000, 28);
    await _out(cash, honorarium, 4000, 57);
  }
}

/// The notes a box holding [rupees] (a multiple of ₹10) is counted in.
DenominationSheet _sheetFor(int rupees) {
  var left = rupees;
  final notes = <int, int>{};
  for (final value in const [500, 200, 100, 50, 20, 10]) {
    final n = left ~/ value;
    if (n > 0) {
      notes[value] = n;
      left -= n * value;
    }
  }
  return DenominationSheet(notes: notes);
}
