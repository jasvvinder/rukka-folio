// The import inbox's line model (S7.1 — 07 §11 item 2 🔒, 02 §10 🔒).
//
// A parsed line already states **date, direction and amount**. The only
// unknown is the counterpart, so every line asks exactly **one question** —
// *Where did it come from?* (money in) or *Where did it go?* (money out) —
// and the user never sees or chooses a side (02 §10 🔒).
//
// Nothing in this file posts anything. Parsed lines land in an inbox, never
// the ledger (02 §10 🔒); posting happens once, in [ImportSource.submit].
//
// Bank vocabulary throughout: Money in / Money out, never Dr/Cr.
import 'parse/parsed_statement.dart';

/// The chip a row wears (07 §11 item 2 🔒). The chip is a **word**, never a
/// tint alone (07 §1 rule 3).
enum ImportLineState {
  /// `Matched ✓` — auto-linked to an entry the book already holds. Nothing
  /// posts; tap to unlink (02 §10 🔒: *links `refs.import_line`, marks both
  /// reconciled. No posting.*).
  matched,

  /// `Suggested` — a learned rule or a fuzzy match named the counterpart and
  /// is waiting on one tap. Approving teaches the rule (07 §11 item 3 🔒).
  suggested,

  /// `New` — nothing is known but the one question. Answered by picking or
  /// inline-creating an A/C.
  needsAnswer,

  /// `Transfer?` — an opposite line in another own-account matches on amount
  /// and date window: *Is this the same money moving between your accounts?*
  /// (02 §10 🔒). One tap posts a **single** Transfer, not two entries.
  transfer,

  /// `Suspense` — *record now, explain later* (02 §10 🔒). Must reach zero
  /// before the month locks (07 §13).
  suspense,

  /// The one question has an answer: this row is classified and will post.
  answered,
}

/// The counterpart the one question is answered with — an A/C of this book.
///
/// The user picks one or creates one inline; either way they name *where the
/// money came from or went to*, never a side.
final class ImportCounterpart {
  /// Creates the candidate.
  const ImportCounterpart({
    required this.id,
    required this.name,
    this.subtitle,
    this.isOwnMoney = false,
  });

  /// The A/C id.
  final String id;

  /// What the user calls it.
  final String name;

  /// One muted line beneath the name, when the book has one.
  final String? subtitle;

  /// Whether this is one of the user's own money A/Cs — the shape that makes
  /// a line a transfer candidate rather than an expense (02 §10 🔒).
  final bool isOwnMoney;
}

/// A rule's or a fuzzy match's guess, named on the green chip
/// (*"Milk Expense — suggested"*, 07 §11 item 2 🔒).
final class ImportSuggestion {
  /// Creates the guess.
  const ImportSuggestion({
    required this.accountId,
    required this.accountName,
    this.fromRule = false,
  });

  /// The A/C guessed.
  final String accountId;

  /// Its name — what the chip says, so the user approves something they can
  /// read rather than a confidence number.
  final String accountName;

  /// Whether a learned rule produced it (as opposed to a fuzzy match).
  final bool fromRule;
}

/// An auto-link to an entry the book already holds (02 §10 🔒).
final class ImportMatch {
  /// Creates the link.
  const ImportMatch({
    required this.entryId,
    required this.entryLabel,
    this.confidence,
  });

  /// The entry linked by `refs.import_line`.
  final String entryId;

  /// How the entry reads, so *Matched ✓* names what it matched.
  final String entryLabel;

  /// 0–1 where the source has one; shown as a word, never as a bare number.
  final double? confidence;
}

/// One line of the import inbox.
///
/// Immutable: every seam verb returns a new line, so a screen never mutates
/// state it does not own and a test can compare before and after.
final class ImportLine {
  /// Creates the line.
  const ImportLine({
    required this.id,
    required this.parsed,
    required this.accountId,
    required this.state,
    this.suggestion,
    this.match,
    this.counterpartId,
    this.counterpartName,
    this.pairedLineId,
    this.note,
    this.correctedFrom,
  });

  /// Stable within one import — the statement's own row identity.
  final String id;

  /// The statement line, verbatim (02 §10 🔒: `bank_text` is immutable
  /// evidence — never edited, re-cased or cleaned up).
  final ParsedLine parsed;

  /// The bank A/C being imported into.
  final String accountId;

  /// Which chip this row wears.
  final ImportLineState state;

  /// The guess, on [ImportLineState.suggested].
  final ImportSuggestion? suggestion;

  /// The auto-link, on [ImportLineState.matched].
  final ImportMatch? match;

  /// The answer to the one question, once there is one.
  final String? counterpartId;

  /// Its name, for the row and for the preview.
  final String? counterpartName;

  /// The opposite line this one pairs with, on [ImportLineState.transfer] —
  /// and, once confirmed, the half that collapsed into this row.
  final String? pairedLineId;

  /// The user's **own** narration (07 §11 item 2 🔒 `+ note`). Optional and
  /// additive: adding one never alters [ParsedLine.bankText] (02 §10 🔒).
  final String? note;

  /// What the row said before the user corrected it — the trigger for the
  /// *Always? Yes/No* toast (07 §11 item 3 🔒). Null when nothing was
  /// corrected, so approving a suggestion never asks.
  final String? correctedFrom;

