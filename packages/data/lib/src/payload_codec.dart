// Payload boundary: opening blobs (injected — `CryptoPayloadOpener` over
// core_crypto, or the JSON opener for tests) and decoding
// the JSON object inside into `core_ledger` events, accounts and book configs.
//
// ⚠️ SPEC: 02 §1.3 fixes the Entry wire shape; 03 §2.3 names the other object
// types but no spec enumerates their JSON fields yet — except `business_setting`,
// fixed by ADR 2026-09-14b §5. The shapes below are the M2 interpretation
// (snake_case, ids as strings, money as integer paise, dates ISO, periods
// `YYYY-MM`). Unknown fields are never dropped by this layer: the blob in
// `envelopes_local` is the stored truth and is never rewritten.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';

/// Hash of a blob, as stored in `envelopes_local.blob_hash` (ADR 05c §2).
/// Injected: `blake2bHasher` (core_crypto) in the app; tests inject a toy hash.
typedef BlobHasher = Uint8List Function(Uint8List blob);

/// The plaintext routing fields of a mirror row (03 §3.1) that an opener needs
/// beside the blob: the AAD of 04 §4 is rebuilt from them, so a header the
/// server changed fails to open.
final class BlobHeader {
  /// Creates the header from a row's columns.
  const BlobHeader({
    required this.envelopeId,
    required this.bookId,
    required this.objectId,
    required this.objectType,
    required this.keyVersion,
    required this.authorDevice,
    required this.hlc,
  });

  /// Envelope id.
  final String envelopeId;

  /// Book.
  final String bookId;

  /// Object id.
  final String objectId;

  /// Registry type.
  final String objectType;

  /// Book-key version the blob is sealed under.
  final int keyVersion;

  /// Author device.
  final String authorDevice;

  /// HLC.
  final int hlc;
}

/// Opens (decrypts, unpads, decodes) an envelope blob into the object JSON.
/// `CryptoPayloadOpener` (over `core_crypto`) is the real one; [JsonPayloadOpener]
/// serves tests and the harness. Signature-chain verification is **not** the
/// opener's job: Recompute only opens rows already marked `verified` (04 §8.3;
/// the sync engine sets the flag after `ChainVerifier`, M4).
abstract interface class PayloadOpener {
  /// Returns the object payload as JSON, with the per-author sequence carried
  /// as `author_seq` at the top level (ADR 2026-09-05b §3). Throws on any
  /// failure — the caller quarantines the envelope with the reason.
  Map<String, Object?> open(Uint8List blob, BlobHeader header);
}

/// Blob = UTF-8 JSON of the object. No cryptography — tests only.
final class JsonPayloadOpener implements PayloadOpener {
  /// Creates the opener.
  const JsonPayloadOpener();

  @override
  Map<String, Object?> open(Uint8List blob, BlobHeader header) {
    final decoded = jsonDecode(utf8.decode(blob));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('payload is not a JSON object');
    }
    return decoded;
  }
}

/// Encodes an object payload the way [JsonPayloadOpener] reads it.
Uint8List encodeJsonPayload(Map<String, Object?> payload) =>
    Uint8List.fromList(utf8.encode(jsonEncode(payload)));

/// Who owns a business book (02 §7.1 🔒, ADR 2026-09-09b §2). Asked on S0.6a;
/// it decides whether the book gets a Capital/Drawings pair or one Partner
/// Current A/c per owner — never both.
enum BookOwnership {
  /// One owner. Gets `Drawings A/c` alongside `Opening Balance / Capital`.
  justMe,

  /// Several owners. Gets a Partner Current A/c each, and no Drawings A/c.
  shared,
}

/// Which kind of organization a [BookType.organization] book is (07 §3.1.1 🔒:
/// gurudwara · temple · society · registered trust). The four are the
/// *illustrative* list that spec calls examples, not an exhaustive set — every
/// value is the same `tenant.type = organization`, so a later addition changes
/// this enum and nothing else. A value this client does not recognise is kept
/// verbatim in [BookConfig.extra] and never guessed at (03 §3.3.4 🔒).
enum OrganizationSubtype {
  /// ਗੁਰਦੁਆਰਾ.
  gurudwara,

