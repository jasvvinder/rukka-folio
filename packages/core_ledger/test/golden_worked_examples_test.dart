// Suite A — golden fixtures (CLAUDE.md § Accounting authority, 09 §2 A).
//
// Replays every voucher of docs/reference/worked-examples/*.md (five documents, eight
// books) through the engine and asserts, per worked-examples/README.md §2:
//   • every ledger row's running balance and side, and every closing c/f;
//   • every trial-balance row and both totals; every book balances alone;
//   • each Due to/from pair whose both sides are in the package nets to zero.
// It compares on engine class (README §1), never on the Debtor/Creditor label.
//
// ⚠️ The documents are pending bookkeeper sign-off; until then this test is the
// engine's proof against the reference as it stands. Test code may read files —
// the purity rule (CLAUDE.md rule 3) binds lib/, not test/.
import 'dart:io';

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

const _dir = '../../docs/reference/worked-examples';
const _files = [
  'individual-rahul-sharma.md',
  'business-sharma-textile.md',
  'trust-singh-sabha-gurudwara.md',
  'joint-family-sharma.md',
  'joint-business-partnership.md',
];

void main() {
  final books = <FixtureBook>[];
  for (final f in _files) {
    books.addAll(parseFixtureFile(File('$_dir/$f').readAsStringSync(), f));
  }

  test('the package holds eight books and 185 vouchers', () {
    expect(books.length, 8);
    expect(books.fold<int>(0, (n, b) => n + b.vouchers.length), 185);
  });

  final replayed = <String, ReplayedBook>{};

  for (final fixture in books) {
    group(fixture.title, () {
      late ReplayedBook r;
      setUpAll(() {
        r = replay(fixture);
        replayed[fixture.title] = r;
      });

      test('nothing is quarantined', () {
        expect(r.state.quarantined, isEmpty);
      });

      test('Opening Balance / Capital absorbs the openings exactly', () {
        final ob = fixture.accounts.singleWhere((a) => a.isOpeningBalance);
        expect(r.state.balances[r.ids[ob.name]!], ob.opening);
      });

      test('every ledger row: running balance and side; closing c/f', () {
        for (final ledger in fixture.ledgers) {
          final id = r.ids[ledger.account];
          expect(
            id,
            isNotNull,
            reason: 'ledger "${ledger.account}" is not in the chart',
          );
          // 02 §4 posts openings as adjustments dated 1 April; the ledger image shows them
          // as the b/f row, not as vouchers — so they are stripped before the row compare.
          final rows = statement(
            r.state,
            id!,
          ).where((row) => !row.entryId.startsWith('open:')).toList();
          expect(
            rows.length,
            ledger.rows.length,
            reason: '${ledger.account}: row count',
          );
          for (var i = 0; i < rows.length; i++) {
            final want = ledger.rows[i];
            final got = rows[i];
            expect(
              got.entryId,
              r.voucherEntryIds[want.voucher],
              reason: '${ledger.account} row $i voucher',
            );
            expect(
              got.dr ?? Paise.zero,
              want.dr,
              reason: '${ledger.account} row $i (${want.voucher}) Dr',
            );
            expect(
              got.cr ?? Paise.zero,
              want.cr,
              reason: '${ledger.account} row $i (${want.voucher}) Cr',
            );
            expect(
              got.running,
              want.running,
              reason: '${ledger.account} row $i (${want.voucher}) running',
            );
          }
          expect(
            r.state.balances[id],
            ledger.closing,
            reason: '${ledger.account} closing c/f',
          );
        }
      });

      test('trial balance rows and totals', () {
        final tb = trialBalance(r.state, r.chart);
        final got = {
          for (final row in tb.rows)
            r.names[row.accountId]!: (
              dr: row.dr ?? Paise.zero,
              cr: row.cr ?? Paise.zero,
            ),
        };
        final want = {
          for (final row in fixture.trialBalance)
            row.account: (dr: row.dr, cr: row.cr),
        };
        expect(got, want);
        expect(tb.totalDr, fixture.tbTotal);
        expect(tb.totalCr, fixture.tbTotal);
        expect(tb.isBalanced, isTrue);
        expect(r.state.balances.isBalanced, isTrue);
      });
    });
  }

  test('Family Reconciliation: the three pairs present in the package net to zero (02 §6)', () {
    ReplayedBook byTitle(String needle) =>
        replayed.values.singleWhere((b) => b.title.contains(needle));
    final joint = byTitle('Sharma Joint Family Book');
    final agri = byTitle('Agriculture Business Book');
    final store = byTitle('Sharma Super Store Book');
    final pankaj = byTitle('Pankaj Sharma Sub-family');
    final pairs = [
      InterBookPair(
        a: joint.state,
        accountA: joint.ids['Agriculture Business (family book)']!,
        b: agri.state,
        accountB: agri.ids['Joint Family (common pool)']!,
      ),
      InterBookPair(
        a: joint.state,
        accountA: joint.ids['Sharma Super Store (family book)']!,
        b: store.state,
        accountB: store.ids['Joint Family (common pool)']!,
      ),
      InterBookPair(
        a: joint.state,
        accountA: joint.ids['Pankaj Sub-family (family book)']!,
        b: pankaj.state,
        accountB: pankaj.ids['Joint Family (common pool)']!,
      ),
    ];
    final result = InterBook.reconcile(pairs);
    expect(result.map((p) => p.net), everyElement(Paise.zero));
    expect(
      joint.state.balances[joint.ids['Agriculture Business (family book)']!],
      -Paise.rupees(400000),
    );
    expect(
      joint.state.balances[joint.ids['Sharma Super Store (family book)']!],
      -Paise.rupees(180000),
    );
    expect(
      joint.state.balances[joint.ids['Pankaj Sub-family (family book)']!],
      Paise.rupees(200000),
    );
  });

  test('every voucher is one entry that passes the universal invariants', () {
    for (final r in replayed.values) {
      for (final e in r.entries) {
        expect(
          checkUniversalInvariants(e, r.chart),
          isEmpty,
          reason: '${r.title} ${e.id}',
        );
      }
    }
  });
}