  /// The money is in, in the bank's own vocabulary.
  bool get isMoneyIn => parsed.direction == BankDirection.moneyIn;

  /// Whether the row carries an answer and so may be submitted. `Matched`
  /// counts: it links rather than posts, which is still a resolution.
  bool get isClassified => switch (state) {
    ImportLineState.matched ||
    ImportLineState.suspense ||
    ImportLineState.answered => true,
    ImportLineState.suggested ||
    ImportLineState.needsAnswer ||
    ImportLineState.transfer => false,
  };

  /// A copy with the given changes. Null clears nothing — pass the
  /// `clear…` flags for that, so `null` never means "leave alone" by
  /// accident.
  ImportLine copyWith({
    ImportLineState? state,
    ImportSuggestion? suggestion,
    ImportMatch? match,
    String? counterpartId,
    String? counterpartName,
    String? pairedLineId,
    String? note,
    String? correctedFrom,
    bool clearSuggestion = false,
    bool clearMatch = false,
    bool clearCounterpart = false,
    bool clearPair = false,
  }) => ImportLine(
    id: id,
    parsed: parsed,
    accountId: accountId,
    state: state ?? this.state,
    suggestion: clearSuggestion ? null : (suggestion ?? this.suggestion),
    match: clearMatch ? null : (match ?? this.match),
    counterpartId: clearCounterpart
        ? null
        : (counterpartId ?? this.counterpartId),
    counterpartName: clearCounterpart
        ? null
        : (counterpartName ?? this.counterpartName),
    pairedLineId: clearPair ? null : (pairedLineId ?? this.pairedLineId),
    note: note ?? this.note,
    correctedFrom: correctedFrom ?? this.correctedFrom,
  );

  @override
  String toString() => 'ImportLine($id, ${state.name}, ${parsed.paise})';
}

/// What [ImportSource.confirmTransfer] gives back: the **one** row that
/// survives, and the ids that collapsed into it.
///
/// Money leaving one own-account and arriving in another is one event
/// (02 §10 🔒), so the inbox must show one row for it, not two.
final class ImportTransferPair {
  /// Creates the result.
  const ImportTransferPair({required this.line, required this.collapsedIds});

  /// The surviving row, now [ImportLineState.answered] with the other
  /// A/C as its counterpart.
  final ImportLine line;

  /// The ids the inbox removes — the other half of the pair.
  final List<String> collapsedIds;
}

/// What happened to one line on submit. A sealed result, never an exception
/// the screen has to interpret (07 §1 rule 12).
sealed class ImportLineOutcome {
  /// Creates the outcome.
  const ImportLineOutcome(this.lineId);

  /// The line it is about.
  final String lineId;
}

/// The line posted, through the ordinary verb (02 §10 🔒: *normal verb
/// posting with `refs.import_line`*).
final class ImportPosted extends ImportLineOutcome {
  /// Creates the outcome.
  const ImportPosted(
    super.lineId, {
    required this.entryId,
    this.transfer = false,
  });

  /// The entry created.
  final String entryId;

  /// Whether it was the single Transfer of a confirmed pair.
  final bool transfer;
}

/// The line was linked to an entry the book already held: reconciled, not
/// posted (02 §10 🔒).
final class ImportLinked extends ImportLineOutcome {
  /// Creates the outcome.
  const ImportLinked(super.lineId, {required this.entryId});

  /// The entry now carrying `refs.import_line`.
  final String entryId;
}

/// The line was left in the inbox — partial submit is always allowed
/// (07 §11 item 1 🔒), and an unanswered line is not an error.
final class ImportLeftInInbox extends ImportLineOutcome {
  /// Creates the outcome.
  const ImportLeftInInbox(super.lineId);
}

/// Why nothing could be posted (07 §1 rule 6: the reason in words, and a path).
enum ImportUnavailableReason {
  /// 🔒 **The standing blocker.** 02 §10 🔒 requires `bank_text` stored on
  /// the envelope **verbatim and separate from `note`**; the engine has no
  /// such field, so a line could only post with its evidence stripped. It
  /// does not post. Owner-held; the day the ruling lands this becomes one
  /// adapter call.
  bankTextHasNowhereToLand,

  /// The month this line falls in is closed (02 §8).
  periodLocked,

  /// The seam has no ledger behind it yet.
  noLedger,
}

/// The line did **not** post, and why — never a thrown error, and never a
/// line posted with its `bank_text` stripped.
final class ImportPostingUnavailable extends ImportLineOutcome {
  /// Creates the outcome.
  const ImportPostingUnavailable(super.lineId, {required this.reason});

  /// Which blocker.
  final ImportUnavailableReason reason;
}

/// Whether submitting can post at all, asked **before** the button is drawn
/// so the action can be disabled *with its reason* (13 §4.3
/// disabled-with-reason).
sealed class ImportPostingAvailability {
  /// Creates the value.
  const ImportPostingAvailability();
}

/// Submitting posts.
final class ImportPostingReady extends ImportPostingAvailability {
  /// Creates the value.
  const ImportPostingReady();
}

/// Submitting cannot post, for a stated reason.
final class ImportPostingBlocked extends ImportPostingAvailability {
  /// Creates the value.
  const ImportPostingBlocked(this.reason);

  /// Which blocker — the same vocabulary [ImportPostingUnavailable] uses.
  final ImportUnavailableReason reason;
}
