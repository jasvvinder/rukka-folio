// Shared fixtures for suite E (client half). Synthetic data only — the Sharma
// family, +91 99999 numbers, never a real entry (CLAUDE.md rule 4).
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';

/// A toy 32-bit FNV-1a — the mirror only needs *a* deterministic hash here;
/// `core_crypto` supplies BLAKE2b at M3.
Uint8List toyHash(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return Uint8List.fromList([
    h >> 24 & 0xff,
    h >> 16 & 0xff,
    h >> 8 & 0xff,
    h & 0xff,
  ]);
}

/// Opens a fresh in-memory database, migrated and quick-checked.
Future<LedgerDatabase> openMemory() async {
  // Each test database has its own executor; the warning is about sharing one.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final r = await openLedgerDatabase(NativeDatabase.memory());
  return (r as Opened).db;
}

/// One synthetic book with its chart — the Sharma family cash book.
final class Fixture {
  Fixture({this.bookId = 'b1'});

  final String bookId;
  final String device = 'dev-a';
  int _seq = 0;
  int _hlc = 1000;

  Hlc nextHlc() => Hlc(_hlc++);

  /// Takes the next `author_seq` without storing anything — the envelope that
  /// should carry it is then "missing" until stored with [eventEnvelope]'s
  /// `authorSeq`, which is how tests open a real author gap (ADR 05b §3).
  int reserveSeq() => ++_seq;

  late final config = BookConfig(
    id: bookId,
    tenantId: 't1',
    type: BookType.family,
    name: 'Sharma family',
  );

  late final cash = _acct(
    'cash',
    'Cash',
    AccountClass.money,
    0,
    MoneySubtype.cash,
  );
  late final bank = _acct(
    'bank',
    'SBI Savings',
    AccountClass.money,
    1,
    MoneySubtype.saving,
  );
  late final salary = _acct('salary', 'Salary', AccountClass.categoryIncome, 2);
  late final kirana = _acct(
    'kirana',
    'Kirana',
    AccountClass.categoryExpense,
    3,
  );
  late final verma = _acct('verma', 'Verma Dairy', AccountClass.party, 4);
  late final opening = Account(
    id: '$bookId:opening',
    bookId: bookId,
    name: 'Opening Balance',
    accountClass: AccountClass.equitySystem,
    systemRole: SystemRole.openingBalance,
    createdOrder: 5,
  );

  Account _acct(
    String id,
    String name,
    AccountClass c,
    int order, [
    MoneySubtype? sub,
  ]) => Account(
    id: '$bookId:$id',
    bookId: bookId,
    name: name,
    accountClass: c,
    subtype: sub,
    createdOrder: order,
  );

  List<Account> get accounts => [cash, bank, salary, kirana, verma, opening];

  Chart get chart => Chart(bookId: bookId, accounts: accounts);

  Entry entry(
    String id,
    List<Line> lines, {
    required LocalDate date,
    EntryKind kind = EntryKind.moneyOut,
    EntryStatus status = EntryStatus.posted,
    bool reviewRequired = false,
    String? reviewApprover,
    EntryRefs refs = const EntryRefs(),
    String user = 'ramesh',
    Map<String, Object?> extra = const {},
    Hlc? hlc,
    String? device,
  }) => Entry(
    id: id,
    bookId: bookId,
    kind: kind,
    status: status,
    reviewRequired: reviewRequired,
    reviewApprover: reviewApprover,
    reviewLimitPaise: reviewRequired ? const Paise.rupees(5000) : null,
    accountingDate: date,
    lines: lines,
    createdByUser: user,
    createdByDevice: device ?? this.device,
    hlc: hlc ?? nextHlc(),
    refs: refs,
    extra: extra,
  );

