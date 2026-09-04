import 'events.dart';
import 'hlc.dart';
import 'local_date.dart';
import 'money.dart';

/// The six verbs (02 §2). Wire names are the 02 §1.3 snake_case values.
enum EntryKind {
  /// Money in / ਪੈਸੇ ਆਏ / पैसे आए.
  moneyIn('money_in'),

  /// Money out / ਪੈਸੇ ਗਏ / पैसे गए.
  moneyOut('money_out'),

  /// Gave on credit / ਉਧਾਰ ਦਿੱਤਾ / उधार दिया.
  gaveCredit('gave_credit'),

  /// Took on credit / ਉਧਾਰ ਲਿਆ / उधार लिया.
  tookCredit('took_credit'),

  /// Transfer between money accounts, or across books (02 §6).
  transfer('transfer'),

  /// Guided adjustment wizards only (02 §2 verb 6).
  adjustment('adjustment');

  const EntryKind(this.wire);

  /// Wire name.
  final String wire;

  /// Parses a wire name.
  static EntryKind parse(String wire) => values.firstWhere(
    (k) => k.wire == wire,
    orElse: () => throw FormatException('unknown kind', wire),
  );
}

/// Stored status (02 §1.3). `pending` is **only** an advance request awaiting
/// approval; everything else is `posted` from the moment it is saved. `void` is
/// a derived state and is never authored — it is accepted on read for forward
/// compatibility only.
enum EntryStatus {
  /// Advance request awaiting approval (02 §7).
  pending('pending'),

  /// Counts in balances from the first moment (02 §3).
  posted('posted'),

  /// Derived: fully reversed (02 §5).
  voided('void');

  const EntryStatus(this.wire);

  /// Wire name.
  final String wire;

  /// Parses a wire name.
  static EntryStatus parse(String wire) => values.firstWhere(
    (s) => s.wire == wire,
    orElse: () => throw FormatException('unknown status', wire),
  );
}

/// One posting line: signed paise, + = debit, − = credit (02 §1.3).
final class Line {
  /// Creates a line. [tag] distinguishes lines to the same account inside one
  /// entry (02 §7.1: `interest` vs `share`). Unknown wire fields ride in [extra].
  const Line({
    required this.accountId,
    required this.amount,
    this.tag,
    this.extra = const {},
  });

  /// Reads a wire line; amounts must be integers (02 §1.4 rule 2).
  factory Line.fromJson(Map<String, Object?> json) {
    final amount = json['amount_paise'];
    if (amount is! int) {
      throw FormatException('amount_paise must be an integer', amount);
    }
    final extra = Map<String, Object?>.of(json)
      ..removeWhere((k, _) => _lineKeys.contains(k));
    return Line(
      accountId: json['account_id'] as String,
      amount: Paise(amount),
      tag: json['tag'] as String?,
      extra: extra,
    );
  }

  static const _lineKeys = {'account_id', 'amount_paise', 'tag'};

  /// Account.
  final String accountId;

  /// Signed amount.
  final Paise amount;

  /// Optional tag.
  final String? tag;

  /// Fields this client does not understand, preserved verbatim (03 §3.3.4).
  final Map<String, Object?> extra;

  /// Wire form.
  Map<String, Object?> toJson() => {
    'account_id': accountId,
    'amount_paise': amount.raw,
    if (tag != null) 'tag': tag,
    ...extra,
  };

  @override
  bool operator ==(Object other) =>
      other is Line &&
      other.accountId == accountId &&
      other.amount == amount &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(accountId, amount, tag);

  @override
  String toString() =>
      '${amount.isDebit ? 'Dr' : 'Cr'} $accountId ${amount.abs().raw}${tag == null ? '' : ' [$tag]'}';
}

/// Cross-references between envelopes (02 §1.3).
final class EntryRefs {
  /// Creates refs.
  const EntryRefs({
    this.amends,
    this.reverses,
    this.transferGroup,
    this.importLine,
    this.close,
    this.extra = const {},
  });

  /// Reads wire refs.
  factory EntryRefs.fromJson(Map<String, Object?> json) {
    final extra = Map<String, Object?>.of(json)
      ..removeWhere((k, _) => _keys.contains(k));
    return EntryRefs(
      amends: json['amends'] as String?,
      reverses: json['reverses'] as String?,
      transferGroup: json['transfer_group'] as String?,
      importLine: json['import_line'] as String?,
      close: json['close'] as String?,
      extra: extra,
    );
  }

  static const _keys = {
    'amends',
    'reverses',
    'transfer_group',
    'import_line',
    'close',
  };

  /// This entry replaces that one (02 §5).
  final String? amends;

  /// This entry mirrors that one (02 §5).
  final String? reverses;

  /// Both halves of an inter-book move share this (02 §6).
  final String? transferGroup;

  /// Statement import line (02 §10).
  final String? importLine;

  /// The close envelope this adjustment belongs to (02 §8).
  final String? close;