  /// A temple / मंदिर.
  temple,

  /// A registered society.
  society,

  /// A registered trust.
  registeredTrust,
}

/// Wire names for [OrganizationSubtype] (07 §3.1.1). Wire names are `snake_case`
/// and fixed: renaming the Dart identifier must never change them.
const organizationSubtypeWire = {
  OrganizationSubtype.gurudwara: 'gurudwara',
  OrganizationSubtype.temple: 'temple',
  OrganizationSubtype.society: 'society',
  OrganizationSubtype.registeredTrust: 'registered_trust',
};

/// A book's configuration envelope (`book_config`, 03 §2.3): what `books_p`
/// is projected from.
final class BookConfig {
  /// Creates a config.
  const BookConfig({
    required this.id,
    required this.tenantId,
    required this.type,
    required this.name,
    this.fyStartMonth = 4,
    this.ownership = BookOwnership.justMe,
    this.startDate,
    this.partnerShares = const {},
    this.structuralQuorum,
    this.organizationSubtype,
    this.extra = const {},
  });

  /// Reads the wire form, keeping unknown fields in [extra].
  ///
  /// A field whose *value* this client cannot interpret counts as unknown:
  /// it is left in [extra] verbatim and written back untouched, so an older
  /// app amending a config a newer app wrote strips nothing (03 §3.3.4 🔒).
  factory BookConfig.fromJson(Map<String, Object?> json) {
    // Absent on books written before this change; a book with no weights
    // recorded simply has none — the ADR 2026-09-09b precedent for
    // `ownership`. Null here means the key is present but uninterpretable,
    // which keeps it in [extra].
    final shares = json.containsKey('partner_shares')
        ? _readPartnerShares(json['partner_shares'])
        : const <String, int>{};
    final subtype = _readOrganizationSubtype(json['organization_subtype']);
    // Absent = the default, all owners (02 §7.2.1); a value this build cannot
    // interpret is null here and stays in [extra] (ADR 2026-09-14b §3).
    final quorum = StructuralQuorum.fromWire(json[structuralQuorumKey]);
    final known = {
      'id',
      'tenant_id',
      'type',
      'name',
      'fy_start_month',
      'ownership',
      'start_date',
      if (shares != null) 'partner_shares',
      if (quorum != null) structuralQuorumKey,
      if (subtype != null) 'organization_subtype',
    };
    return BookConfig(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      type: BookType.values.byName(json['type'] as String),
      name: json['name'] as String,
      fyStartMonth: json['fy_start_month'] as int? ?? 4,
      // Absent on books written before ADR 2026-09-09b; a book with no
      // ownership recorded is a single-owner book.
      ownership: BookOwnership.values.byName(
        json['ownership'] as String? ?? BookOwnership.justMe.name,
      ),
      // Absent on books written before ADR 2026-09-09d.
      startDate: switch (json['start_date']) {
        final String iso => LocalDate.parse(iso),
        _ => null,
      },
      partnerShares: shares ?? const {},
      structuralQuorum: quorum,
      organizationSubtype: subtype,
      extra: Map.unmodifiable(
        Map<String, Object?>.of(json)..removeWhere((k, _) => known.contains(k)),
      ),
    );
  }

  /// Book id.
  final String id;

  /// Tenant.
  final String tenantId;

  /// Book type.
  final BookType type;

  /// Name.
  final String name;

  /// FY start month (02 §1.1).
  final int fyStartMonth;

  /// Who owns it (02 §7.1 🔒). Meaningful for [BookType.business]; every other
  /// book type is [BookOwnership.justMe] and ignores it.
  final BookOwnership ownership;

  /// The day the books begin (ADR 2026-09-09d §4): stamped once when the book
  /// is created and never changed. Opening balances are dated here, and no
  /// entry may be dated before it. Null only on books older than the ADR.
  final LocalDate? startDate;

