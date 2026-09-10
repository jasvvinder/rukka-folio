// The two slots of an entry, labelled by verb (07 §5 step 2 🔒, corrected 31
// Aug 2026): "the money-account label is never a fixed FROM". Every entry has
// two sides — one is usually a money account, shown as quick chips; the other
// is any ledger account, shown as a picker.
//
// | Verb          | money slot            | ledger slot                     |
// |---------------|-----------------------|---------------------------------|
// | Money in      | INTO (chips)          | FROM — income or a person       |
// | Money out     | FROM (chips)          | FOR — expense or a person       |
// | Gave on credit| WHAT DID YOU GIVE     | TO WHOM — party (leads)         |
// | Took on credit| WHAT DID YOU TAKE     | FROM WHOM — party (leads)       |
// | Move money    | FROM (chips)          | TO (chips)                      |
//
// The pill has five positions 🔒 (ADR 2026-09-03b ruling 1): Move money is
// the fifth swipe, not a separate door. `adjustment` (verb 6) is deliberately
// absent — it lives behind the S2.4 wizards, never on this screen.
//
// This file is the table and nothing else: no widget, no engine call. The
// posting itself is `LocalLedger`'s (02 §2) — the display language never
// bends the postings (02 §10 🔒).
import 'package:core_ledger/core_ledger.dart';

import '../../l10n/gen/app_localizations.dart';

/// The verb pill, in order (07 §5 🔒, ADR 2026-09-03b).
const List<EntryKind> entryVerbs = [
  EntryKind.moneyIn,
  EntryKind.moneyOut,
  EntryKind.gaveCredit,
  EntryKind.tookCredit,
  EntryKind.transfer,
];

/// Which of an entry's two sides a slot is.
enum EntrySlot {
  /// The side that is usually a money account (chips).
  money,

  /// The other side — any ledger account (picker).
  ledger,
}

/// Every slot label the table above uses.
enum SlotLabel {
  into,
  from,
  forWhat,
  whatYouGave,
  toWhom,
  whatYouTook,
  fromWhom,
  moveFrom,
  moveTo,
}

/// The label's string, from ARB (never composed here — 01 §1 rule 7).
String slotLabel(AppLocalizations l10n, SlotLabel label) => switch (label) {
  SlotLabel.into => l10n.entrySlotInto,
  SlotLabel.from => l10n.entrySlotFrom,
  SlotLabel.forWhat => l10n.entrySlotForWhat,
  SlotLabel.whatYouGave => l10n.entrySlotWhatYouGave,
  SlotLabel.toWhom => l10n.entrySlotToWhom,
  SlotLabel.whatYouTook => l10n.entrySlotWhatYouTook,
  SlotLabel.fromWhom => l10n.entrySlotFromWhom,
  SlotLabel.moveFrom => l10n.entrySlotMoveFrom,
  SlotLabel.moveTo => l10n.entrySlotMoveTo,
};

/// The verb's own word — consumer vocabulary only on this screen (02 §10 🔒,
/// CLAUDE.md rule 9). *Move money* is 07 §5's name for verb 5; 01 §2's
/// loanword *ਟ੍ਰਾਂਸਫਰ / ट्रांसफ़र* carries it in the Indic strings.
String verbLabel(AppLocalizations l10n, EntryKind kind) => switch (kind) {
  EntryKind.moneyIn => l10n.entryVerbMoneyIn,
  EntryKind.moneyOut => l10n.entryVerbMoneyOut,
  EntryKind.gaveCredit => l10n.entryVerbGaveCredit,
  EntryKind.tookCredit => l10n.entryVerbTookCredit,
  EntryKind.transfer => l10n.entryVerbMoveMoney,
  // Guided wizards only (02 §2 verb 6) — never a position on this pill.
  EntryKind.adjustment => l10n.entryVerbMoveMoney,
};

/// One slot: its label, whether the chip row belongs to it, which account
/// classes may answer it, and which classes an inline create may mint.
final class SlotSpec {
  /// Creates the spec.
  const SlotSpec({
    required this.label,
    required this.showChips,
    required this.classes,
    this.creatable = const [],
  });

  /// The label this slot carries under its verb.
  final SlotLabel label;

  /// True when the three most-used money accounts + **+ More** belong here
  /// (07 §5 step 2 🔒).
  final bool showChips;

  /// Account classes that may answer this slot.
  final List<AccountClass> classes;

  /// Classes an inline create may mint here (02 §1.2): empty = no create
  /// offered, one = the class is inferred and nothing is asked, two = the one
  /// two-chip question (07 §5 step 3 🔒).
  ///
  /// ⚠️ SPEC: a *money* slot mints nothing. 02 §1.2 infers the **class** from
  /// the slot, but a money account also needs its subtype (cash · saving ·
  /// current · card…, 02 §1.2), which is a second question this screen has no
  /// room for — S3.1 quick-add owns that choice. Creating money accounts from
  /// the entry screen is left to the owner rather than invented here.
  final List<AccountClass> creatable;

