// What statement import needs from the ledger and from the device, and
// nothing more.
//
// `app/lib/shared/ledger/` and `bootstrap.dart` belong to other lanes this
// round, so S7 talks to these **feature-local seams** instead of to
// `LocalLedger`. The next lane implements [ImportSource] over it and installs
// it above the route with [ImportScope]; nothing in this folder imports the
// facade.
//
// Two seams, because they fail for different reasons and are faked
// separately: [ImportSource] is the book (which A/Cs, what is already
// imported, what this bank's mapping was last time), and [StatementFilePort]
// is the device (one file, its bytes). **No new dependency this round** — a
// real `file_picker` binding is one implementation of [StatementFilePort].
//
// Everything here is on-device. Nothing readable leaves the phone (07 §11
// item 1 🔒, 04), so no method on either seam is allowed to reach the network,
// and none of them takes a callback that could.
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/widgets.dart';

import 'import_lines.dart';
import 'parse/column_mapping.dart';
import 'parse/parsed_statement.dart';
import 'parse/statement_parser.dart';

/// A bank A/C of the current book, as the S7 account list draws it.
///
/// Only *bank* A/Cs are candidates: a statement is a bank's own book of the
/// account (02 §10 🔒). Cash and collection A/Cs are counted, not imported
/// (02 §8.2).
final class ImportAccount {
  /// Creates the row.
  const ImportAccount({
    required this.id,
    required this.name,
    required this.bankKey,
    this.subtitle,
  });

  /// The A/C id.
  final String id;

  /// What the user calls it (*SBI Saving*).
  final String name;

  /// Which bank's shape a remembered mapping belongs to (07 §11 item 1 🔒:
  /// corrections are remembered **per bank**, not per A/C — a second A/C at
  /// the same bank exports the same columns).
  final String bankKey;

  /// One muted line beneath the name, when the book has one (the A/C type, a
  /// masked number). Never the full number.
  final String? subtitle;
}

/// One file the user picked, held in memory. It is read on this phone and
/// nowhere else.
final class PickedStatementFile {
  /// Creates the file.
  const PickedStatementFile({required this.name, required this.bytes});

  /// The file's own name, shown back to the user for recognition.
  final String name;

  /// Its bytes.
  final Uint8List bytes;

  /// Its size, which the 10 MB rule is about.
  int get length => bytes.length;
}

/// The device door: one file, picked by the user.
///
/// A seam rather than a package call, so S7 is testable and so the real
/// binding is a single follow-up file. Returns null when the user backed out
/// of the picker — a cancel is not an error and must not show one.
abstract interface class StatementFilePort {
  /// Opens the OS picker and returns what the user chose.
  Future<PickedStatementFile?> pickStatementFile();
}

/// The ledger door, as S7 and S7.0a–c need it.
abstract interface class ImportSource {
  /// The bank A/Cs of [bookId] that a statement can be imported into — the
  /// first step of 07 §11 item 1 🔒 (*pick account → pick file*).
  Future<List<ImportAccount>> pickAccount(String bookId);

  /// The mapping this bank's statements needed last time, or null the first
  /// time (07 §11 item 1 🔒: *corrections are remembered per bank, so the next
  /// statement from that bank needs no mapping*).
  Future<ColumnMapping?> rememberedMapping(String bankKey);

  /// Remembers [mapping] for [bankKey]. Called when the user confirms the
  /// mapping step, whether or not they corrected anything.
  Future<void> rememberMapping(String bankKey, ColumnMapping mapping);

  /// The line identities [bookId] already holds, so duplicates are removed
  /// **before anything is shown** (07 §11 item 1 🔒).
  Future<Set<LineIdentity>> alreadyImported(String bookId);

  /// Reads [bytes] on this device.
  ///
  /// The default implementation is the pure parser; an implementation may
  /// move it off the UI isolate, but never off the phone.
  Future<StatementParseResult> parse({
    required Uint8List bytes,
    required String fileName,
    required String accountId,
    ColumnMapping? mapping,
    Set<LineIdentity> alreadyImported = const {},
  });

  // ── S7.1, the import inbox (07 §11 item 2 🔒, 02 §10 🔒) ──────────────────

  /// Turns a read statement into inbox lines, each wearing its chip.
  ///
  /// This is where `Matched ✓`, `Suggested` and `Transfer?` are decided —
  /// the learned rules, the auto-link and the opposite-line search all live
  /// behind the seam, so S7.1 renders a decision it never makes. Parsed
  /// lines land in an **inbox, never the ledger** (02 §10 🔒): nothing here
  /// posts.
  Future<List<ImportLine>> classify({
    required String bookId,
    required ParsedStatement statement,
  });

