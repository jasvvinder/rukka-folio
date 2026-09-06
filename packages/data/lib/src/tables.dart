// Drift table definitions — 03 §3.1 (Layer 1: envelope mirror & outbox) and
// §3.2 (Layer 2: projections). Column names are the spec's snake_case names.
// Money is integer paise everywhere (CLAUDE.md rule 1). Layer 1 is the truth
// the client holds; every Layer 2 table is disposable and rebuilt by Recompute.
import 'package:drift/drift.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layer 1 — envelope mirror & outbox (03 §3.1 🔒)
// ─────────────────────────────────────────────────────────────────────────────

/// Mirror of every envelope this device has pulled or authored. Append-only:
/// triggers refuse UPDATE of the envelope's own fields and any DELETE outside
/// the guarded re-bootstrap path (CLAUDE.md rule 2, ADR 2026-09-05c §6).
class EnvelopesLocal extends Table {
  @override
  String get tableName => 'envelopes_local';

  /// Envelope id (client-minted UUIDv7, 03 §1).
  TextColumn get envelopeId => text()();

  /// Book.
  TextColumn get bookId => text()();

  /// Object the envelope carries a version of.
  TextColumn get objectId => text()();

  /// `object_type` registry value (03 §2.3).
  TextColumn get objectType => text()();

  /// Book-key version the blob is sealed under.
  IntColumn get keyVersion => integer()();

  /// Ordering authority (03 §1).
  IntColumn get hlc => integer()();

  /// Server sequence; null until acknowledged. Revocation cut-off (ADR 05b §5).
  IntColumn get seq => integer().nullable()();

  /// Authoring device.
  TextColumn get authorDevice => text()();

  /// Per-author sequence, copied from inside the ciphertext (ADR 05b §3).
  IntColumn get authorSeq => integer()();

  /// Opaque ciphertext (SQL column `blob`).
  BlobColumn get envelopeBlob => blob().named('blob')();

  /// Hash of [blob], verified on read (ADR 05c §2, §6).
  BlobColumn get blobHash => blob()();

  /// 1 after the signature-chain check.
  IntColumn get verified => integer().withDefault(const Constant(0))();

  /// 1 when a reader refused it (security event).
  IntColumn get quarantined => integer().withDefault(const Constant(0))();

  /// Why it was quarantined.
  TextColumn get quarantineReason => text().nullable()();

  /// 1 while a dangling reference waits for its target (ADR 05b §4).
  IntColumn get held => integer().withDefault(const Constant(0))();

  /// The missing target's id.
  TextColumn get heldFor => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {envelopeId};
}

/// Envelopes authored here, awaiting the server (03 §3.1, ADR 05b §6).
class Outbox extends Table {
  @override
  String get tableName => 'outbox';

  /// Envelope id.
  TextColumn get envelopeId => text()();

  /// Book.
  TextColumn get bookId => text()();

  /// The sealed envelope as pushed (SQL column `blob`).
  BlobColumn get envelopeBlob => blob().named('blob')();

  /// Injected creation time (ms); never read from a clock inside this package.
  IntColumn get createdAt => integer()();

  /// queued → inflight → acked → observed; any state → rejected.
  TextColumn get pushState => text().customConstraint(
    "NOT NULL CHECK (push_state IN ('queued','inflight','acked','observed','rejected'))",
  )();

  /// Server seq returned on ack.
  IntColumn get ackedSeq => integer().nullable()();

  /// Server's reason on rejection.
  TextColumn get rejectReason => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {envelopeId};
}

/// Next `author_seq` per (book, device) — monotone from 1 (ADR 05b §3).
class AuthorSeqLocal extends Table {
  @override
  String get tableName => 'author_seq_local';

  /// Book.
  TextColumn get bookId => text()();

  /// This device.
  TextColumn get deviceId => text()();

  /// The next sequence number to hand out.
  IntColumn get nextSeq => integer()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, deviceId};
}