  /// Each owner's agreed share weight, **keyed by Partner Current A/c id**,
  /// as **agreed at business creation** — the deed (02 §7.1 🔒, ADR 2026-09-09
  /// §2, ADR 2026-09-14b §2/§4). Whole positive weights, never percentages:
  /// 02 §7.1 divides by `floor(amount × weight ÷ Σweights)`, so 1:1:1 is three
  /// equal thirds and 33/33/34 is not.
  ///
  /// This is the creation-time value and it never changes here: a ratio change
  /// is the structural action of 02 §7.2.1, recorded once quorum exists as a
  /// dated [BusinessSetting]. The ratio **in force** is read through
  /// [structuralSettingsInForce] and [partnerSharesInForce], never from this
  /// field alone — a distribution under a stale ratio is a wrong ledger.
  ///
  /// Keyed by account id because that is the only identity that survives a
  /// rename — the account is seeded as `{Name} — Partner Current A/c` and the
  /// owner may rename it or themselves — and because 02 §7.1's own remainder
  /// rule keys on the partner *account* (largest ratio, ties by earliest
  /// created). ADR 2026-09-09 §1 collects the weights against owner rows, but
  /// each owner gets exactly one partner account and, since owners are only
  /// *invited* at setup, no member identity exists yet to key on.
  ///
  /// Empty means no weights are recorded — a book written before this field
  /// existed, or a [BookOwnership.justMe] book, which has no partners at all.
  /// It never means "equal": a reader that finds none must say so rather than
  /// assume a split.
  ///
  /// The keys are checked here for shape only. A distributing caller must
  /// still match them against the book's chart — an id that is absent, or is
  /// not a `partner` account, is a claim from an envelope like any other and
  /// is not evidence (02 preamble: readers re-check).
  final Map<String, int> partnerShares;

  /// The `structural_quorum` chosen at creation (02 §7.2.1 🔒, ADR 2026-09-14b
  /// §3) — the deed's value, like [partnerShares]. Null when the key is absent
  /// (the default, all owners, applies) **or** when the stored value is one
  /// this build does not recognise (kept verbatim in [extra], 03 §3.3.4 🔒,
  /// and read by the engine as all owners — the strictest rule). Changes are
  /// dated [BusinessSetting] records; the rule in force at any order point is
  /// `quorumInForce(structuralSettingsInForce(...))`.
  final StructuralQuorum? structuralQuorum;

  /// Which of 07 §3.1.1's four kinds of organization this book is. Null on a
  /// book written before this field existed, on every non-organization book,
  /// and when the stored value is one this client does not recognise (in
  /// which case it is preserved in [extra], 03 §3.3.4 🔒).
  final OrganizationSubtype? organizationSubtype;

  /// Fields this client did not understand.
  final Map<String, Object?> extra;

  /// Wire form, unknown fields written back.
  Map<String, Object?> toJson() => {
    'id': id,
    'tenant_id': tenantId,
    'type': type.name,
    'name': name,
    'fy_start_month': fyStartMonth,
    'ownership': ownership.name,
    if (startDate != null) 'start_date': startDate!.toIso(),
    // Omitted when there are none, so a book with no partners carries no key
    // — and so an uninterpretable value held in [extra] is written back by
    // the spread below without colliding with a key of ours.
    if (partnerShares.isNotEmpty)
      'partner_shares': Map<String, Object?>.of(partnerShares),
    // Written only when recorded and understood; an uninterpretable value
    // rides in [extra] below under the same key, so the two never collide.
    if (structuralQuorum != null) structuralQuorumKey: structuralQuorum!.wire,
    if (organizationSubtype != null)
      'organization_subtype': organizationSubtypeWire[organizationSubtype]!,
    ...extra,
  };

  /// `{account id: weight}` when every entry is a positive whole weight, else
  /// null — the value is then not understood and stays in [extra] (03 §3.3.4).
  /// A float weight is refused like any float touching arithmetic.
  static Map<String, int>? _readPartnerShares(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, int>{};
    for (final MapEntry(:key, :value) in raw.entries) {
      if (key is! String || value is! int || value <= 0) return null;
      out[key] = value;
    }
    return Map.unmodifiable(out);
  }

  /// The subtype for a wire name, or null when absent *or* unrecognised — a
  /// value a newer client wrote must survive, never throw (03 §3.3.4 🔒).
  static OrganizationSubtype? _readOrganizationSubtype(Object? raw) {
    if (raw is! String) return null;
    for (final MapEntry(:key, :value) in organizationSubtypeWire.entries) {
      if (value == raw) return key;
    }
    return null;
  }
}

