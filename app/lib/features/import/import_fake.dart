// In-memory [ImportSource] and [StatementFilePort] for tests and for driving
// S7 before the ledger lane lands (the `shared/seams/` fakes live in lib/ for
// the same reason).
//
// The fake does **not** re-decide anything the parser owns: `parse` runs the
// real `parseStatement`, so a screen green against this fake is green against
// the rule, not against a stub's opinion of it.
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';

import 'import_lines.dart';
import 'import_source.dart';
import 'parse/column_mapping.dart';
import 'parse/parsed_statement.dart';

/// An [ImportSource] over fixed A/Cs and an in-memory per-bank memory.
final class FakeImportSource implements ImportSource {
  /// Creates the fake.
  FakeImportSource({
    List<ImportAccount>? accounts,
    Map<String, ColumnMapping>? remembered,
    Set<LineIdentity>? alreadyImported,
    this.failAccounts = false,
    this.loadDelay,
  }) : accounts =
           accounts ??
           const [
             ImportAccount(
               id: 'bank-1',
               name: 'SBI Saving',
               bankKey: 'sbi',
               subtitle: 'Savings',
             ),
             ImportAccount(
               id: 'bank-2',
               name: 'HDFC Current',
               bankKey: 'hdfc',
               subtitle: 'Current',
             ),
           ],
       remembered = {...?remembered},
       _already = {...?alreadyImported};

  /// What [pickAccount] answers.
  List<ImportAccount> accounts;

  /// The per-bank memory, by `bankKey`.
  final Map<String, ColumnMapping> remembered;

  final Set<LineIdentity> _already;

  /// Makes [pickAccount] throw, for the error state.
  bool failAccounts;

  /// Delays [pickAccount], for the loading state.
  Duration? loadDelay;

  /// Every `(bankKey, mapping)` [rememberMapping] was called with, in order.
  final List<(String, ColumnMapping)> rememberedCalls = [];

  @override
  Future<List<ImportAccount>> pickAccount(String bookId) async {
    if (loadDelay != null) await Future<void>.delayed(loadDelay!);
    if (failAccounts) throw StateError('no accounts');
    return accounts;
  }

  @override
  Future<ColumnMapping?> rememberedMapping(String bankKey) async =>
      remembered[bankKey];

  @override
  Future<void> rememberMapping(String bankKey, ColumnMapping mapping) async {
    remembered[bankKey] = mapping.confirmed;
    rememberedCalls.add((bankKey, mapping.confirmed));
  }

  @override
  Future<Set<LineIdentity>> alreadyImported(String bookId) async => _already;

  /// Adds identities the book is to consider already imported.
  void addImported(Iterable<LineIdentity> identities) =>
      _already.addAll(identities);

  @override
  Future<StatementParseResult> parse({
    required Uint8List bytes,
    required String fileName,
    required String accountId,
    ColumnMapping? mapping,
    Set<LineIdentity> alreadyImported = const {},
  }) => parseOnDevice(
    bytes: bytes,
    fileName: fileName,
    accountId: accountId,
    mapping: mapping,
    alreadyImported: alreadyImported,
  );

  // ── S7.1, the import inbox ────────────────────────────────────────────────

  /// What `classify` answers the one question with, keyed by an **uppercase
  /// fragment** of the bank text: a learned rule, in the shape the real
  /// source's rule table has (07 §11 item 3 🔒).
  final Map<String, ImportCounterpart> rules = {};

  /// Auto-links, keyed by the parsed line's `rowIndex` — `Matched ✓`.
  final Map<int, ImportMatch> matches = {};

  /// Lines already sitting in the inbox from another A/C's import. A transfer
  /// pair is one line here and one in the statement being classified, because
  /// the opposite line always lives in **another own-account** (02 §10 🔒).
  final List<ImportLine> carried = [];

  /// The date window a transfer pair may straddle (02 §10 🔒 *amount equal,
  /// date within window*).
  int transferWindowDays = 3;

  /// What the one-question picker offers.
  List<ImportCounterpart> counterpartList = const [
    ImportCounterpart(id: 'cat-milk', name: 'Milk Expense'),
    ImportCounterpart(id: 'cat-salary', name: 'Salary Income'),
    ImportCounterpart(id: 'party-ramesh', name: 'Ramesh'),
    ImportCounterpart(id: 'bank-2', name: 'HDFC Current', isOwnMoney: true),
  ];