/// Derived: two envelopes from one author carrying the same `author_seq`
/// (ADR 05b §3). The earlier by `(hlc, envelope_id)` is kept; the later is
/// quarantined `author_seq_duplicate` by Recompute and the book stays
/// `integrity_ok = 0` while a duplicate exists — the mirror is append-only, so a
/// duplicate can never be removed, only remembered.
class AuthorDuplicates extends Table {
  @override
  String get tableName => 'author_duplicates';

  /// Book.
  TextColumn get bookId => text()();

  /// Author whose sequence repeats.
  TextColumn get authorDevice => text()();

  /// The repeated sequence number.
  IntColumn get authorSeq => integer()();

  /// The envelope that keeps the seq (earliest by `(hlc, envelope_id)`).
  TextColumn get keptEnvelopeId => text()();

  /// The later envelope, quarantined.
  TextColumn get duplicateEnvelopeId => text()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, duplicateEnvelopeId};
}

/// Derived: missing `author_seq` values per (book, author) — drives the status
/// surface and blocks close (ADR 05b §3, ADR 05e §4).
class AuthorGaps extends Table {
  @override
  String get tableName => 'author_gaps';

  /// Book.
  TextColumn get bookId => text()();

  /// Author whose sequence has a hole.
  TextColumn get authorDevice => text()();

  /// The sequence number that has not arrived.
  IntColumn get expectedSeq => integer()();

  /// HLC of the earliest later envelope from that author — since when we know.
  IntColumn get sinceHlc => integer()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, authorDevice, expectedSeq};
}

/// Signed structural records (ADR 05b §1); server rows are their projection.
class SignedRecordsLocal extends Table {
  @override
  String get tableName => 'signed_records_local';

  /// Record id.
  TextColumn get id => text()();

  /// Tenant.
  TextColumn get tenantId => text()();

  /// Record kind.
  TextColumn get kind => text()();

  /// Payload bytes.
  BlobColumn get payload => blob()();

  /// Signing device.
  TextColumn get authorDevice => text()();

  /// Signature.
  BlobColumn get sig => blob()();

  /// HLC.
  IntColumn get hlc => integer()();

  /// Server seq.
  IntColumn get seq => integer().nullable()();

  /// 1 after verification.
  IntColumn get verified => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One row: the server store epoch (ADR 05b §6). A change resets every cursor.
class StoreEpoch extends Table {
  @override
  String get tableName => 'store_epoch';

  /// Always 1 — enforces the single row.
  IntColumn get id => integer().customConstraint('NOT NULL CHECK (id = 1)')();

  /// The epoch.
  TextColumn get epoch => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Server-seq pull cursor per book (05 §4).
class SyncCursors extends Table {
  @override
  String get tableName => 'sync_cursors';

  /// Book.
  TextColumn get bookId => text()();

  /// Highest server seq applied.
  IntColumn get lastSeq => integer()();

  @override
  Set<Column<Object>> get primaryKey => {bookId};
}

/// Wrapped book keys; unwrapped only in memory (04 §3.3).
class KeyCache extends Table {
  @override
  String get tableName => 'key_cache';

  /// Book.
  TextColumn get bookId => text()();

  /// Key version.
  IntColumn get keyVersion => integer()();

  /// The wrapped key blob — opaque here.
  BlobColumn get wrappedBlob => blob()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, keyVersion};
}

/// Local attachment files.
class AttachmentCache extends Table {
  @override
  String get tableName => 'attachment_cache';

  /// Attachment id.
  TextColumn get id => text()();

  /// Book.
  TextColumn get bookId => text()();

  /// Where the decrypted file lives locally.
  TextColumn get localPath => text()();

  /// Cache state.
  TextColumn get state => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ─────────────────────────────────────────────────────────────────────────────
// Layer 2 — projections (03 §3.2 🔒), rebuildable, indexed for the UI
// ─────────────────────────────────────────────────────────────────────────────

/// Books.
class BooksP extends Table {
  @override
  String get tableName => 'books_p';

  /// Book id.
  TextColumn get id => text()();

  /// Tenant.
  TextColumn get tenantId => text()();