// ─── replay ──────────────────────────────────────────────────────────────────

class ReplayedBook {
  ReplayedBook(
    this.title,
    this.chart,
    this.state,
    this.ids,
    this.names,
    this.voucherEntryIds,
    this.entries,
  );
  final String title;
  final Chart chart;
  final LedgerState state;
  final Map<String, String> ids; // account name → id
  final Map<String, String> names; // id → account name
  final Map<String, String> voucherEntryIds; // voucher → entry id
  final List<Entry> entries;
}

ReplayedBook replay(FixtureBook fixture) {
  final bookId = fixture.title.hashCode.toRadixString(16);
  final ids = <String, String>{};
  final names = <String, String>{};
  final accounts = <Account>[];
  var order = 0;
  for (final a in fixture.accounts) {
    final id = '$bookId:${order.toString().padLeft(2, '0')}';
    ids[a.name] = id;
    names[id] = a.name;
    accounts.add(
      Account(
        id: id,
        bookId: bookId,
        name: a.name,
        accountClass: a.accountClass,
        subtype: a.subtype,
        systemRole: a.isOpeningBalance
            ? SystemRole.openingBalance
            : (a.accountClass == AccountClass.equitySystem &&
                      a.label == 'Interbook'
                  ? SystemRole.dueToFrom
                  : null),
        createdOrder: order++,
      ),
    );
  }
  final chart = Chart(bookId: bookId, accounts: accounts);
  final openingAccount = accounts.singleWhere(
    (a) => a.systemRole == SystemRole.openingBalance,
  );

  var hlc = 1;
  final entries = <Entry>[];
  final voucherEntryIds = <String, String>{};
  Entry make(String id, LocalDate date, EntryKind kind, List<Line> lines) =>
      Entry(
        id: id,
        bookId: bookId,
        kind: kind,
        status: EntryStatus.posted,
        reviewRequired: false,
        accountingDate: date,
        lines: lines,
        createdByUser: 'fixture',
        createdByDevice: 'fixture',
        hlc: Hlc(hlc++),
      );

  // 02 §4: each opening balance posts one adjustment against Opening Balance.
  for (final a in fixture.accounts) {
    if (a.isOpeningBalance || a.opening.isZero) continue;
    final acct = chart.account(ids[a.name]!);
    entries.add(
      make(
        'open:${a.name}',
        LocalDate(2026, 4, 1),
        EntryKind.adjustment,
        Verbs.openingBalance(
          account: acct,
          balance: a.opening,
          openingAccount: openingAccount,
        ),
      ),
    );
  }

  // Vouchers: rows sharing an id form one multi-line entry (standards §8).
  final grouped = <String, List<FixtureVoucherRow>>{};
  for (final v in fixture.vouchers) {
    grouped.putIfAbsent(v.voucher, () => []).add(v);
  }
  for (final MapEntry(key: voucher, value: rows) in grouped.entries) {
    final lines = <Line>[
      for (final row in rows) Line(accountId: ids[row.dr]!, amount: row.amount),
      for (final row in rows)
        Line(accountId: ids[row.cr]!, amount: -row.amount),
    ];
    // Kind is presentation for the fixture (balances never depend on it); infer loosely.
    final drClass = chart.account(ids[rows.first.dr]!).accountClass;
    final crClass = chart.account(ids[rows.first.cr]!).accountClass;
    final kind = switch ((drClass, crClass)) {
      (AccountClass.money, AccountClass.money) => EntryKind.transfer,
      (AccountClass.money, _) => EntryKind.moneyIn,
      (_, AccountClass.money) => EntryKind.moneyOut,
      (AccountClass.party, _) => EntryKind.gaveCredit,
      (_, AccountClass.party) => EntryKind.tookCredit,
      _ => EntryKind.adjustment,
    };
    final e = make(voucher, rows.first.date, kind, lines);
    entries.add(e);
    voucherEntryIds[voucher] = e.id;
  }

  final state = project(entries, chart);
  return ReplayedBook(
    fixture.title,
    chart,
    state,
    ids,
    names,
    voucherEntryIds,
    entries,
  );
}