/// Wire names for [AccountClass] (02 §1.2).
const accountClassWire = {
  AccountClass.money: 'money',
  AccountClass.party: 'party',
  AccountClass.advance: 'advance',
  AccountClass.partner: 'partner',
  AccountClass.categoryIncome: 'category_income',
  AccountClass.categoryExpense: 'category_expense',
  AccountClass.equitySystem: 'equity_system',
};

/// Wire names for [MoneySubtype] (03 §3.2 comment).
const moneySubtypeWire = {
  MoneySubtype.cash: 'cash',
  MoneySubtype.cashCollection: 'cash_collection',
  MoneySubtype.saving: 'saving',
  MoneySubtype.current: 'current',
  MoneySubtype.od: 'od',
  MoneySubtype.cc: 'cc',
  MoneySubtype.loan: 'loan',
  MoneySubtype.wallet: 'wallet',
};

/// Wire names for [SystemRole].
const systemRoleWire = {
  SystemRole.openingBalance: 'opening_balance',
  SystemRole.adjustments: 'adjustments',
  SystemRole.suspense: 'suspense',
  SystemRole.dueToFrom: 'due_to_from',
  SystemRole.profitDistributed: 'profit_distributed',
  SystemRole.drawings: 'drawings',
};

T _byWire<T>(Map<T, String> table, String wire, String what) => table.entries
    .firstWhere(
      (e) => e.value == wire,
      orElse: () => throw FormatException('unknown $what', wire),
    )
    .key;

/// An `account` payload (02 §1.2) as [Account] plus the projection-only fields.
final class AccountPayload {
  /// Creates the decoded payload.
  const AccountPayload(
    this.account, {
    this.collectionIncomeAccountId,
    this.usualCategoryId,
    this.archived = false,
  });

  /// Reads the wire form.
  factory AccountPayload.fromJson(Map<String, Object?> json) {
    final subtype = json['money_subtype'] as String?;
    final role = json['system_role'] as String?;
    return AccountPayload(
      Account(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        name: json['name'] as String,
        accountClass: _byWire(
          accountClassWire,
          json['class'] as String,
          'account class',
        ),
        subtype: subtype == null
            ? null
            : _byWire(moneySubtypeWire, subtype, 'money subtype'),
        systemRole: role == null
            ? null
            : _byWire(systemRoleWire, role, 'system role'),
        memberId: json['member_id'] as String?,
        counterpartBookId: json['counterpart_book_id'] as String?,
        createdOrder: json['created_order'] as int,
      ),
      collectionIncomeAccountId:
          json['collection_income_account_id'] as String?,
      usualCategoryId: json['usual_category_id'] as String?,
      archived: json['archived'] as bool? ?? false,
    );
  }

  /// The engine account.
  final Account account;

  /// Where a collection count posts income (02 §8.2).
  final String? collectionIncomeAccountId;

  /// Quick-entry default.
  final String? usualCategoryId;

  /// Archived flag.
  final bool archived;

  /// Wire form.
  Map<String, Object?> toJson() => {
    'id': account.id,
    'book_id': account.bookId,
    'name': account.name,
    'class': accountClassWire[account.accountClass],
    if (account.subtype != null)
      'money_subtype': moneySubtypeWire[account.subtype],
    if (account.systemRole != null)
      'system_role': systemRoleWire[account.systemRole],
    if (account.memberId != null) 'member_id': account.memberId,
    if (account.counterpartBookId != null)
      'counterpart_book_id': account.counterpartBookId,
    'created_order': account.createdOrder,
    if (collectionIncomeAccountId != null)
      'collection_income_account_id': collectionIncomeAccountId,
    if (usualCategoryId != null) 'usual_category_id': usualCategoryId,
    if (archived) 'archived': true,
  };
}

/// Object types the projector consumes (03 §2.3 registry). Everything else is
/// stored, counted for integrity, and ignored by Recompute at M2.
const projectedObjectTypes = {
  'entry',
  'approval_decision',
  'period_lock',
  'period_unlock',
  'year_close',
  'cash_count',
};