  /// Book type (02 §1.1 wire name).
  TextColumn get type => text()();

  /// Display name (ciphertext-side, 03 §4).
  TextColumn get name => text()();

  /// Financial-year start month (02 §1.1).
  IntColumn get fyStartMonth => integer().withDefault(const Constant(4))();

  /// 1 only when every envelope of the book is present, verified and not held
  /// (ADR 05c §6) — gates the Home card.
  IntColumn get integrityOk => integer().withDefault(const Constant(0))();

  /// 1 when a mirror row failed `blob_hash`: re-bootstrap from the server
  /// (ADR 05c §6). ⚠️ SPEC: column not listed in 03 §3.2; a projection table
  /// may carry it because Recompute derives it from the mirror every time.
  IntColumn get needsRebootstrap => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Accounts (02 §1.2). Carries every field `core_ledger.Account` needs so the
/// Chart rebuilds from this table without re-opening payloads.
class AccountsP extends Table {
  @override
  String get tableName => 'accounts_p';

  /// Account id.
  TextColumn get id => text()();

  /// Book.
  TextColumn get bookId => text()();

  /// Name.
  TextColumn get name => text()();

  /// Engine class wire name.
  TextColumn get accountClass => text().named('class')();

  /// cash | cash_collection | saving | current | od | cc | loan | wallet.
  TextColumn get moneySubtype => text().nullable()();

  /// cash_collection: where counts post income (02 §8.2).
  TextColumn get collectionIncomeAccountId => text().nullable()();

  /// Usual category for quick entry (02 §1.2).
  TextColumn get usualCategoryId => text().nullable()();

  /// 1 when archived.
  IntColumn get archived => integer().withDefault(const Constant(0))();

  /// equity_system role wire name.
  TextColumn get systemRole => text().nullable()();

  /// Member for advance / partner accounts.
  TextColumn get memberId => text().nullable()();

  /// Counterpart book for Due to/from accounts (02 §6).
  TextColumn get counterpartBookId => text().nullable()();

  /// Creation order within the chart.
  IntColumn get createdOrder => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Entries with their projected state (02 §1.3, §3, §5).
///
/// 🔒 `status` and `review_state` are INDEPENDENT: `pending` means only "advance
/// request awaiting approval"; an over-limit entry is `posted` + `open` and IS in
/// balances (02 §9).
class EntriesP extends Table {
  @override
  String get tableName => 'entries_p';

  /// Entry id.
  TextColumn get id => text()();

  /// Book.
  TextColumn get bookId => text()();

  /// Verb wire name.
  TextColumn get kind => text()();

  /// Effective status wire name: posted | pending | rejected | superseded |
  /// void | in_tray (⚠️ SPEC: 03 §3.2 does not enumerate; these are
  /// `core_ledger.EffectiveStatus` in 02 §1.3 spelling).
  TextColumn get status => text()();

  /// ISO date.
  TextColumn get accountingDate => text()();

  /// Note.
  TextColumn get note => text().nullable()();

  /// Channel tag.
  TextColumn get channel => text().nullable()();

  /// Party.
  TextColumn get partyId => text().nullable()();

  /// Advance the entry belongs to (02 §7).
  TextColumn get advanceRef => text().nullable()();

  /// Inter-book pair id (02 §6).
  TextColumn get transferGroup => text().nullable()();

  /// Amended entry.
  TextColumn get amends => text().nullable()();

  /// Reversed entry.
  TextColumn get reverses => text().nullable()();

  /// The amendment that replaced this entry; null = head of the chain.
  TextColumn get supersededBy => text().nullable()();

  /// Review flag (02 §3).
  TextColumn get reviewState => text().customConstraint(
    "NOT NULL DEFAULT 'none' CHECK (review_state IN ('none','open','approved','rejected'))",
  )();

  /// Who must act, then who acted.
  TextColumn get reviewApprover => text().nullable()();

  /// HLC of the decision.
  IntColumn get reviewDecidedHlc => integer().nullable()();

