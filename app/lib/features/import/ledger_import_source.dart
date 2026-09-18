// [ImportSource] over the real book — the reads are real; **nothing posts**.
//
// 🔒 **Why nothing posts.** 02 §10 🔒 requires the statement's own line stored
// on the envelope as `bank_text`, **verbatim and separate from `note`**:
// immutable evidence, never edited, never cleaned up, used for matching and
// for the learned rules. The engine has no such field — `Entry` carries only
// `note` (`packages/core_ledger/lib/src/entry.dart`), and `LocalLedger`'s
// `moneyIn` / `moneyOut` / `transfer` take only `note:`. Posting an import
// line today would mean posting it **stripped of its evidence**, which is the
// one thing 02 §10 forbids. So [submit] answers
// [ImportPostingUnavailable] for every line — a typed outcome, never a throw
// and never a silent half-posting — and S7.1 draws its primary action
// disabled **with that reason in one plain sentence** plus *Keep for later*
// (07 §1 rule 6). The day the ruling lands, posting is one adapter method:
// see the lane report for the exact facade call each state needs.
//
// Everything else here is the real ledger: the bank A/Cs come from
// `watchAccounts`, and S7.2's two balances from `watchStatement`, which sums
// an A/C's lines up to a date. No writes, so nothing this class does can
// corrupt a book while the ruling is open.
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';

import '../../shared/ledger/local_ledger.dart';
import 'import_lines.dart';
import 'import_source.dart';
import 'parse/column_mapping.dart';
import 'parse/parsed_statement.dart';
import 'parse/statement_parser.dart';

/// The real [ImportSource]: reads from [LocalLedger], posts nothing.
final class LedgerImportSource implements ImportSource {
  /// Creates the source over [ledger].
  LedgerImportSource(this.ledger);

  /// The facade. Read-only from here.
  final LocalLedger ledger;

  /// Per-bank column memory (07 §11 item 1 🔒).
  ///
  /// In memory for now: the facade has no store for it, and `app/lib/shared`
  /// is another lane's directory. A mapping therefore survives the import but
  /// not the app — stated in the lane report as the follow-up.
  final Map<String, ColumnMapping> _mappings = {};

  @override
  Future<List<ImportAccount>> pickAccount(String bookId) async {
    final rows = await ledger.watchAccounts(bookId).first;
    return [
      for (final row in rows)
        if (!row.archived && _isBank(row.account))
          ImportAccount(
            id: row.account.id,
            name: row.account.name,
            bankKey: bankKeyOf(row.account.name),
            subtitle: null,
          ),
    ];
  }

  /// A statement is a bank's own book of the account, so only bank-shaped
  /// money A/Cs are candidates: cash and collection A/Cs are **counted**, not
  /// imported (02 §8.2).
  static bool _isBank(Account account) =>
      account.isMoney &&
      switch (account.subtype) {
        MoneySubtype.saving ||
        MoneySubtype.current ||
        MoneySubtype.od ||
        MoneySubtype.cc ||
        MoneySubtype.loan => true,
        MoneySubtype.cash ||
        MoneySubtype.cashCollection ||
        MoneySubtype.wallet ||
        null => false,
      };

  /// Which bank's shape a remembered mapping belongs to (07 §11 item 1 🔒 —
  /// per **bank**, not per A/C). Derived from the A/C's own name until the
  /// book carries a bank field: *SBI Saving* and *SBI Current* share `sbi`.
  static String bankKeyOf(String accountName) {
    final word = accountName.trim().split(RegExp(r'\s+')).firstOrNull ?? '';
    return word.toLowerCase();
  }

  @override
  Future<ColumnMapping?> rememberedMapping(String bankKey) async =>
      _mappings[bankKey];

  @override
  Future<void> rememberMapping(String bankKey, ColumnMapping mapping) async =>
      _mappings[bankKey] = mapping.confirmed;

  /// What the book has already imported.
  ///
  /// Empty today: an identity is `(A/C, date, amount, normalised text,
  /// per-file ordinal)` (02 §10 🔒) and the normalised text comes from
  /// `bank_text`, which the engine does not store — the same 🔒 blocker.
  /// Returning the empty set is the conservative answer: it can only ever
  /// show a line the user has seen before, never hide one they have not.
  /// When `bank_text` lands, this reads the posted lines' refs and builds
  /// identities with [identityOf] rather than a second copy of the rule.
  @override
  Future<Set<LineIdentity>> alreadyImported(String bookId) async => const {};

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