/// Decodes a projector event, or returns null for object types the projector
/// does not consume (`account`, `book_config`, `rule`, `import_*`, …).
///
/// [authorDevice] / [authorSeq] are the mirror row's columns (03 §3.1) — the
/// plaintext mirror of the `author_seq` that travels inside the ciphertext
/// (ADR 2026-09-05b §3). Every event carries them from here; an entry's inner
/// `author_seq` is kept only when no [authorSeq] is given.
/// `period_lock` / `year_close` carry `projector_version` (ADR 2026-09-05c §3).
LedgerEvent? decodeEvent(
  String objectType,
  Map<String, Object?> json, {
  String? authorDevice,
  int? authorSeq,
}) {
  switch (objectType) {
    case 'entry':
      final e = Entry.fromJson(json);
      // The caller's [authorSeq] is the projector-facing rank (see Recompute
      // step 1b); when given it replaces the inner seq, which Recompute has
      // already checked against the mirror row.
      return authorSeq != null ? e.copyWith(authorSeq: authorSeq) : e;
    case 'approval_decision':
      return ApprovalDecision(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        entryId: json['entry_id'] as String,
        decision: Decision.values.byName(json['decision'] as String),
        byUser: json['by_user'] as String,
        hlc: Hlc(json['hlc'] as int),
        reason: json['reason'] as String?,
        authorDevice: authorDevice,
        authorSeq: authorSeq,
      );
    case 'period_lock':
      final declared = json['declared_balances'] as Map<String, Object?>?;
      return PeriodLock(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        period: _yearMonth(json['period'] as String),
        byUser: json['by_user'] as String,
        hlc: Hlc(json['hlc'] as int),
        declaredBalances: declared == null
            ? null
            : {for (final e in declared.entries) e.key: Paise(e.value as int)},
        vectorCanonical: json['vector_canonical'] as String?,
        projectorVersion: json['projector_version'] as int?,
        authorDevice: authorDevice,
        authorSeq: authorSeq,
      );
    case 'period_unlock':
      return PeriodUnlock(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        period: _yearMonth(json['period'] as String),
        byUser: json['by_user'] as String,
        reason: json['reason'] as String,
        hlc: Hlc(json['hlc'] as int),
        authorDevice: authorDevice,
        authorSeq: authorSeq,
      );
    case 'year_close':
      final vector = json['vector'] as Map<String, Object?>;
      return YearClose(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        financialYear: FinancialYear(
          json['fy_start_year'] as int,
          startMonth: json['fy_start_month'] as int? ?? 4,
        ),
        vector: BalanceVector({
          for (final e in vector.entries) e.key: Paise(e.value as int),
        }),
        byUser: json['by_user'] as String,
        hlc: Hlc(json['hlc'] as int),
        projectorVersion: json['projector_version'] as int?,
        authorDevice: authorDevice,
        authorSeq: authorSeq,
      );
    case 'cash_count':
      final sheet = json['sheet'] as Map<String, Object?>?;
      return CashCount(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        accountId: json['account_id'] as String,
        date: LocalDate.parse(json['date'] as String),
        counted: Paise(json['counted_paise'] as int),
        hlc: Hlc(json['hlc'] as int),
        authorDevice: authorDevice,
        authorSeq: authorSeq,
        sheet: sheet == null
            ? null
            : DenominationSheet(
                notes: {
                  for (final e
                      in (sheet['notes'] as Map<String, Object?>? ?? const {})
                          .entries)
                    int.parse(e.key): e.value as int,
                },
                coinsPaise: Paise(sheet['coins_paise'] as int? ?? 0),
              ),
        countedBy: json['counted_by'] as String?,
        witness: json['witness'] as String?,
      );
    default:
      return null;
  }
}