  /// Required on rejected.
  TextColumn get reviewReason => text().nullable()();

  /// Author.
  TextColumn get createdByUser => text()();

  /// HLC.
  IntColumn get hlc => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Posting lines, denormalised with book and date — answers every ledger query.
class EntryLinesP extends Table {
  @override
  String get tableName => 'entry_lines_p';

  /// Entry.
  TextColumn get entryId => text()();

  /// Account.
  TextColumn get accountId => text()();

  /// Signed paise: + Dr, − Cr.
  IntColumn get amountPaise => integer()();

  /// Book.
  TextColumn get bookId => text()();

  /// ISO date.
  TextColumn get accountingDate => text()();

  /// Position within the entry — keeps line order stable across rebuilds.
  IntColumn get lineIndex => integer()();

  @override
  Set<Column<Object>> get primaryKey => {entryId, lineIndex};
}

/// Month states (02 §8).
class PeriodsP extends Table {
  @override
  String get tableName => 'periods_p';

  /// Book.
  TextColumn get bookId => text()();

  /// Calendar year.
  IntColumn get year => integer()();

  /// Month 1–12.
  IntColumn get month => integer()();

  /// open | locked.
  TextColumn get state => text()();

  /// HLC of the lock in force.
  IntColumn get lockHlc => integer().nullable()();

  /// This reader's verification of the lock's published vector (ADR 2026-09-05c
  /// §3): verified | mismatch | reader_outdated | certifier_outdated; null when
  /// the lock published no vector or the month is open.
  TextColumn get verification => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, year, month};
}

/// Cash counts (02 §8.2).
class CashCountsP extends Table {
  @override
  String get tableName => 'cash_counts_p';

  /// Count id.
  TextColumn get id => text()();

  /// Cash or collection account.
  TextColumn get accountId => text()();

  /// verify (cash) | collect (cash_collection).
  TextColumn get mode => text()();

  /// ISO date counted.
  TextColumn get countedAt => text()();

  /// Counted total in paise.
  IntColumn get countedTotalPaise => integer()();

  /// Denomination sheet as JSON.
  TextColumn get breakdownJson => text().nullable()();

  /// The adjustment / income entry the count led to.
  TextColumn get postedEntryId => text().nullable()();

  /// Counter.
  TextColumn get countedBy => text().nullable()();

  /// Witness (mandatory for collection accounts).
  TextColumn get witness => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Year close states (02 §8.1).
class YearCloseP extends Table {
  @override
  String get tableName => 'year_close_p';

  /// Book.
  TextColumn get bookId => text()();

  /// `2026-27`.
  TextColumn get fyLabel => text()();

  /// open | closed | uncertified.
  TextColumn get state => text()();

  /// Hash of the certified vector (core_crypto, M3).
  TextColumn get vectorHash => text().nullable()();

  /// The certified vector as JSON `{account_id: paise}`.
  TextColumn get vector => text().nullable()();

  /// `core_ledger.projectorVersion` recorded in the close envelope (ADR
  /// 2026-09-05c §3); null for a pre-M2 close.
  IntColumn get projectorVersion => integer().nullable()();

  /// This reader's verification of the close: verified | mismatch |
  /// reader_outdated ("Update the app to verify this close") |
  /// certifier_outdated. Null while the year is open.
  TextColumn get verification => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {bookId, fyLabel};
}

/// Imported statement lines (02 §10).
class ImportLinesP extends Table {
  @override
  String get tableName => 'import_lines_p';

  /// Line id.
  TextColumn get id => text()();

  /// Book.
  TextColumn get bookId => text()();

  /// The bank account imported into.
  TextColumn get bankAccountId => text()();

  /// ISO date.
  TextColumn get date => text()();

  /// Bank text.
  TextColumn get description => text()();

  /// Signed paise.
  IntColumn get amountPaise => integer()();

  /// State.
  TextColumn get state => text()();

  /// Matched entry.
  TextColumn get matchedEntry => text().nullable()();