  /// Whether submitting posts. The real ledger source answers
  /// [ImportPostingBlocked] while `bank_text` has nowhere to land (02 §10 🔒).
  @override
  ImportPostingAvailability posting = const ImportPostingReady();

  /// Every rule the *Always? Yes* answer taught, in order.
  final List<ImportLine> taught = [];

  /// Every line that posted, in order — what a test asserts a single Transfer
  /// against.
  final List<FakePosting> postings = [];

  /// A/C balances the book would answer with: `accountId → epochDay → paise`.
  final Map<String, Map<int, int>> balances = {};

  var _seq = 0;

  /// Seeds [ledgerBalanceOn].
  void setBalance(String accountId, LocalDate date, int paise) =>
      (balances[accountId] ??= {})[date.toEpochDays()] = paise;

  @override
  Future<List<ImportLine>> classify({
    required String bookId,
    required ParsedStatement statement,
  }) async {
    final fresh = <ImportLine>[
      for (final (i, line) in statement.lines.indexed)
        _classifyOne(line, statement.accountId, i),
    ];
    final all = [...carried, ...fresh];
    return _pairTransfers(all);
  }

  ImportLine _classifyOne(ParsedLine line, String accountId, int i) {
    final id = '$accountId#${line.rowIndex}';
    final match = matches[line.rowIndex];
    if (match != null) {
      return ImportLine(
        id: id,
        parsed: line,
        accountId: accountId,
        state: ImportLineState.matched,
        match: match,
      );
    }
    final upper = line.bankText.toUpperCase();
    for (final MapEntry(key: fragment, value: account) in rules.entries) {
      if (!upper.contains(fragment.toUpperCase())) continue;
      return ImportLine(
        id: id,
        parsed: line,
        accountId: accountId,
        state: ImportLineState.suggested,
        suggestion: ImportSuggestion(
          accountId: account.id,
          accountName: account.name,
          fromRule: true,
        ),
      );
    }
    return ImportLine(
      id: id,
      parsed: line,
      accountId: accountId,
      state: ImportLineState.needsAnswer,
    );
  }

  /// Marks every pair of lines that are the same money moving between the
  /// user's own A/Cs: equal amount, opposite direction, within the window,
  /// and — the part that makes it a transfer at all — **different A/Cs**.
  List<ImportLine> _pairTransfers(List<ImportLine> lines) {
    final out = [...lines];
    final paired = <String>{};
    for (var i = 0; i < out.length; i++) {
      if (paired.contains(out[i].id)) continue;
      if (out[i].state == ImportLineState.matched) continue;
      for (var j = i + 1; j < out.length; j++) {
        final a = out[i];
        final b = out[j];
        if (paired.contains(b.id)) continue;
        if (b.state == ImportLineState.matched) continue;
        if (a.accountId == b.accountId) continue;
        if (a.parsed.paise != b.parsed.paise) continue;
        if (a.parsed.direction == b.parsed.direction) continue;
        final gap = (a.parsed.date.toEpochDays() - b.parsed.date.toEpochDays())
            .abs();
        if (gap > transferWindowDays) continue;
        out[i] = a.copyWith(
          state: ImportLineState.transfer,
          pairedLineId: b.id,
          clearSuggestion: true,
        );
        out[j] = b.copyWith(
          state: ImportLineState.transfer,
          pairedLineId: a.id,
          clearSuggestion: true,
        );
        paired
          ..add(a.id)
          ..add(b.id);
        break;
      }
    }
    return out;
  }

  @override
  Future<List<ImportCounterpart>> counterparts(String bookId) async =>
      counterpartList;

  @override
  Future<ImportCounterpart> createCounterpart(
    String bookId, {
    required String name,
  }) async {
    final created = ImportCounterpart(id: 'new-${++_seq}', name: name);
    counterpartList = [...counterpartList, created];
    return created;
  }

  @override
  Future<ImportLine> unlink(ImportLine line) async =>
      line.copyWith(state: ImportLineState.needsAnswer, clearMatch: true);

  @override
  Future<ImportLine> approveSuggestion(ImportLine line) async {
    final s = line.suggestion;
    if (s == null) return line;
    taught.add(line);
    return line.copyWith(
      state: ImportLineState.answered,
      counterpartId: s.accountId,
      counterpartName: s.accountName,
    );
  }