/// The wire form of a projector event — the inverse of [decodeEvent], used by
/// tests and by authoring code until `core_ledger` grows `toJson` on events.
Map<String, Object?> encodeEvent(LedgerEvent event) => switch (event) {
  Entry() => event.toJson(),
  ApprovalDecision() => {
    'id': event.id,
    'book_id': event.bookId,
    'entry_id': event.entryId,
    'decision': event.decision.name,
    'by_user': event.byUser,
    'hlc': event.hlc.raw,
    if (event.reason != null) 'reason': event.reason,
  },
  PeriodLock() => {
    'id': event.id,
    'book_id': event.bookId,
    'period': event.period.toString(),
    'by_user': event.byUser,
    'hlc': event.hlc.raw,
    if (event.declaredBalances != null)
      'declared_balances': {
        for (final e in event.declaredBalances!.entries) e.key: e.value.raw,
      },
    if (event.vectorCanonical != null)
      'vector_canonical': event.vectorCanonical,
    if (event.projectorVersion != null)
      'projector_version': event.projectorVersion,
  },
  PeriodUnlock() => {
    'id': event.id,
    'book_id': event.bookId,
    'period': event.period.toString(),
    'by_user': event.byUser,
    'reason': event.reason,
    'hlc': event.hlc.raw,
  },
  YearClose() => {
    'id': event.id,
    'book_id': event.bookId,
    'fy_start_year': event.financialYear.startYear,
    'fy_start_month': event.financialYear.startMonth,
    'vector': {
      for (final e in event.vector.nonZero.entries) e.key: e.value.raw,
    },
    'by_user': event.byUser,
    'hlc': event.hlc.raw,
    if (event.projectorVersion != null)
      'projector_version': event.projectorVersion,
  },
  CashCount() => {
    'id': event.id,
    'book_id': event.bookId,
    'account_id': event.accountId,
    'date': event.date.toIso(),
    'counted_paise': event.counted.raw,
    'hlc': event.hlc.raw,
    if (event.sheet != null)
      'sheet': {
        'notes': {
          for (final e in event.sheet!.notes.entries) '${e.key}': e.value,
        },
        'coins_paise': event.sheet!.coinsPaise.raw,
      },
    if (event.countedBy != null) 'counted_by': event.countedBy,
    if (event.witness != null) 'witness': event.witness,
  },
  _ => throw ArgumentError.value(event, 'event', 'unknown event type'),
};

/// The `object_type` registry value for a projector event.
String objectTypeOf(LedgerEvent event) => switch (event) {
  Entry() => 'entry',
  ApprovalDecision() => 'approval_decision',
  PeriodLock() => 'period_lock',
  PeriodUnlock() => 'period_unlock',
  YearClose() => 'year_close',
  CashCount() => 'cash_count',
  _ => throw ArgumentError.value(event, 'event', 'unknown event type'),
};

YearMonth _yearMonth(String s) {
  final parts = s.split('-');
  if (parts.length != 2) throw FormatException('period must be YYYY-MM', s);
  return YearMonth(int.parse(parts[0]), int.parse(parts[1]));
}

/// The structural keys a `book_config` envelope carries as the deed — the
/// terms agreed at creation (ADR 2026-09-14b §2). `fy_start_month` is not
/// among them: it is the one structural key the projector reads and its
/// change path is its own slice (ADR 2026-09-14b § Open).
const Set<String> structuralSettingKeys = {
  'partner_shares',
  structuralQuorumKey,
};

/// A `business_setting` envelope (03 §2.3 registry; ADR 2026-09-05e §11;
/// ADR 2026-09-14b §2, §5): the dated record of **one applied structural
/// change** — a new object per change, never amended. It names the
/// `structural_approval` request whose quorum authorised it, and carries the
/// settings it set as the flat map the engine speaks (`structural_quorum`,
/// `partner_shares`, …), so `structuralQuorumOf(record.settings)` reads it
/// directly and the fold below is `applyStructural` composed.
///
/// The codec does not judge a record: whether its [requestId] names an
/// approved request whose payload equals [settings] is the verifier's rule
/// (ADR 2026-09-14b §5, `E-03-36 @M7`), and a record that fails it is
/// quarantined with its reason. Reading never throws on that question — only
/// on a malformed shape.
///
/// Not a projector event: Recompute neither sums nor quarantines it on shape,
/// `decodeEvent` returns null for it, and `project()` never sees it.
final class BusinessSetting {
  /// Creates a record.
  const BusinessSetting({
    required this.id,
    required this.bookId,
    required this.hlc,
    required this.byUser,
    required this.settings,
    this.requestId,
    this.extra = const {},
  });