  /// Duplicate hash (ADR 05e §12).
  TextColumn get dedupeHash => text().unique()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Learned import rules.
class RulesP extends Table {
  @override
  String get tableName => 'rules_p';

  /// Rule id.
  TextColumn get id => text()();

  /// Book.
  TextColumn get bookId => text()();

  /// Pattern.
  TextColumn get pattern => text()();

  /// Target account.
  TextColumn get targetAccount => text()();

  /// Hit count.
  IntColumn get hits => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Balance cache (02 §9): derived, rebuilt by Recompute, cross-checked against
/// `entry_lines_p` by the consistency check.
class Balances extends Table {
  @override
  String get tableName => 'balances';

  /// Account.
  TextColumn get accountId => text()();

  /// Signed paise.
  IntColumn get balancePaise => integer()();

  /// HLC of the last applied envelope.
  IntColumn get asOfHlc => integer()();

  @override
  Set<Column<Object>> get primaryKey => {accountId};
}

/// End-of-day balance per account on days with activity.
class DailySnapshots extends Table {
  @override
  String get tableName => 'daily_snapshots';

  /// Account.
  TextColumn get accountId => text()();

  /// ISO date.
  TextColumn get date => text()();

  /// Signed paise at end of day.
  IntColumn get balancePaise => integer()();

  @override
  Set<Column<Object>> get primaryKey => {accountId, date};
}

/// Every table, Layer 1 then Layer 2 — the order Recompute and dumps use.
const layer1Tables = [
  'envelopes_local',
  'outbox',
  'author_seq_local',
  'author_gaps',
  'author_duplicates',
  'signed_records_local',
  'store_epoch',
  'sync_cursors',
  'key_cache',
  'attachment_cache',
];

/// Projection tables (disposable).
const layer2Tables = [
  'books_p',
  'accounts_p',
  'entries_p',
  'entry_lines_p',
  'periods_p',
  'cash_counts_p',
  'year_close_p',
  'import_lines_p',
  'rules_p',
  'balances',
  'daily_snapshots',
];

/// Key indexes (03 §3.2) and the append-only guards on the mirror.
const schemaStatements = [
  // 03 §3.1 — mirror lookups
  'CREATE INDEX IF NOT EXISTS envelopes_local_book_order ON envelopes_local(book_id, hlc, envelope_id)',
  'CREATE INDEX IF NOT EXISTS envelopes_local_author ON envelopes_local(book_id, author_device, author_seq)',
  'CREATE INDEX IF NOT EXISTS outbox_state ON outbox(push_state)',
  // 03 §3.2 — key indexes
  'CREATE INDEX IF NOT EXISTS entry_lines_p_account_date ON entry_lines_p(account_id, accounting_date)',
  'CREATE INDEX IF NOT EXISTS entries_p_daybook ON entries_p(book_id, accounting_date DESC)',
  "CREATE INDEX IF NOT EXISTS entries_p_inbox ON entries_p(book_id, review_approver) WHERE review_state = 'open'",
  "CREATE INDEX IF NOT EXISTS entries_p_advance_requests ON entries_p(book_id) WHERE status = 'pending'",
  'CREATE INDEX IF NOT EXISTS import_lines_p_state ON import_lines_p(book_id, state)',
  // CLAUDE.md rule 2 — the mirror is append-only. Flag columns (verified,
  // quarantined, quarantine_reason, held, held_for, seq) may change; the envelope
  // itself may not. Deletion only through the guarded re-bootstrap path.
  'CREATE TRIGGER IF NOT EXISTS envelopes_local_append_only_update '
      'BEFORE UPDATE OF envelope_id, book_id, object_id, object_type, key_version, hlc, author_device, author_seq, blob, blob_hash '
      "ON envelopes_local BEGIN SELECT RAISE(ABORT, 'envelopes_local is append-only'); END",
  'CREATE TRIGGER IF NOT EXISTS envelopes_local_append_only_delete '
      "BEFORE DELETE ON envelopes_local BEGIN SELECT RAISE(ABORT, 'envelopes_local is append-only; use rebootstrapBook'); END",
];