  /// The routing envelope around an object payload. Envelope ids differ from
  /// object ids on purpose (`env-…`), so tests catch any conflation.
  EnvelopeRecord envelope(
    String objectId,
    String objectType,
    Map<String, Object?> payload, {
    required int hlc,
    bool verified = true,
    Uint8List? blobHash,
    String? authorDevice,
    int? authorSeq,
  }) {
    final blob = encodeJsonPayload(payload);
    return EnvelopeRecord(
      envelopeId: 'env-$objectId',
      bookId: bookId,
      objectId: objectId,
      objectType: objectType,
      keyVersion: 1,
      hlc: hlc,
      authorDevice: authorDevice ?? device,
      authorSeq: authorSeq ?? ++_seq,
      blob: blob,
      blobHash: blobHash ?? toyHash(blob),
      verified: verified,
    );
  }

  EnvelopeRecord eventEnvelope(
    LedgerEvent e, {
    bool verified = true,
    Uint8List? blobHash,
    String? authorDevice,
    int? authorSeq,
  }) => envelope(
    e.id,
    objectTypeOf(e),
    encodeEvent(e),
    hlc: e.hlc.raw,
    verified: verified,
    blobHash: blobHash,
    authorDevice: authorDevice ?? e.authorDevice,
    authorSeq: authorSeq,
  );

  /// Config + accounts, the envelopes every book starts with.
  List<EnvelopeRecord> setupEnvelopes() => [
    envelope(bookId, 'book_config', config.toJson(), hlc: 1),
    for (final a in accounts)
      envelope(
        a.id,
        'account',
        AccountPayload(a).toJson(),
        hlc: 2 + a.createdOrder,
      ),
  ];

  /// A month of ordinary life: salary in, kirana out, dairy on credit, one
  /// over-limit payment flagged for Papa, Papa approves.
  List<LedgerEvent> ordinaryMonth() {
    final e1 = entry(
      'e1',
      Verbs.moneyIn(
        into: cash,
        from: salary,
        amount: const Paise.rupees(50000),
      ),
      date: LocalDate(2026, 4, 5),
      kind: EntryKind.moneyIn,
    );
    final e2 = entry(
      'e2',
      Verbs.moneyOut(
        from: cash,
        forWhat: kirana,
        amount: const Paise.rupees(1200),
      ),
      date: LocalDate(2026, 4, 6),
    );
    final e3 = entry(
      'e3',
      Verbs.tookCredit(
        fromWhom: verma,
        took: kirana,
        amount: const Paise.rupees(800),
      ),
      date: LocalDate(2026, 5, 1),
      kind: EntryKind.tookCredit,
    );
    final e4 = entry(
      'e4',
      Verbs.moneyOut(
        from: cash,
        forWhat: kirana,
        amount: const Paise.rupees(7000),
      ),
      date: LocalDate(2026, 5, 3),
      reviewRequired: true,
      reviewApprover: 'papa',
    );
    final d1 = ApprovalDecision(
      id: 'd1',
      bookId: bookId,
      entryId: 'e4',
      decision: Decision.approve,
      byUser: 'papa',
      hlc: nextHlc(),
    );
    return [e1, e2, e3, e4, d1];
  }
}

/// Stores every envelope through the mirror.
Future<void> storeAll(Mirror m, Iterable<EnvelopeRecord> envelopes) async {
  for (final e in envelopes) {
    await m.append(e);
  }
}

/// Mirror + Recompute over [db] with the test hash and the JSON opener.
(Mirror, Recompute) rig(LedgerDatabase db) {
  final m = Mirror(db, hasher: toyHash);
  return (m, Recompute(db, mirror: m, opener: const JsonPayloadOpener()));
}

/// Reads `books_p` for [bookId].
Future<BooksPData> bookRow(LedgerDatabase db, String bookId) =>
    (db.select(db.booksP)..where((t) => t.id.equals(bookId))).getSingle();

/// Balance in paise as stored, or null.
Future<int?> storedBalance(LedgerDatabase db, String accountId) async {
  final r = await (db.select(
    db.balances,
  )..where((t) => t.accountId.equals(accountId))).getSingleOrNull();
  return r?.balancePaise;
}

/// Keeps the drift `Value` import used for tests that build companions.
const absent = Value<Object?>.absent();
