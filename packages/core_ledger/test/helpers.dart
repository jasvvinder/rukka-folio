// Shared builders for suite A (09 §2 A). Synthetic data only — never real entries.
// Test code may read files, the clock and dart:math — the purity rule (CLAUDE.md rule 3)
// binds lib/, not test/.
import 'dart:io';
import 'dart:math';

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

/// The repository root (the directory holding CLAUDE.md), whether `dart test` runs from the
/// package or from the workspace root (ADR 2026-09-05i §9).
String workspaceRoot() {
  var d = Directory.current.absolute;
  while (!File('${d.path}/CLAUDE.md').existsSync()) {
    if (d.parent.path == d.path) {
      throw StateError(
        'not inside the rukka-folio repository: ${Directory.current.path}',
      );
    }
    d = d.parent;
  }
  return d.path;
}

/// `test/regress/seeds.txt`, relative to this package (ADR 2026-09-05i §5).
String get seedsFile =>
    '${workspaceRoot()}/packages/core_ledger/test/regress/seeds.txt';

/// Seeds recorded for [testId] in the regression file: `<test-id> <seed>` per line, `#` comments.
List<int> regressionSeeds(String testId) {
  final f = File(seedsFile);
  if (!f.existsSync()) return const [];
  final out = <int>[];
  for (final raw in f.readAsLinesSync()) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0] == testId) {
      final seed = int.tryParse(parts[1]);
      if (seed == null) {
        throw FormatException('bad seed line in seeds.txt: $raw');
      }
      out.add(seed);
    }
  }
  return out;
}

/// The fresh seed for this run: `PROPTEST_SEED` when set, else drawn from the clock so every
/// run explores new inputs. Always printed in a failure (ADR 2026-09-05i §5).
int freshSeed() {
  final pinned = int.tryParse(Platform.environment['PROPTEST_SEED'] ?? '');
  return pinned ?? DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
}

/// Runs [body] once per recorded regression seed for [testId], then once with [freshSeed].
/// A failure re-throws with the seed and the replay command, so the case can be pinned
/// (`PROPTEST_SEED=<seed>`) and then checked into `test/regress/seeds.txt` permanently.
void forEachSeed(String testId, void Function(Random rng, int seed) body) {
  final seeds = [...regressionSeeds(testId), freshSeed()];
  for (final seed in seeds) {
    try {
      body(Random(seed), seed);
    } on TestFailure catch (e) {
      throw TestFailure(
        '${e.message}\n\n$testId failed with seed $seed.\n'
        '  replay : PROPTEST_SEED=$seed dart test packages/core_ledger\n'
        '  pin    : add "$testId $seed   # ${'<date> — <why>'}" to test/regress/seeds.txt',
      );
    }
  }
}

/// A book under test: a chart of accounts plus a monotonically increasing HLC
/// so entries are created in causal order without touching any clock.
class TestBook {
  TestBook(this.bookId, {this.bookType = BookType.family});

  final String bookId;
  final BookType bookType;
  final Map<String, Account> _accounts = {};
  int _order = 0;
  int _hlc = 1000;

  Chart get chart => Chart(bookId: bookId, accounts: _accounts.values.toList());

  Hlc nextHlc() => Hlc(_hlc++);

  Account acct(
    String name,
    AccountClass accountClass, {
    MoneySubtype? subtype,
    SystemRole? systemRole,
    String? memberId,
    String? counterpartBookId,
  }) {
    final id =
        '$bookId:${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}';
    final a = Account(
      id: id,
      bookId: bookId,
      name: name,
      accountClass: accountClass,
      subtype: subtype,
      systemRole: systemRole,
      memberId: memberId,
      counterpartBookId: counterpartBookId,
      createdOrder: _order++,
    );
    _accounts[id] = a;
    return a;
  }

  Account money(String name, {MoneySubtype subtype = MoneySubtype.saving}) =>
      acct(name, AccountClass.money, subtype: subtype);
  Account cash(String name) =>
      acct(name, AccountClass.money, subtype: MoneySubtype.cash);
  Account party(String name) => acct(name, AccountClass.party);
  Account income(String name) => acct(name, AccountClass.categoryIncome);
  Account expense(String name) => acct(name, AccountClass.categoryExpense);
  Account advance(String member) =>
      acct('Advance – $member', AccountClass.advance, memberId: member);
  Account partner(String owner) => acct(
    '$owner — Partner Current A/c',
    AccountClass.partner,
    memberId: owner,
  );
  Account openingBalance() => acct(
    'Opening Balance',
    AccountClass.equitySystem,
    systemRole: SystemRole.openingBalance,
  );
  Account adjustments() => acct(
    'Adjustments',
    AccountClass.equitySystem,
    systemRole: SystemRole.adjustments,
  );
  Account suspense() => acct(
    'Suspense',
    AccountClass.equitySystem,
    systemRole: SystemRole.suspense,
  );
  Account profitDistributed() => acct(
    'Profit Distributed',
    AccountClass.equitySystem,
    systemRole: SystemRole.profitDistributed,
  );
  Account dueToFrom(String otherBook) => acct(
    'Due to/from $otherBook',
    AccountClass.equitySystem,
    systemRole: SystemRole.dueToFrom,
    counterpartBookId: otherBook,
  );

  /// A posted entry with the given lines. Defaults are the common case: not
  /// flagged, authored by `u1` on `d1`, dated [date] (default 2026-05-10).
  Entry entry(
    List<Line> lines, {
    String? id,
    EntryKind kind = EntryKind.moneyOut,
    EntryStatus status = EntryStatus.posted,
    LocalDate? date,
    bool reviewRequired = false,
    Paise? reviewLimit,
    String? reviewApprover,
    EntryRefs refs = const EntryRefs(),
    String createdByUser = 'u1',
    String createdByDevice = 'd1',
    String? note,
    Hlc? hlc,
    String? partyId,
    String? advanceId,
  }) {
    final h = hlc ?? nextHlc();
    return Entry(
      id: id ?? 'e${h.raw}',
      bookId: bookId,
      kind: kind,
      status: status,
      reviewRequired: reviewRequired,
      reviewLimitPaise: reviewLimit,
      reviewApprover: reviewApprover,
      accountingDate: date ?? LocalDate(2026, 5, 10),
      lines: lines,
      refs: refs,
      note: note,
      createdByUser: createdByUser,
      createdByDevice: createdByDevice,
      hlc: h,
      partyId: partyId,
      advanceId: advanceId,
    );
  }
}

Paise rs(int rupees) => Paise.rupees(rupees);
Line dr(Account a, Paise p) => Line(accountId: a.id, amount: p);
Line cr(Account a, Paise p) => Line(accountId: a.id, amount: -p);
LocalDate d(int y, int m, int day) => LocalDate(y, m, day);