// ─── fixture model ───────────────────────────────────────────────────────────

class FixtureAccount {
  FixtureAccount(this.name, this.label, this.opening);
  final String name;
  final String label;
  final Paise opening; // signed: Dr +, Cr −

  bool get isOpeningBalance => name.startsWith('Opening Balance');

  /// README §1 class mapping: labels are for the bookkeeper; the engine has classes.
  AccountClass get accountClass => switch (label.split(' ').first) {
    'Money' => AccountClass.money,
    'Debtor' || 'Creditor' => AccountClass.party,
    'Advance' => AccountClass.advance,
    'Partner' => AccountClass.partner,
    'Expense' => AccountClass.categoryExpense,
    'Income' => AccountClass.categoryIncome,
    'Equity' || 'Interbook' => AccountClass.equitySystem,
    _ => throw StateError('unknown label "$label" for $name'),
  };

  MoneySubtype? get subtype {
    if (accountClass != AccountClass.money) return null;
    if (label.contains('CC')) return MoneySubtype.cc;
    // ⚠️ "Gollak Cash A/c" in the trust example is the box *after* emptying into the
    // cash drawer (its vouchers pay expenses from it), i.e. plain cash — the example
    // predates the 2–3 Sep 2026 gollak ADRs. Flagged to the owner in CHANGELOG.
    if (name.contains('Cash')) return MoneySubtype.cash;
    return MoneySubtype.current;
  }
}

class FixtureVoucherRow {
  FixtureVoucherRow(this.date, this.voucher, this.dr, this.cr, this.amount);
  final LocalDate date;
  final String voucher;
  final String dr;
  final String cr;
  final Paise amount;
}

class FixtureLedgerRow {
  FixtureLedgerRow(this.voucher, this.dr, this.cr, this.running);
  final String voucher;
  final Paise dr;
  final Paise cr;
  final Paise running; // signed
}

class FixtureLedger {
  FixtureLedger(this.account);
  final String account;
  final rows = <FixtureLedgerRow>[];
  Paise closing = Paise.zero;
}

class FixtureTbRow {
  FixtureTbRow(this.account, this.dr, this.cr);
  final String account;
  final Paise dr;
  final Paise cr;
}

class FixtureBook {
  FixtureBook(this.title);
  final String title;
  final accounts = <FixtureAccount>[];
  final vouchers = <FixtureVoucherRow>[];
  final ledgers = <FixtureLedger>[];
  final trialBalance = <FixtureTbRow>[];
  Paise tbTotal = Paise.zero;
}

// ─── parser ──────────────────────────────────────────────────────────────────