  /// Reads the wire form. Unknown top-level fields are kept in [extra];
  /// unknown keys **or values** inside `settings` are kept verbatim inside
  /// [settings] — their consumers read them conservatively (03 §3.3.4 🔒).
  /// Throws [FormatException] when `settings` is not a JSON object: a record
  /// that sets nothing is malformed, and the caller quarantines it.
  factory BusinessSetting.fromJson(Map<String, Object?> json) {
    final settings = json['settings'];
    if (settings is! Map) {
      throw const FormatException(
        'business_setting: `settings` must be a JSON object',
      );
    }
    const known = {'id', 'book_id', 'hlc', 'by_user', 'request_id', 'settings'};
    return BusinessSetting(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      hlc: Hlc(json['hlc'] as int),
      byUser: json['by_user'] as String,
      requestId: json['request_id'] as String?,
      settings: Map.unmodifiable(Map<String, Object?>.from(settings)),
      extra: Map.unmodifiable(
        Map<String, Object?>.of(json)..removeWhere((k, _) => known.contains(k)),
      ),
    );
  }

  /// Object id — one per change.
  final String id;

  /// Book.
  final String bookId;

  /// When it was recorded; with [id], its place in the `(hlc, envelope_id)`
  /// order every device folds in.
  final Hlc hlc;

  /// Who recorded it — the device that observed quorum reached. Joins the
  /// admin-actions feed (02 §7.2 item 3).
  final String byUser;

  /// The `structural_approval` request this record applies. Null is legal at
  /// the codec and illegal at the verifier: a record with no authorising
  /// request never enters the fold.
  final String? requestId;

  /// The structural keys this change set, verbatim.
  final Map<String, Object?> settings;

  /// Top-level fields this client did not understand.
  final Map<String, Object?> extra;

  /// Wire form, unknown fields written back.
  Map<String, Object?> toJson() => {
    'id': id,
    'book_id': bookId,
    'hlc': hlc.raw,
    'by_user': byUser,
    if (requestId != null) 'request_id': requestId,
    'settings': Map<String, Object?>.of(settings),
    ...extra,
  };
}

/// The structural settings **in force** after [applied] — the deed's
/// [structuralSettingKeys] from [deed], overridden by each record's
/// [BusinessSetting.settings] in `(hlc, id)` order whatever order they are
/// given in (ADR 2026-09-14b §2). This is `applyStructural` composed over the
/// approved requests the records stand for, and the **only** path a
/// distributing or counting caller may read a structural setting through.
///
/// [applied] must already be verified (ADR 2026-09-14b §5) — the fold trusts
/// what it is handed, like the engine's `evaluateStructural` trusts its
/// records. A record of another book is a caller error and throws. Values a
/// build cannot interpret — in the deed or a record — are carried verbatim, so
/// `structuralQuorumOf` reads them as all owners and [partnerSharesInForce] as
/// *not recorded*. Neither input is mutated.
Map<String, Object?> structuralSettingsInForce({
  required BookConfig deed,
  required Iterable<BusinessSetting> applied,
}) {
  final wire = deed.toJson();
  final inForce = <String, Object?>{
    for (final k in structuralSettingKeys)
      if (wire.containsKey(k)) k: wire[k],
  };
  final ordered = applied.toList()
    ..sort((a, b) => compareEventOrder(a.hlc, a.id, b.hlc, b.id));
  for (final record in ordered) {
    if (record.bookId != deed.id) {
      throw ArgumentError.value(
        record.id,
        'applied',
        'business_setting of book ${record.bookId} folded into ${deed.id}',
      );
    }
    inForce.addAll(record.settings);
  }
  return Map.unmodifiable(inForce);
}

/// The quorum rule in force — the engine's conservative read of the fold:
/// absent or uninterpretable is all owners (ADR 2026-09-14b §3).
StructuralQuorum quorumInForce(Map<String, Object?> inForce) =>
    structuralQuorumOf(inForce);

/// The ratio in force, `{partner account id: weight}` — or empty when none is
/// recorded **or** the recorded value is one this build cannot divide by
/// (ADR 2026-09-13 §3: empty never means equal; a reader says so).
Map<String, int> partnerSharesInForce(Map<String, Object?> inForce) =>
    BookConfig._readPartnerShares(inForce['partner_shares']) ?? const {};