  /// The A/Cs the one question can be answered with — the full picker
  /// (07 §11 item 2 🔒).
  Future<List<ImportCounterpart>> counterparts(String bookId);

  /// Inline-creates an A/C from the picker and returns it, so the answer can
  /// be given without leaving the row.
  Future<ImportCounterpart> createCounterpart(
    String bookId, {
    required String name,
  });

  /// `Matched ✓` → **tap to unlink** (07 §11 item 2 🔒). The row falls back
  /// to the one question; nothing was posted, so nothing is reversed.
  Future<ImportLine> unlink(ImportLine line);

  /// `Suggested` → the **one-tap Approve**. Approving teaches the rule
  /// (07 §11 item 3 🔒), which is why it is the seam's job and not the
  /// screen's.
  Future<ImportLine> approveSuggestion(ImportLine line);

  /// The user answers the one question by picking or inline-creating
  /// [counterpart]. A correction — an answer that overrides a suggestion —
  /// comes back carrying [ImportLine.correctedFrom], which is what makes the
  /// screen offer *Always? Yes/No* (07 §11 item 3 🔒).
  Future<ImportLine> answer(ImportLine line, ImportCounterpart counterpart);

  /// The *Always? **Yes*** answer: re-teach the rule from this correction.
  /// Answering *No* simply never calls it.
  Future<void> teachRule(ImportLine line);

  /// `Transfer?` → one tap posts a **single** Transfer instead of two
  /// entries (02 §10 🔒). The pair collapses to one row; the ids that went
  /// come back in [ImportTransferPair.collapsedIds].
  Future<ImportTransferPair> confirmTransfer(ImportLine line);

  /// `Suspense` — *record now, explain later* (02 §10 🔒). The line is
  /// resolved enough to submit; it is not explained, and month-close step 3
  /// walks it to zero (07 §13).
  Future<ImportLine> toSuspense(ImportLine line);

  /// `+ note` — the user's **own** narration on a classified row
  /// (07 §11 item 2 🔒). Never touches `bank_text`, which is immutable
  /// evidence (02 §10 🔒).
  Future<ImportLine> addNote(ImportLine line, String note);

  /// Whether submitting can post at all, asked before the primary action is
  /// drawn so a blocked one is **disabled with its reason** (13 §4.3) rather
  /// than failing on tap.
  ImportPostingAvailability get posting;

  /// Submits [lines] — **partial submit is always allowed** (07 §11 item 1
  /// 🔒): classified lines post, the rest stay in the inbox and come back as
  /// [ImportLeftInInbox].
  ///
  /// One outcome per line, in the order given. It never throws and never
  /// posts a line stripped of its `bank_text`.
  Future<List<ImportLineOutcome>> submit(List<ImportLine> lines);

  /// The book's balance for [accountId] at the end of [date], signed engine
  /// side (+ = Dr) — which for a bank A/C is how the bank prints it. Null
  /// when the seam cannot answer; S7.2 then says so instead of guessing.
  Future<int?> ledgerBalanceOn(String accountId, LocalDate date);
}

/// The on-device parse every [ImportSource] shares: bytes in, value out.
Future<StatementParseResult> parseOnDevice({
  required Uint8List bytes,
  required String fileName,
  required String accountId,
  ColumnMapping? mapping,
  Set<LineIdentity> alreadyImported = const {},
}) async => parseStatement(
  bytes: bytes,
  fileName: fileName,
  accountId: accountId,
  mapping: mapping,
  alreadyImported: alreadyImported,
);

/// The [ImportSource] and [StatementFilePort] for the tree below — installed
/// by the shell above the router, so `importRoutes` can build S7 from a path
/// alone.
class ImportScope extends InheritedWidget {
  /// Creates the scope.
  const ImportScope({
    super.key,
    required this.source,
    required this.filePort,
    required this.bookId,
    required super.child,
  });

  /// The ledger door in force.
  final ImportSource source;

  /// The device door in force.
  final StatementFilePort filePort;

  /// The book being imported into.
  final String bookId;

  /// The nearest scope, or null when the shell has not installed one yet —
  /// the screen then shows its error state rather than throwing (07 §1 rule
  /// 6: no dead ends, and no red screen either).
  static ImportScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImportScope>();

  @override
  bool updateShouldNotify(ImportScope old) =>
      source != old.source || filePort != old.filePort || bookId != old.bookId;
}