List<FixtureBook> parseFixtureFile(String text, String fileName) {
  final lines = text.split('\n');
  final books = <FixtureBook>[];
  FixtureBook? book;
  var section = 0;
  FixtureLedger? ledger;

  final multi = lines.any((l) => l.startsWith('# Book '));
  if (!multi) {
    book = FixtureBook(lines.first.replaceFirst(RegExp(r'^# '), '').trim());
    books.add(book);
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.startsWith('# Book ')) {
      book = FixtureBook(line.substring(2).trim());
      books.add(book);
      section = 0;
      ledger = null;
      continue;
    }
    if (book == null) continue;
    final sec = RegExp(r'^## (\d)\.').firstMatch(line);
    if (sec != null) {
      section = int.parse(sec.group(1)!);
      ledger = null;
      continue;
    }
    switch (section) {
      case 1:
        final m = RegExp(r'^\| *\d+ *\| (.+?) \| (.+?) \| (.+?) \|$')
            .firstMatch(line);
        if (m != null) {
          book.accounts.add(
            FixtureAccount(
              m.group(1)!.trim(),
              m.group(2)!.trim(),
              _signed(m.group(3)!),
            ),
          );
        }
      case 2:
        final m = RegExp(
          r'^\| (\d{2} \w{3} \d{4})<br><em>([A-Z]+-\d+)</em> \| .+? \| (.+?) \| (.+?) \| ([\d,]+) \|$',
        ).firstMatch(line);
        if (m != null) {
          book.vouchers.add(
            FixtureVoucherRow(
              _date(m.group(1)!),
              m.group(2)!,
              m.group(3)!.trim(),
              m.group(4)!.trim(),
              _rupees(m.group(5)!),
            ),
          );
        }
      case 3:
        if (line.startsWith('### ')) {
          ledger = FixtureLedger(line.substring(4).trim());
          book.ledgers.add(ledger);
          continue;
        }
        if (ledger == null) continue;
        final row = RegExp(
          r'^\| \d{2} \w{3} \d{4}<br><em>([A-Z]+-\d+)</em> \| .+? \| (—|[\d,]+) \| (—|[\d,]+) \| (—|[\d,]+) (Dr|Cr) \|$',
        ).firstMatch(line);
        if (row != null) {
          ledger.rows.add(
            FixtureLedgerRow(
              row.group(1)!,
              _rupees(row.group(2)!),
              _rupees(row.group(3)!),
              _signed('${row.group(4)} ${row.group(5)}'),
            ),
          );
          continue;
        }
        final close = RegExp(
          r'^\| \*\*.+?\*\* \| \*\*Closing balance c/f\*\* \| — \| — \| \*\*(—|[\d,]+) (Dr|Cr)\*\* \|$',
        ).firstMatch(line);
        if (close != null) {
          ledger.closing = _signed('${close.group(1)} ${close.group(2)}');
        }
      case 4:
        final total = RegExp(
          r'^\| \*\*TOTALS\*\* \| \*\*([\d,]+)\*\* \| \*\*([\d,]+)\*\* \|$',
        ).firstMatch(line);
        if (total != null) {
          if (total.group(1) != total.group(2)) {
            throw StateError('$fileName: TB columns differ as printed');
          }
          book.tbTotal = _rupees(total.group(1)!);
          continue;
        }
        final m = RegExp(r'^\| (.+?) \| (—|[\d,]+) \| (—|[\d,]+) \|$')
            .firstMatch(line);
        if (m != null &&
            !m.group(1)!.startsWith('Account') &&
            !m.group(1)!.startsWith('---')) {
          book.trialBalance.add(
            FixtureTbRow(
              m.group(1)!.trim(),
              _rupees(m.group(2)!),
              _rupees(m.group(3)!),
            ),
          );
        }
      default:
        break;
    }
  }
  return books;
}

/// "1,09,400" (Indian grouping) or "—" → whole rupees as paise.
Paise _rupees(String s) {
  final t = s.trim();
  if (t == '—' || t.isEmpty) return Paise.zero;
  return Paise.rupees(int.parse(t.replaceAll(',', '')));
}

/// "85,000 Dr" → +, "50,000 Cr" → −, "—" / "— Cr" → 0.
Paise _signed(String s) {
  final t = s.trim();
  if (t == '—') return Paise.zero;
  final m = RegExp(r'^(—|[\d,]+) (Dr|Cr)$').firstMatch(t);
  if (m == null) throw FormatException('balance cell "$s"');
  final v = _rupees(m.group(1)!);
  return m.group(2) == 'Dr' ? v : -v;
}

const _months = {
  'Jan': 1,
  'Feb': 2,
  'Mar': 3,
  'Apr': 4,
  'May': 5,
  'Jun': 6,
  'Jul': 7,
  'Aug': 8,
  'Sep': 9,
  'Oct': 10,
  'Nov': 11,
  'Dec': 12,
};

LocalDate _date(String s) {
  final p = s.split(' ');
  return LocalDate(int.parse(p[2]), _months[p[1]]!, int.parse(p[0]));
}