  // ── S7.1 ──────────────────────────────────────────────────────────────────

  /// Every line asks its one question.
  ///
  /// No `Matched ✓` and no `Suggested` yet: both read `bank_text` off posted
  /// entries — the auto-link to compare against, the rules to fire on — and
  /// that field does not exist. A line the app cannot classify is shown as
  /// `New`, which is the honest state: the user answers it themselves, and no
  /// wrong guess is put in front of them.
  @override
  Future<List<ImportLine>> classify({
    required String bookId,
    required ParsedStatement statement,
  }) async => [
    for (final line in statement.lines)
      ImportLine(
        id: '${statement.accountId}#${line.rowIndex}',
        parsed: line,
        accountId: statement.accountId,
        state: ImportLineState.needsAnswer,
      ),
  ];

  @override
  Future<List<ImportCounterpart>> counterparts(String bookId) async {
    final rows = await ledger.watchAccounts(bookId).first;
    return [
      for (final row in rows)
        if (!row.archived)
          ImportCounterpart(
            id: row.account.id,
            name: row.account.name,
            isOwnMoney: row.account.isMoney,
          ),
    ];
  }

  @override
  Future<ImportCounterpart> createCounterpart(
    String bookId, {
    required String name,
  }) async {
    // Creating an A/C is an ordinary write the engine already owns, and it
    // carries no `bank_text` — so inline-create works today even though the
    // line it will answer cannot post yet.
    final account = await ledger.addAccount(
      bookId,
      name: name,
      accountClass: AccountClass.categoryExpense,
    );
    return ImportCounterpart(id: account.id, name: account.name);
  }

  @override
  Future<ImportLine> unlink(ImportLine line) async =>
      line.copyWith(state: ImportLineState.needsAnswer, clearMatch: true);

  @override
  Future<ImportLine> approveSuggestion(ImportLine line) async {
    final s = line.suggestion;
    if (s == null) return line;
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

  /// The rule table is keyed by normalised `bank_text` (02 §10 🔒), so it
  /// cannot be written before that field exists. Teaching is accepted and
  /// dropped rather than refused: the user's *Always? Yes* is about the next
  /// import, and nothing is lost that was ever stored.
  @override
  Future<void> teachRule(ImportLine line) async {}

  @override
  Future<ImportTransferPair> confirmTransfer(ImportLine line) async =>
      ImportTransferPair(
        line: line.copyWith(state: ImportLineState.answered),
        collapsedIds: [?line.pairedLineId],
      );

  @override
  Future<ImportLine> toSuspense(ImportLine line) async => line.copyWith(
    state: ImportLineState.suspense,
    clearSuggestion: true,
    clearCounterpart: true,
  );

  @override
  Future<ImportLine> addNote(ImportLine line, String note) async =>
      line.copyWith(note: note);

  /// 🔒 Blocked while `bank_text` has nowhere to land (02 §10 🔒). Asked
  /// **before** the button is drawn, so S7.1 disables it with the reason
  /// rather than letting a tap fail.
  @override
  ImportPostingAvailability get posting => const ImportPostingBlocked(
    ImportUnavailableReason.bankTextHasNowhereToLand,
  );

  /// Never throws, never posts a line stripped of its `bank_text`, never
  /// leaves half an import behind: one stated outcome per line, and the
  /// inbox keeps everything.
  @override
  Future<List<ImportLineOutcome>> submit(List<ImportLine> lines) async => [
    for (final line in lines)
      ImportPostingUnavailable(
        line.id,
        reason: ImportUnavailableReason.bankTextHasNowhereToLand,
      ),
  ];

  /// The book's balance for [accountId] at the end of [date] — the A/C's own
  /// lines summed to that day, signed engine-side (+ = Dr), which for a bank
  /// A/C is how the bank prints it.
  @override
  Future<int?> ledgerBalanceOn(String accountId, LocalDate date) async {
    final statement = await ledger.watchStatement(accountId, to: date).first;
    return statement.closingPaise;
  }
}