  /// Unknown fields, preserved.
  final Map<String, Object?> extra;

  /// True when nothing is set.
  bool get isEmpty =>
      amends == null &&
      reverses == null &&
      transferGroup == null &&
      importLine == null &&
      close == null &&
      extra.isEmpty;

  /// Copy with changes.
  EntryRefs copyWith({
    String? amends,
    String? reverses,
    String? transferGroup,
    String? importLine,
    String? close,
  }) => EntryRefs(
    amends: amends ?? this.amends,
    reverses: reverses ?? this.reverses,
    transferGroup: transferGroup ?? this.transferGroup,
    importLine: importLine ?? this.importLine,
    close: close ?? this.close,
    extra: extra,
  );

  /// Wire form.
  Map<String, Object?> toJson() => {
    if (amends != null) 'amends': amends,
    if (reverses != null) 'reverses': reverses,
    if (transferGroup != null) 'transfer_group': transferGroup,
    if (importLine != null) 'import_line': importLine,
    if (close != null) 'close': close,
    ...extra,
  };
}

/// The plaintext JSON inside an entry envelope (02 §1.3).
final class Entry implements LedgerEvent {
  /// Creates an entry.
  Entry({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.status,
    required this.reviewRequired,
    required this.accountingDate,
    required this.lines,
    required this.createdByUser,
    required this.createdByDevice,
    required this.hlc,
    this.reviewLimitPaise,
    this.reviewApprover,
    this.partyId,
    this.advanceId,
    this.note,
    this.attachmentIds = const [],
    this.refs = const EntryRefs(),
    this.currency = 'INR',
    this.extra = const {},
  });

  /// Reads a wire entry, keeping unknown top-level fields in [extra] (03 §3.3.4).
  factory Entry.fromJson(Map<String, Object?> json) {
    final extra = Map<String, Object?>.of(json)
      ..removeWhere((k, _) => _keys.contains(k));
    final limit = json['review_limit_paise'];
    if (limit != null && limit is! int) {
      throw FormatException('review_limit_paise must be an integer', limit);
    }
    final hlc = json['hlc'];
    if (hlc is! int) throw FormatException('hlc must be an integer', hlc);
    return Entry(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      kind: EntryKind.parse(json['kind'] as String),
      status: EntryStatus.parse(json['status'] as String),
      reviewRequired: json['review_required'] as bool? ?? false,
      reviewLimitPaise: limit == null ? null : Paise(limit as int),
      reviewApprover: json['review_approver'] as String?,
      accountingDate: LocalDate.parse(json['accounting_date'] as String),
      lines: [
        for (final l in json['lines'] as List<Object?>)
          Line.fromJson(l! as Map<String, Object?>),
      ],
      partyId: json['party_id'] as String?,
      advanceId: json['advance_id'] as String?,
      note: json['note'] as String?,
      attachmentIds: [
        for (final a
            in (json['attachment_ids'] as List<Object?>?) ?? const <Object?>[])
          a! as String,
      ],
      refs: json['refs'] == null
          ? const EntryRefs()
          : EntryRefs.fromJson(json['refs']! as Map<String, Object?>),
      createdByUser: json['created_by_user'] as String,
      createdByDevice: json['created_by_device'] as String,
      hlc: Hlc(hlc),
      currency: json['currency'] as String? ?? 'INR',
      extra: extra,
    );
  }

  static const _keys = {
    'id',
    'book_id',
    'kind',
    'status',
    'review_required',
    'review_limit_paise',
    'review_approver',
    'accounting_date',
    'lines',
    'party_id',
    'advance_id',
    'note',
    'attachment_ids',
    'refs',
    'created_by_user',
    'created_by_device',
    'hlc',
    'currency',
  };

  @override
  final String id;

  @override
  final String bookId;

  /// Verb.
  final EntryKind kind;

  /// Stored status.
  final EntryStatus status;

  /// Authored at save time by the client that knows the limit (02 §1.3).
  final bool reviewRequired;

  /// The limit in force at this entry's HLC; `null` = no limit applies (own
  /// personal book, or a single-member book — 02 §3, §7.2 item 1).
  /// ⚠️ SPEC: 02 §1.3 types this as a plain int; the "never flagged" cases need
  /// a representation, and `null` is the conservative one.
  final Paise? reviewLimitPaise;

  /// Who must act, then who acted.
  final String? reviewApprover;

  /// User-visible date.
  final LocalDate accountingDate;

  /// Postings.
  final List<Line> lines;

  /// Denormalised party ref for lists and ageing.
  final String? partyId;

  /// Denormalised advance ref.
  final String? advanceId;

  /// The user's own words (02 §10 *note*).
  final String? note;

  /// Attachments.
  final List<String> attachmentIds;

  /// Cross-references.
  final EntryRefs refs;

  /// Author.
  final String createdByUser;

  /// Authoring device.
  final String createdByDevice;