  /// True when this slot must ask which kind of account to create.
  bool get asksClass => creatable.length > 1;
}

/// The whole slot plan for one verb.
final class VerbPlan {
  const VerbPlan._({
    required this.kind,
    required this.money,
    required this.ledger,
    required this.ledgerLeads,
  });

  /// The plan for [kind].
  static VerbPlan of(EntryKind kind) => switch (kind) {
    EntryKind.moneyIn => const VerbPlan._(
      kind: EntryKind.moneyIn,
      money: SlotSpec(
        label: SlotLabel.into,
        showChips: true,
        classes: [AccountClass.money],
      ),
      ledger: SlotSpec(
        label: SlotLabel.from,
        showChips: false,
        classes: [AccountClass.categoryIncome, AccountClass.party],
        creatable: [AccountClass.categoryIncome, AccountClass.party],
      ),
      ledgerLeads: false,
    ),
    EntryKind.moneyOut => const VerbPlan._(
      kind: EntryKind.moneyOut,
      money: SlotSpec(
        label: SlotLabel.from,
        showChips: true,
        classes: [AccountClass.money],
      ),
      ledger: SlotSpec(
        label: SlotLabel.forWhat,
        showChips: false,
        classes: [AccountClass.categoryExpense, AccountClass.party],
        creatable: [AccountClass.categoryExpense, AccountClass.party],
      ),
      ledgerLeads: false,
    ),
    // The credit verbs: the person is the answer, so the party slot leads the
    // screen (07 §5 table, *leads the screen*).
    EntryKind.gaveCredit => const VerbPlan._(
      kind: EntryKind.gaveCredit,
      money: SlotSpec(
        label: SlotLabel.whatYouGave,
        showChips: true,
        classes: [AccountClass.money, AccountClass.categoryIncome],
        creatable: [AccountClass.categoryIncome],
      ),
      ledger: SlotSpec(
        label: SlotLabel.toWhom,
        showChips: false,
        classes: [AccountClass.party],
        creatable: [AccountClass.party],
      ),
      ledgerLeads: true,
    ),
    EntryKind.tookCredit => const VerbPlan._(
      kind: EntryKind.tookCredit,
      money: SlotSpec(
        label: SlotLabel.whatYouTook,
        showChips: true,
        classes: [AccountClass.money, AccountClass.categoryExpense],
        creatable: [AccountClass.categoryExpense],
      ),
      ledger: SlotSpec(
        label: SlotLabel.fromWhom,
        showChips: false,
        classes: [AccountClass.party],
        creatable: [AccountClass.party],
      ),
      ledgerLeads: true,
    ),
    // S2.3 within one book: two money accounts, both chip rows.
    EntryKind.transfer => const VerbPlan._(
      kind: EntryKind.transfer,
      money: SlotSpec(
        label: SlotLabel.moveFrom,
        showChips: true,
        classes: [AccountClass.money],
      ),
      ledger: SlotSpec(
        label: SlotLabel.moveTo,
        showChips: true,
        classes: [AccountClass.money],
      ),
      ledgerLeads: false,
    ),
    EntryKind.adjustment => throw ArgumentError(
      'adjustment is guided-only (02 §2 verb 6, S2.4) — not an S2 position',
    ),
  };

  /// The verb.
  final EntryKind kind;

  /// The money-account side.
  final SlotSpec money;

  /// The other side.
  final SlotSpec ledger;

  /// True when the ledger slot is drawn first (the credit verbs).
  final bool ledgerLeads;

  /// Screen order of the two slots.
  List<EntrySlot> get order => ledgerLeads
      ? const [EntrySlot.ledger, EntrySlot.money]
      : const [EntrySlot.money, EntrySlot.ledger];

  /// The slot's spec.
  SlotSpec spec(EntrySlot slot) => slot == EntrySlot.money ? money : ledger;

  /// Which slot the engine credits — the left-hand side of the preview line
  /// (01 §2.1 🔒: `{amt} · {credited} → {debited} · {note}`). Read straight
  /// off 02 §2's fixed postings, never guessed.
  EntrySlot get creditSlot => switch (kind) {
    // Dr into (money) · Cr from (income/party).
    EntryKind.moneyIn => EntrySlot.ledger,
    // Dr for (expense/party) · Cr from (money).
    EntryKind.moneyOut => EntrySlot.money,
    // Dr to whom (party) · Cr what you gave (money/income).
    EntryKind.gaveCredit => EntrySlot.money,
    // Dr what you took (money/expense) · Cr from whom (party).
    EntryKind.tookCredit => EntrySlot.ledger,
    // Dr to · Cr from.
    EntryKind.transfer => EntrySlot.money,
    EntryKind.adjustment => EntrySlot.money,
  };

  /// The other side of [creditSlot].
  EntrySlot get debitSlot =>
      creditSlot == EntrySlot.money ? EntrySlot.ledger : EntrySlot.money;
}
