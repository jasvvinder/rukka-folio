// Which column of this bank's CSV is which (07 §11 item 1 🔒).
//
// The app auto-detects date, description, withdrawal, deposit and balance and
// asks the user to confirm; the correction is **remembered per bank**, so the
// next statement from that bank needs no mapping. This type is both what the
// detector produces and what is remembered — one shape, so a remembered
// mapping can be fed straight back into the parser.

/// What one column of the statement holds.
///
/// Bank vocabulary, not ledger vocabulary (02 §10 🔒): the bank's *credit*
/// column is money **in** to the user, and the user never sees the word.
enum StatementColumn {
  /// Transaction date — the entry's `accounting_date`.
  date,

  /// The bank's own line: `bank_text`, immutable evidence (02 §10 🔒).
  description,

  /// Money out of the account (the bank prints it as withdrawal or debit).
  moneyOut,

  /// Money in to the account (the bank prints it as deposit or credit).
  moneyIn,

  /// A single amount column, its direction carried by a sign or a marker.
  amount,

  /// The marker column beside [amount] (`Dr`/`Cr`, `D`/`C`, `Debit`/`Credit`).
  direction,

  /// The bank's running balance after the line.
  balance,
}

/// How sure the detector is of a mapping.
enum MappingConfidence {
  /// The user confirmed it, or it came back from the per-bank memory.
  confirmed,

  /// Every column was named by a header the detector recognises.
  detected,

  /// At least one column had to be inferred from the data rather than read
  /// from a header — the mapping step opens with that column highlighted.
  guessed,
}

/// The column indices one statement shape uses.
///
/// Exactly one of the two money arrangements is present:
/// - [moneyOut] and/or [moneyIn] — separate columns, the common Indian shape;
/// - [amount], alone (signed) or with [direction] (a `Dr`/`Cr` marker).
final class ColumnMapping {
  /// Creates a mapping.
  const ColumnMapping({
    required this.date,
    this.description,
    this.moneyOut,
    this.moneyIn,
    this.amount,
    this.direction,
    this.balance,
    this.headerRow = 0,
    this.delimiter = ',',
    this.confidence = MappingConfidence.detected,
  });

  /// Column holding the transaction date.
  final int date;

  /// Column holding the bank's own narration line, when the file has one.
  final int? description;

  /// Withdrawal / debit column.
  final int? moneyOut;

  /// Deposit / credit column.
  final int? moneyIn;

  /// Single amount column.
  final int? amount;

  /// `Dr`/`Cr` marker column beside [amount].
  final int? direction;

  /// Running balance column.
  final int? balance;

  /// Index of the header row within the file (rows above it are the bank's
  /// letterhead and are skipped).
  final int headerRow;

  /// The field delimiter the file uses.
  final String delimiter;

  /// How the mapping was arrived at.
  final MappingConfidence confidence;

  /// True when the file carries separate money-out and money-in columns.
  bool get hasSplitColumns => moneyOut != null || moneyIn != null;

  /// True when the mapping can actually read a line's amount.
  bool get hasAmount => hasSplitColumns || amount != null;

  /// The column index playing [role], or null.
  int? column(StatementColumn role) => switch (role) {
    StatementColumn.date => date,
    StatementColumn.description => description,
    StatementColumn.moneyOut => moneyOut,
    StatementColumn.moneyIn => moneyIn,
    StatementColumn.amount => amount,
    StatementColumn.direction => direction,
    StatementColumn.balance => balance,
  };

  /// This mapping with [role] pointed at [column] (null clears it) — what a
  /// correction on the mapping screen produces. A corrected mapping is
  /// [MappingConfidence.confirmed]: the user has just said so.
  ColumnMapping withColumn(StatementColumn role, int? column) => ColumnMapping(
    date: role == StatementColumn.date ? (column ?? date) : date,
    description: role == StatementColumn.description ? column : description,
    moneyOut: role == StatementColumn.moneyOut ? column : moneyOut,
    moneyIn: role == StatementColumn.moneyIn ? column : moneyIn,
    amount: role == StatementColumn.amount ? column : amount,
    direction: role == StatementColumn.direction ? column : direction,
    balance: role == StatementColumn.balance ? column : balance,
    headerRow: headerRow,
    delimiter: delimiter,
    confidence: MappingConfidence.confirmed,
  );

  /// This mapping, marked confirmed — what is remembered for the bank.
  ColumnMapping get confirmed => confidence == MappingConfidence.confirmed
      ? this
      : ColumnMapping(
          date: date,
          description: description,
          moneyOut: moneyOut,
          moneyIn: moneyIn,
          amount: amount,
          direction: direction,
          balance: balance,
          headerRow: headerRow,
          delimiter: delimiter,
          confidence: MappingConfidence.confirmed,
        );

  /// JSON shape — what `rules_p` (03 §3.2) will hold per bank. Unknown fields
  /// a later version adds are preserved by the caller, not dropped here
  /// (03 §3.3.4).
  Map<String, Object?> toJson() => {
    'date': date,
    if (description != null) 'description': description,
    if (moneyOut != null) 'money_out': moneyOut,
    if (moneyIn != null) 'money_in': moneyIn,
    if (amount != null) 'amount': amount,
    if (direction != null) 'direction': direction,
    if (balance != null) 'balance': balance,
    'header_row': headerRow,
    'delimiter': delimiter,
  };

  /// Reads [toJson].
  static ColumnMapping fromJson(Map<String, Object?> json) => ColumnMapping(
    date: json['date']! as int,
    description: json['description'] as int?,
    moneyOut: json['money_out'] as int?,
    moneyIn: json['money_in'] as int?,
    amount: json['amount'] as int?,
    direction: json['direction'] as int?,
    balance: json['balance'] as int?,
    headerRow: (json['header_row'] as int?) ?? 0,
    delimiter: (json['delimiter'] as String?) ?? ',',
    confidence: MappingConfidence.confirmed,
  );

  @override
  bool operator ==(Object other) =>
      other is ColumnMapping &&
      other.date == date &&
      other.description == description &&
      other.moneyOut == moneyOut &&
      other.moneyIn == moneyIn &&
      other.amount == amount &&
      other.direction == direction &&
      other.balance == balance &&
      other.headerRow == headerRow &&
      other.delimiter == delimiter;

  @override
  int get hashCode => Object.hash(
    date,
    description,
    moneyOut,
    moneyIn,
    amount,
    direction,
    balance,
    headerRow,
    delimiter,
  );

  @override
  String toString() => 'ColumnMapping(${toJson()}, ${confidence.name})';
}