  @override
  final Hlc hlc;

  /// Always `INR` in Phase 1 (02 §1.4 rule 5).
  final String currency;

  /// Unknown top-level fields, preserved verbatim.
  final Map<String, Object?> extra;

  /// Sum of debit lines — the entry's amount for limits and lists.
  Paise get totalDebits =>
      Paise.sum(lines.where((l) => l.amount.isDebit).map((l) => l.amount));

  /// Wire form. Fields this client did not understand are written back unchanged.
  Map<String, Object?> toJson() => {
    'id': id,
    'book_id': bookId,
    'kind': kind.wire,
    'status': status.wire,
    'review_required': reviewRequired,
    'review_limit_paise': reviewLimitPaise?.raw,
    if (reviewApprover != null) 'review_approver': reviewApprover,
    'accounting_date': accountingDate.toIso(),
    'lines': [for (final l in lines) l.toJson()],
    if (partyId != null) 'party_id': partyId,
    if (advanceId != null) 'advance_id': advanceId,
    if (note != null) 'note': note,
    if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
    if (!refs.isEmpty) 'refs': refs.toJson(),
    'created_by_user': createdByUser,
    'created_by_device': createdByDevice,
    'hlc': hlc.raw,
    'currency': currency,
    ...extra,
  };

  /// Copy with changes. Unknown fields travel along.
  Entry copyWith({
    String? id,
    EntryKind? kind,
    EntryStatus? status,
    bool? reviewRequired,
    Paise? reviewLimitPaise,
    String? reviewApprover,
    LocalDate? accountingDate,
    List<Line>? lines,
    String? partyId,
    String? advanceId,
    String? note,
    List<String>? attachmentIds,
    EntryRefs? refs,
    String? createdByUser,
    String? createdByDevice,
    Hlc? hlc,
    String? currency,
  }) => Entry(
    id: id ?? this.id,
    bookId: bookId,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    reviewRequired: reviewRequired ?? this.reviewRequired,
    reviewLimitPaise: reviewLimitPaise ?? this.reviewLimitPaise,
    reviewApprover: reviewApprover ?? this.reviewApprover,
    accountingDate: accountingDate ?? this.accountingDate,
    lines: lines ?? this.lines,
    partyId: partyId ?? this.partyId,
    advanceId: advanceId ?? this.advanceId,
    note: note ?? this.note,
    attachmentIds: attachmentIds ?? this.attachmentIds,
    refs: refs ?? this.refs,
    createdByUser: createdByUser ?? this.createdByUser,
    createdByDevice: createdByDevice ?? this.createdByDevice,
    hlc: hlc ?? this.hlc,
    currency: currency ?? this.currency,
    extra: extra,
  );

  /// An amendment of this entry (02 §5): a new envelope, kind unchanged,
  /// `refs.amends = this.id`, carrying the complete replacement payload. Fields
  /// not passed are copied from this entry — including ones this client does not
  /// understand (03 §3.3.4). Amend the head of the chain only.
  Entry amendWith({
    required String newId,
    required Hlc hlc,
    List<Line>? lines,
    LocalDate? accountingDate,
    String? note,
    List<String>? attachmentIds,
    String? partyId,
    String? advanceId,
    bool? reviewRequired,
    Paise? reviewLimitPaise,
    String? reviewApprover,
    String? createdByUser,
    String? createdByDevice,
  }) => copyWith(
    id: newId,
    hlc: hlc,
    lines: lines,
    accountingDate: accountingDate,
    note: note,
    attachmentIds: attachmentIds,
    partyId: partyId,
    advanceId: advanceId,
    reviewRequired: reviewRequired,
    reviewLimitPaise: reviewLimitPaise,
    reviewApprover: reviewApprover,
    createdByUser: createdByUser,
    createdByDevice: createdByDevice,
    refs: refs.copyWith(amends: id),
  );

  /// The auto-built mirror of this entry (02 §5): every line negated, dated in
  /// the open period, `refs.reverses = this.id`. Posted, never flagged — a
  /// reversal restores the prior figure and is authored by the corrector.
  Entry reversal({
    required String newId,
    required Hlc hlc,
    required LocalDate accountingDate,
    required String createdByUser,
    required String createdByDevice,
    String? note,
  }) => Entry(
    id: newId,
    bookId: bookId,
    kind: kind,
    status: EntryStatus.posted,
    reviewRequired: false,
    accountingDate: accountingDate,
    lines: [
      for (final l in lines)
        Line(
          accountId: l.accountId,
          amount: -l.amount,
          tag: l.tag,
          extra: l.extra,
        ),
    ],
    partyId: partyId,
    advanceId: advanceId,
    note: note,
    refs: EntryRefs(reverses: id),
    createdByUser: createdByUser,
    createdByDevice: createdByDevice,
    hlc: hlc,
    currency: currency,
  );

  @override
  String toString() => 'Entry($id ${kind.wire} $accountingDate $lines)';
}