  @override
  Future<ImportLine> answer(
    ImportLine line,
    ImportCounterpart counterpart,
  ) async => line.copyWith(
    state: ImportLineState.answered,
    counterpartId: counterpart.id,
    counterpartName: counterpart.name,
    clearSuggestion: true,
    correctedFrom: line.suggestion?.accountName,
  );

  @override
  Future<void> teachRule(ImportLine line) async => taught.add(line);

  @override
  Future<ImportTransferPair> confirmTransfer(ImportLine line) async {
    final otherId = line.pairedLineId;
    final other = otherId == null
        ? null
        : carried.where((l) => l.id == otherId).firstOrNull;
    return ImportTransferPair(
      line: line.copyWith(
        state: ImportLineState.answered,
        counterpartId: other?.accountId ?? otherId,
        counterpartName: transferPartnerName,
      ),
      collapsedIds: [?otherId],
    );
  }

  /// What the surviving transfer row names as its other side.
  String transferPartnerName = 'HDFC Current';

  @override
  Future<ImportLine> toSuspense(ImportLine line) async => line.copyWith(
    state: ImportLineState.suspense,
    clearSuggestion: true,
    clearCounterpart: true,
  );

  @override
  Future<ImportLine> addNote(ImportLine line, String note) async =>
      line.copyWith(note: note);

  @override
  Future<List<ImportLineOutcome>> submit(List<ImportLine> lines) async {
    if (posting case ImportPostingBlocked(:final reason)) {
      return [
        for (final l in lines) ImportPostingUnavailable(l.id, reason: reason),
      ];
    }
    final out = <ImportLineOutcome>[];
    for (final l in lines) {
      switch (l.state) {
        case ImportLineState.matched:
          out.add(ImportLinked(l.id, entryId: l.match?.entryId ?? 'e-linked'));
        case ImportLineState.suspense:
        case ImportLineState.answered:
          final transfer =
              l.state == ImportLineState.answered && l.pairedLineId != null;
          final entryId = 'e-${++_seq}';
          postings.add(
            FakePosting(
              lineId: l.id,
              entryId: entryId,
              counterpartId: l.counterpartId,
              paise: l.parsed.paise,
              direction: l.parsed.direction,
              bankText: l.parsed.bankText,
              note: l.note,
              suspense: l.state == ImportLineState.suspense,
              transfer: transfer,
            ),
          );
          out.add(ImportPosted(l.id, entryId: entryId, transfer: transfer));
        case ImportLineState.needsAnswer:
        case ImportLineState.suggested:
        case ImportLineState.transfer:
          out.add(ImportLeftInInbox(l.id));
      }
    }
    return out;
  }

  @override
  Future<int?> ledgerBalanceOn(String accountId, LocalDate date) async =>
      balances[accountId]?[date.toEpochDays()];
}

/// One posting the fake recorded — enough for a test to say *exactly one
/// Transfer*, and to prove `bank_text` travelled with it (02 §10 🔒).
final class FakePosting {
  /// Creates the record.
  const FakePosting({
    required this.lineId,
    required this.entryId,
    required this.paise,
    required this.direction,
    required this.bankText,
    this.counterpartId,
    this.note,
    this.suspense = false,
    this.transfer = false,
  });

  /// The inbox line it came from.
  final String lineId;

  /// The entry it created.
  final String entryId;

  /// The counterpart the one question was answered with.
  final String? counterpartId;

  /// Integer paise, magnitude.
  final int paise;

  /// Money in or money out, bank vocabulary.
  final BankDirection direction;

  /// The statement's own words, verbatim.
  final String bankText;

  /// The user's own words, when they added any.
  final String? note;

  /// Posted to Suspense (02 §10 🔒).
  final bool suspense;

  /// One Transfer for a pair, not two entries (02 §10 🔒).
  final bool transfer;
}

/// A [StatementFilePort] that hands back a queued file (or a cancel).
final class FakeStatementFilePort implements StatementFilePort {
  /// Creates the port. With no [file] the first pick is a **cancel**, which
  /// is not an error.
  FakeStatementFilePort({this.file});

  /// What the next pick returns; null means the user backed out.
  PickedStatementFile? file;

  /// How many times the picker was opened.
  int picks = 0;

  @override
  Future<PickedStatementFile?> pickStatementFile() async {
    picks++;
    return file;
  }
}
