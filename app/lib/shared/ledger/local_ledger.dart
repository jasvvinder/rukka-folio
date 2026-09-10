// The app's one door to the ledger: `LocalLedger` composes the real packages
// (core_ledger 02 · core_crypto 04 · data 03) over the `KeyStore` seam so a
// screen never touches an envelope, a key or a projector directly.
//
// Write path (the harness's SimulatedDevice with real envelopes): the event is
// checked against 02 §1.4/§2 shapes, given this device's next `author_seq`
// from the mirror (ADR 2026-09-05b §3) and an HLC ticked from the injected
// clock, sealed with `EnvelopeBuilder.seal` under the book's current key,
// appended to `envelopes_local`, queued in `outbox`, and the book's
// projections are rebuilt by `Recompute` — the only place rows are written.
//
// Read path: Drift streams over Layer 2 (03 §3.2) shaped for 07 §4 / §6 / §7.
// Every amount is signed integer paise with the engine's convention (+ = Dr,
// − = Cr); the vocabulary a screen speaks is decided in `shared/format`
// (02 §10 🔒) — nothing here bends to it.
//
// Rules kept: no `DateTime.now()` (clock injected), no `Random()` (ids from the
// suite's libsodium CSPRNG), append-only (never UPDATE/DELETE an envelope),
// unknown fields round-trip (amend/reverse copy the projected `Entry`, which
// carries `extra`), keys only through `KeyStore`, book keys wrapped to a
// *verified* UMK only (04 §8.2 — the type system insists).
import 'dart:async';
import 'dart:convert';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart';

import '../seams/key_store.dart';

/// Ids this facade keeps in the [KeyStore] beside [KeyIds]. The identity
/// record is not secret (device/user/tenant ids) but the seam is the only
/// persistent store the shell offers outside the ledger database.
abstract final class LocalLedgerKeys {
  /// JSON `{device_id, user_id, tenant_id, suite_version}` (all uuids).
  static const identity = 'rk.ledger.identity';
}

/// Who this install is: the ids every envelope is stamped with (04 §4).
final class LedgerIdentity {
  /// Creates the identity.
  const LedgerIdentity({
    required this.deviceId,
    required this.userId,
    required this.tenantId,
  });

  /// `author_device_id` — canonical uuid (04 §3.3).
  final String deviceId;

  /// `created_by_user` — canonical uuid.
  final String userId;

  /// `tenant_id` in every AAD (04 §4).
  final String tenantId;
}

/// A posting the engine refused *before* it was sealed (02 §1.4, §2, §5).
/// Nothing was appended; the caller shows the reasons (07 §1 rule 6: explain
/// and offer the path — e.g. `periodLocked` → *Fix an old entry*).
final class PostRejected implements Exception {
  /// Creates the rejection.
  const PostRejected(this.entryId, this.violations);

  /// The draft's id.
  final String entryId;

  /// Why — never empty.
  final List<Violation> violations;

  /// True when any violation is of [kind].
  bool has(ViolationKind kind) => violations.any((v) => v.kind == kind);

  @override
  String toString() => 'PostRejected($entryId: ${violations.join('; ')})';
}

/// The facade was used before [LocalLedger.bootstrapSolo] (or `open`).
final class LedgerNotOpen implements Exception {
  /// Creates the error.
  const LedgerNotOpen();

  @override
  String toString() => 'LedgerNotOpen: call bootstrapSolo() first';
}

/// One line of the Home position card (07 §4; 02 §9). Every figure is signed
/// integer paise in the engine's convention.
final class Position {
  /// Creates the position.
  const Position({
    required this.bookId,
    required this.totalMoneyPaise,
    required this.cashPaise,
    required this.banks,
    required this.youWillGetPaise,
    required this.youWillGivePaise,
    required this.advancesOutPaise,
    required this.inTransitPaise,
  });

  /// Book.
  final String bookId;

  /// *Total money you have*: Σ every `money` account (overdrafts subtract).
  final int totalMoneyPaise;

  /// Σ `money` accounts of subtype `cash`.
  final int cashPaise;

  /// Each non-cash `money` account (banks, cards, loans, wallets) and its
  /// balance, in creation order.
  final List<AccountBalance> banks;

  /// Σ Dr party balances (they owe you) — positive or zero.
  final int youWillGetPaise;

  /// Σ |Cr party balances| (you owe them) — positive or zero.
  final int youWillGivePaise;

  /// Σ `advance` balances (advances given out, awaiting spend or return).
  final int advancesOutPaise;

  /// Σ *Due to/from* balances — money between your books (02 §6), signed.
  final int inTransitPaise;
}

/// An account with its live balance — one row of the A–Z Ledger index (07 §6).
final class AccountBalance {
  /// Creates the row.
  const AccountBalance({
    required this.account,
    required this.balancePaise,
    required this.archived,
    this.usualCategoryId,
  });

  /// The engine account (class, subtype, role).
  final Account account;

  /// Signed paise (+ = Dr).
  final int balancePaise;

  /// Hidden from pickers (02 §1.2).
  final bool archived;

  /// Quick-entry default for a party (02 §1.2).
  final String? usualCategoryId;
}

/// One row of an A/C statement (07 §6, design-system §5): the account's own
/// line of an entry, the other side(s), and the running balance after it.
/// Both vocabularies read from the same figures: consumer surfaces take
/// [amountPaise] (signed); professional surfaces take [debitPaise] /
/// [creditPaise] (absolute, one of them zero) — 02 §10, A-02-10.
final class StatementRow {
  /// Creates the row.
  const StatementRow({
    required this.entryId,
    required this.accountId,
    required this.date,
    required this.kind,
    required this.status,
    required this.reviewState,
    required this.amountPaise,
    required this.runningBalancePaise,
    required this.counterAccountIds,
    required this.hlc,
    this.note,
    this.channel,
  });

  /// Entry.
  final String entryId;

  /// The account whose statement this is.
  final String accountId;

  /// `accounting_date`.
  final LocalDate date;

  /// Verb.
  final EntryKind kind;

  /// Effective status as projected (`posted`, `void`, `in_tray` …).
  final String status;

  /// `none | open | approved | rejected` (03 §3.3.5).
  final String reviewState;

  /// This account's signed line (+ = Dr, − = Cr).
  final int amountPaise;

  /// Balance after this row, ordered by `(accounting_date, hlc, entry_id)`
  /// (02 §9).
  final int runningBalancePaise;

  /// The other account(s) of the entry — the *particulars* column.
  final List<String> counterAccountIds;

  /// Entry HLC.
  final int hlc;

  /// Note.
  final String? note;

  /// `upi | card | netbanking | cash` (02 §1.3).
  final String? channel;

  /// Debit column figure (absolute), zero when the line is a credit.
  int get debitPaise => amountPaise > 0 ? amountPaise : 0;

  /// Credit column figure (absolute), zero when the line is a debit.
  int get creditPaise => amountPaise < 0 ? -amountPaise : 0;

  /// Ledger side of this line.
  Side? get side => Paise(amountPaise).side;
}

/// An entry as the Ledger tab shows it (audit trail one tap away, 07 §1
/// rule 8): the projected row plus its lines.
final class EntryView {
  /// Creates the view.
  const EntryView({
    required this.id,
    required this.bookId,
    required this.kind,
    required this.status,
    required this.date,
    required this.lines,
    required this.reviewState,
    required this.createdByUser,
    required this.hlc,
    this.note,
    this.channel,
    this.partyId,
    this.amends,
    this.reverses,
    this.supersededBy,
  });

  /// Entry id.
  final String id;

  /// Book.
  final String bookId;

  /// Verb.
  final EntryKind kind;

  /// Effective status wire (`posted`, `void`, `superseded`, …).
  final String status;

  /// `accounting_date`.
  final LocalDate date;

  /// Lines in order.
  final List<Line> lines;

  /// Review flag state.
  final String reviewState;

  /// Author.
  final String createdByUser;

  /// HLC.
  final int hlc;

  /// Note.
  final String? note;

  /// Channel tag.
  final String? channel;

  /// Party, when the verb touched one.
  final String? partyId;

  /// `refs.amends`.
  final String? amends;

  /// `refs.reverses`.
  final String? reverses;

  /// The amendment that replaced this entry, if any (02 §5).
  final String? supersededBy;

  /// Head of its amend chain — the version views show.
  bool get isHead => supersededBy == null;
}

/// What S1.4 / the sync chip need about a book's projection (07 §1 rule 7,
/// ADR 2026-09-05b §3–4, 05c §6).
final class BookHealth {
  /// Creates the report.
  const BookHealth({
    required this.bookId,
    required this.integrityOk,
    required this.needsRebootstrap,
    required this.heldCount,
    required this.authorGapCount,
    required this.quarantinedCount,
  });

  /// Book.
  final String bookId;

  /// `books_p.integrity_ok`.
  final bool integrityOk;

  /// Blob hash failed — re-bootstrap (ADR 05c §6).
  final bool needsRebootstrap;

  /// Envelopes waiting for a target that has not arrived (`held`).
  final int heldCount;

  /// Open `author_seq` holes — *Waiting for entries from {name}'s phone*.
  final int authorGapCount;

  /// Envelopes an honest reader refused.
  final int quarantinedCount;

  /// The projection is provisional (02 §5, 07 §1 rule 7).
  bool get isProvisional => heldCount > 0 || authorGapCount > 0;
}

/// The local ledger.
final class LocalLedger {
  /// Creates the facade. [suite] is the app's libsodium binding wrapped in a
  /// [CryptoSuite]; [now] is the injected wall clock the HLC ticks against.
  LocalLedger({
    required this.db,
    required this.keys,
    required this.suite,
    required this.now,
  }) : mirror = Mirror(db, hasher: blake2bHasher(suite)) {
    recompute = Recompute(
      db,
      mirror: mirror,
      opener: CryptoPayloadOpener(suite, _keySource),
    );
  }

  /// The open database (03).
  final LedgerDatabase db;

  /// Secrets at rest (04 §3.3).
  final KeyStore keys;

  /// libsodium + CSPRNG.
  final CryptoSuite suite;

  /// Injected clock (09 §1).
  final DateTime Function() now;

  /// Envelope mirror + outbox (03 §3.1).
  final Mirror mirror;

  /// Projection rebuilder (03 §3.3).
  late final Recompute recompute;

  final InMemoryKeySource _keySource = InMemoryKeySource();
  final Map<String, BookRecompute> _last = {};

  LedgerIdentity? _identity;
  DeviceKeyPair? _device;
  UmkKeyPair? _umk;
  VerifiedUmkPublic? _umkVerified;
  Hlc _clock = const Hlc(0);

  /// True after [bootstrapSolo] (or a successful re-open).
  bool get isOpen => _identity != null;

  /// This install's ids; throws [LedgerNotOpen] before bootstrap.
  LedgerIdentity get identity => _identity ?? (throw const LedgerNotOpen());

  /// The last Recompute report for [bookId] (S1.4), if the book was rebuilt
  /// in this process.
  BookRecompute? lastRecompute(String bookId) => _last[bookId];

  // ── bootstrap ─────────────────────────────────────────────────────────────

  /// First run of a solo user (07 §3.1, 04 §3.1–§3.4): mints device, user and
  /// tenant ids, generates the device keys and the UMK from the suite's
  /// CSPRNG, self-verifies the device (the first device holds the UMK, 04
  /// §3.4), wraps the UMK to it and stores everything through [keys]. When
  /// [firstBookName] is given and no book exists, the first book (with its
  /// key, v1) is created too. Idempotent: a second call — or a new
  /// [LocalLedger] over the same store — reopens the same identity and posts
  /// with the same device.
  Future<LedgerIdentity> bootstrapSolo({
    String? firstBookName,
    BookType firstBookType = BookType.personal,
    String openingBalanceName = 'Opening Balance',
    LocalDate? startDate,
  }) async {
    if (_identity == null) {
      final stored = await keys.read(LocalLedgerKeys.identity);
      if (stored != null) {
        await _reopen(stored);
      } else {
        await _firstRun();
      }
    }
    if (firstBookName != null && (await mirror.bookIds()).isEmpty) {
      await createBook(
        name: firstBookName,
        type: firstBookType,
        openingBalanceName: openingBalanceName,
        startDate: startDate,
      );
    }
    return _identity!;
  }

  Future<void> _firstRun() async {
    final deviceId = newId();
    final userId = newId();
    final tenantId = newId();

    final edSeed = suite.randomBytes(32);
    final xSeed = suite.randomBytes(32);
    final DeviceKeyPair device;
    try {
      device = _deviceFromSeeds(deviceId, edSeed, xSeed);
      await keys.write(KeyIds.deviceSigningKey, edSeed);
      await keys.write(KeyIds.deviceAgreementKey, xSeed);
    } finally {
      suite.zeroize(edSeed);
      suite.zeroize(xSeed);
    }

    final umk = UmkKeyPair.generate(suite);
    final wrapped = wrapUmkToDevice(suite, umk, _selfVerifyDevice(device));
    await keys.write(KeyIds.wrappedUmk, wrapped.bytes);

    final record = <String, Object?>{
      'device_id': deviceId,
      'user_id': userId,
      'tenant_id': tenantId,
      'suite_version': suiteVersion,
    };
    await keys.write(
      LocalLedgerKeys.identity,
      Uint8List.fromList(utf8.encode(jsonEncode(record))),
    );

    _device = device;
    _umk = umk;
    _umkVerified = _selfVerifyUmk(umk, userId);
    _identity = LedgerIdentity(
      deviceId: deviceId,
      userId: userId,
      tenantId: tenantId,
    );
  }

  Future<void> _reopen(Uint8List identityBytes) async {
    final record =
        jsonDecode(utf8.decode(identityBytes)) as Map<String, Object?>;
    final id = LedgerIdentity(
      deviceId: record['device_id'] as String,
      userId: record['user_id'] as String,
      tenantId: record['tenant_id'] as String,
    );
    final edSeed = await keys.read(KeyIds.deviceSigningKey);
    final xSeed = await keys.read(KeyIds.deviceAgreementKey);
    final wrappedUmk = await keys.read(KeyIds.wrappedUmk);
    if (edSeed == null || xSeed == null || wrappedUmk == null) {
      throw StateError('identity present but device keys missing — recovery');
    }
    final DeviceKeyPair device;
    try {
      device = _deviceFromSeeds(id.deviceId, edSeed, xSeed);
    } finally {
      suite.zeroize(edSeed);
      suite.zeroize(xSeed);
    }
    final umk = unwrapUmk(
      suite,
      WrappedUmk(deviceId: id.deviceId, bytes: wrappedUmk),
      device,
    );
    _device = device;
    _umk = umk;
    _umkVerified = _selfVerifyUmk(umk, id.userId);
    _identity = id;

    // Tenants and wrapped book keys back into memory (03 §3.1 key_cache).
    for (final b in await db.select(db.booksP).get()) {
      _keySource.tenants[b.id] = b.tenantId;
    }
    for (final row in await db.select(db.keyCache).get()) {
      _keySource.tenants.putIfAbsent(row.bookId, () => id.tenantId);
      final ref = BookKeyRef(bookId: row.bookId, keyVersion: row.keyVersion);
      _keySource.keys[ref] = unwrapBookKey(
        suite,
        _decodeWrappedBookKey(ref, row.wrappedBlob),
        umk,
      );
    }
    await _seedClock();
    for (final bookId in await mirror.bookIds()) {
      await _rebuild(bookId);
    }
  }

  /// Rebuilds a [DeviceKeyPair] from its two 32-byte seeds by replaying them
  /// through `DeviceKeyPair.generate` on a suite whose random source is the
  /// stored seeds — the same determinism path suite B relies on. ⚠️ SPEC: a
  /// `DeviceKeyPair.fromSeeds` factory in core_crypto would make this direct.
  DeviceKeyPair _deviceFromSeeds(String deviceId, Uint8List ed, Uint8List x) {
    final queue = <Uint8List>[Uint8List.fromList(ed), Uint8List.fromList(x)];
    final replay = CryptoSuite(
      suite.sodium,
      random: (int n) {
        if (queue.isEmpty) throw StateError('device seed replay exhausted');
        final next = queue.removeAt(0);
        if (next.length != n) {
          throw StateError('device seed is ${next.length} bytes, need $n');
        }
        return next;
      },
    );
    return DeviceKeyPair.generate(replay, deviceId: deviceId);
  }

  /// The first device verifies its own keys byte-for-byte through the
  /// ceremony module — the only producer of [VerifiedDevicePublic] — so the
  /// UMK is wrapped to a verified device by construction (04 §3.4, §8.2).
  VerifiedDevicePublic _selfVerifyDevice(DeviceKeyPair device) {
    final r = Ceremony.verifyDeviceQr(
      suite,
      scanned: DeviceQrPayload(
        device: device.public,
        nonce: suite.randomBytes(ceremonyNonceBytes),
      ),
      relayed: device.public,
    );
    return switch (r) {
      DeviceVerified(:final verified) => verified,
      DeviceMismatch() => throw StateError('device self-verification failed'),
    };
  }

  /// Same for the user's own UMK: book keys are wrapped only to a
  /// [VerifiedUmkPublic] (04 §8.2), and the owner's own fingerprint is
  /// verified by the same byte-for-byte check.
  VerifiedUmkPublic _selfVerifyUmk(UmkKeyPair umk, String userId) {
    final r = Ceremony.verifyQr(
      suite,
      scanned: QrPayload(
        userId: userId,
        umk: umk.public,
        nonce: suite.randomBytes(ceremonyNonceBytes),
      ),
      relayed: umk.public,
      relayedUserId: userId,
    );
    return switch (r) {
      CeremonyVerified(:final verified) => verified,
      _ => throw StateError('UMK self-verification failed'),
    };
  }

  Future<void> _seedClock() async {
    final maxHlc = db.envelopesLocal.hlc.max();
    final row = await (db.selectOnly(
      db.envelopesLocal,
    )..addColumns([maxHlc])).getSingle();
    final v = row.read(maxHlc);
    if (v != null && v > _clock.raw) _clock = Hlc(v);
  }

  // ── ids, clock, keys ──────────────────────────────────────────────────────

  /// A fresh canonical uuid (v4 layout) from libsodium's CSPRNG — entry,
  /// account, book and envelope ids (04 §4 requires canonical uuids).
  String newId() {
    final b = suite.randomBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    return Uuid16.fromBytes(b);
  }

  Hlc _tick() => _clock = _clock.tick(physicalMs: now().millisecondsSinceEpoch);

  /// Today per the injected clock, as the ledger's calendar day.
  LocalDate today() {
    final t = now();
    return LocalDate(t.year, t.month, t.day);
  }

  BookKey _currentKey(String bookId) {
    BookKey? best;
    for (final MapEntry(key: ref, value: key) in _keySource.keys.entries) {
      if (ref.bookId != bookId) continue;
      if (best == null || ref.keyVersion > best.ref.keyVersion) best = key;
    }
    return best ?? (throw StateError('no key for book $bookId'));
  }

  /// `suite_version(1) ‖ recipient fingerprint(32) ‖ sealed box` — the
  /// `key_cache.wrapped_blob` layout (03 §3.1; BKs rest wrapped to the UMK).
  static Uint8List _encodeWrappedBookKey(WrappedBookKey w) =>
      Bytes.concat([Bytes.u8(w.suiteVersion), w.recipient.bytes, w.blob]);

  static WrappedBookKey _decodeWrappedBookKey(BookKeyRef ref, Uint8List blob) =>
      WrappedBookKey(
        ref: ref,
        sealed: SealedBlob(
          suiteVersion: blob[0],
          recipient: Fingerprint(Uint8List.sublistView(blob, 1, 33)),
          bytes: Uint8List.sublistView(blob, 33),
        ),
      );

  void _requireOpen() {
    if (_identity == null) throw const LedgerNotOpen();
  }

  // ── books and accounts ────────────────────────────────────────────────────

  /// Creates a book (02 §1.1): mints its id and key v1 (wrapped to the
  /// verified UMK into `key_cache`), authors the `book_config` envelope and
  /// the *Opening Balance* system account (02 §4 needs it), rebuilds.
  Future<String> createBook({
    required String name,
    required BookType type,
    int fyStartMonth = 4,
    BookOwnership ownership = BookOwnership.justMe,
    String openingBalanceName = 'Opening Balance',
    String drawingsName = 'Drawings',
    String profitDistributedName = 'Profit Distributed',
    List<String> ownerNames = const [],
    LocalDate? startDate,
  }) async {
    _requireOpen();
    final id = _identity!;
    final bookId = newId();
    final bk = BookKey.generate(suite, bookId: bookId, keyVersion: 1);
    final wrapped = wrapBookKey(suite, bk, _umkVerified!);
    await db
        .into(db.keyCache)
        .insert(
          KeyCacheCompanion.insert(
            bookId: bookId,
            keyVersion: 1,
            wrappedBlob: _encodeWrappedBookKey(wrapped),
          ),
        );
    _keySource.keys[bk.ref] = bk;
    _keySource.tenants[bookId] = id.tenantId;

    final config = BookConfig(
      id: bookId,
      tenantId: id.tenantId,
      type: type,
      name: name,
      fyStartMonth: fyStartMonth,
      ownership: ownership,
      // ADR 2026-09-09d §4: the books begin on the day the book is made —
      // stamped once, never moved. The UI never offers a picker (owner-ruled:
      // read-only today); the parameter exists for fixtures and imports.
      startDate: startDate ?? today(),
    );
    await _author(
      bookId: bookId,
      objectId: bookId,
      objectType: 'book_config',
      hlc: _tick(),
      object: (_) => config.toJson(),
    );
    await addAccount(
      bookId,
      name: openingBalanceName,
      accountClass: AccountClass.equitySystem,
      systemRole: SystemRole.openingBalance,
    );
    // ADR 2026-09-09b §2: the Capital/Drawings pair belongs to a *Just me*
    // business. Capital is the Opening Balance account above — both worked
    // examples name it `Opening Balance / Capital A/c`, so it is not a second
    // account. A shared business gets one Partner Current A/c per owner
    // instead, which 02 §7.1 calls the single place that relationship lives.
    if (type == BookType.business && ownership == BookOwnership.justMe) {
      await addAccount(
        bookId,
        name: drawingsName,
        accountClass: AccountClass.equitySystem,
        systemRole: SystemRole.drawings,
      );
    }
    // ADR 2026-09-09c §1: a shared business seeds `Profit Distributed` and
    // **one `{Name} — Partner Current A/c` per owner** — the names come from
    // S0.6a1 ([ownerNames], in the order shown there, the creating user
    // first). 02 §7.1 calls the Partner Current A/c the single place that
    // relationship lives, which is why an owner's opening contribution posts
    // there and never to a Capital account (ADR 2026-09-09c §4).
    //
    // ⚠️ SPEC: the **share weights** collected on S0.6a1 have nowhere to
    // persist — `BookConfig` (packages/data) carries `ownership` but no
    // partner ratio, and `PartnerShare` takes its weight per call at
    // distribution time (verbs.dart:432). The weights are therefore held by
    // the caller for now; giving them a home is a `packages/data` change and
    // is recorded in the lane report rather than invented here.
    if (type == BookType.business && ownership == BookOwnership.shared) {
      await addAccount(
        bookId,
        name: profitDistributedName,
        accountClass: AccountClass.equitySystem,
        systemRole: SystemRole.profitDistributed,
      );
      for (final owner in ownerNames) {
        await addAccount(
          bookId,
          name: partnerCurrentAccountName(owner),
          accountClass: AccountClass.partner,
        );
      }
    }
    return bookId;
  }

  /// `{Name} — Partner Current A/c`, the seeded name of an owner's partner
  /// account (ADR 2026-09-09c §1, 02 §7.1). Editable afterwards like any
  /// seeded name; the engine keys on the account id, never on this string.
  static String partnerCurrentAccountName(String owner) =>
      '$owner — Partner Current A/c';

  /// Books this device holds, as projected.
  Stream<List<BooksPData>> watchBooks() => db.select(db.booksP).watch();

  /// The day [bookId]'s books begin (ADR 2026-09-09d §4), or null for a book
  /// written before the ADR. Read from the projection, so a book that arrived
  /// by sync carries its boundary the moment its config is projected.
  Future<LocalDate?> startDateOf(String bookId) async {
    final row = await (db.select(
      db.booksP,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    final iso = row?.startDate;
    return iso == null ? null : LocalDate.parse(iso);
  }

  /// Adds an account (02 §1.2 — created inline, class inferred by the caller
  /// from the picker slot) and rebuilds the book. Returns the engine account.
  Future<Account> addAccount(
    String bookId, {
    required String name,
    required AccountClass accountClass,
    MoneySubtype? subtype,
    SystemRole? systemRole,
    String? usualCategoryId,
    String? counterpartBookId,
    String? memberId,
  }) async {
    _requireOpen();
    final countExp = db.envelopesLocal.envelopeId.count();
    final order =
        await (db.selectOnly(db.envelopesLocal)
              ..addColumns([countExp])
              ..where(
                db.envelopesLocal.bookId.equals(bookId) &
                    db.envelopesLocal.objectType.equals('account'),
              ))
            .map((r) => r.read(countExp)!)
            .getSingle();
    final account = Account(
      id: newId(),
      bookId: bookId,
      name: name,
      accountClass: accountClass,
      subtype: subtype,
      systemRole: systemRole,
      memberId: memberId,
      counterpartBookId: counterpartBookId,
      createdOrder: order,
    );
    await _author(
      bookId: bookId,
      objectId: account.id,
      objectType: 'account',
      hlc: _tick(),
      object: (_) =>
          AccountPayload(account, usualCategoryId: usualCategoryId).toJson(),
    );
    await _rebuild(bookId);
    return account;
  }

  /// The chart as last projected (rebuilding if this process has not yet).
  Future<Chart> chartOf(String bookId) async =>
      (_last[bookId] ?? await _rebuild(bookId)).chart;

  Future<LedgerState> _stateOf(String bookId) async =>
      (_last[bookId] ?? await _rebuild(bookId)).state;

  // ── posting ───────────────────────────────────────────────────────────────

  /// Posts a drafted entry (02 §3: it counts the moment it is saved). The
  /// draft's `hlc`, `createdByDevice` and `authorSeq` are stamped here; its
  /// id is kept when it is a canonical uuid, else minted. Checks 02 §1.4
  /// invariants, the §2 shape, the authoring rules (no future date) and the
  /// period lock (§8) first — a failure throws [PostRejected] and appends
  /// nothing.
  Future<Entry> post(Entry draft) async {
    _requireOpen();
    final id = _identity!;
    final chart = await chartOf(draft.bookId);
    final state = await _stateOf(draft.bookId);
    final hlc = _tick();
    var entry = draft.copyWith(
      id: Uuid16.isCanonical(draft.id) ? draft.id : newId(),
      hlc: hlc,
      createdByDevice: id.deviceId,
    );
    final violations = <Violation>[
      ...checkUniversalInvariants(entry, chart),
      ...checkAuthoringRules(entry, today: today()),
    ];
    final shape = checkShape(entry, chart);
    if (shape != null) violations.add(shape);
    final period = entry.accountingDate.yearMonth;
    if (state.periods.currentStatus(period) == PeriodStatus.locked) {
      violations.add(
        Violation(ViolationKind.periodLocked, '$period is locked (02 §8)'),
      );
    }
    // ADR 2026-09-09d §4/§4a: nothing is dated before the books begin. An
    // authoring guard only — a reader never rejects, quarantines or hides an
    // earlier-dated entry that arrives by sync (§4b routes it to the Inbox).
    final start = await startDateOf(entry.bookId);
    if (start != null && entry.accountingDate.compareTo(start) < 0) {
      violations.add(
        Violation(
          ViolationKind.beforeBookStart,
          '${entry.accountingDate} is before the books begin ($start); '
          'the opening balance already includes it (ADR 2026-09-09d §4)',
        ),
      );
    }
    if (violations.isNotEmpty) throw PostRejected(entry.id, violations);

    await _author(
      bookId: entry.bookId,
      objectId: entry.id,
      objectType: 'entry',
      hlc: hlc,
      object: (seq) {
        entry = entry.copyWith(authorSeq: seq);
        return encodeEvent(entry);
      },
    );
    await _rebuild(entry.bookId);
    return entry;
  }

  Entry _draft({
    required String bookId,
    required EntryKind kind,
    required List<Line> lines,
    required LocalDate date,
    String? note,
    String? channel,
    String? partyId,
    String? advanceId,
  }) => Entry(
    id: newId(),
    bookId: bookId,
    kind: kind,
    status: EntryStatus.posted,
    reviewRequired: false,
    accountingDate: date,
    lines: lines,
    note: note,
    partyId: partyId,
    advanceId: advanceId,
    createdByUser: identity.userId,
    createdByDevice: identity.deviceId,
    hlc: _clock,
    extra: channel == null ? const {} : {'channel': channel},
  );

  String? _partyOf(Account a) =>
      a.accountClass == AccountClass.party ? a.id : null;

  /// Verb 1 — *Money in* (02 §2): Dr [into] (cash/bank) · Cr [from]
  /// (income category or party).
  Future<Entry> moneyIn({
    required String bookId,
    required String into,
    required String from,
    required int paise,
    required LocalDate date,
    String? note,
    String? channel,
  }) async {
    final c = await chartOf(bookId);
    final fromA = c.account(from);
    return post(
      _draft(
        bookId: bookId,
        kind: EntryKind.moneyIn,
        lines: Verbs.moneyIn(
          into: c.account(into),
          from: fromA,
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        channel: channel,
        partyId: _partyOf(fromA),
      ),
    );
  }

  /// Verb 2 — *Money out*: Dr [forWhat] (expense category or party) ·
  /// Cr [from] (cash/bank).
  Future<Entry> moneyOut({
    required String bookId,
    required String from,
    required String forWhat,
    required int paise,
    required LocalDate date,
    String? note,
    String? channel,
  }) async {
    final c = await chartOf(bookId);
    final forA = c.account(forWhat);
    return post(
      _draft(
        bookId: bookId,
        kind: EntryKind.moneyOut,
        lines: Verbs.moneyOut(
          from: c.account(from),
          forWhat: forA,
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        channel: channel,
        partyId: _partyOf(forA),
      ),
    );
  }

  /// Verb 3 — *Gave on credit*: Dr [toWhom] (party) · Cr [gave] (money or
  /// income category).
  Future<Entry> gaveCredit({
    required String bookId,
    required String toWhom,
    required String gave,
    required int paise,
    required LocalDate date,
    String? note,
  }) async {
    final c = await chartOf(bookId);
    return post(
      _draft(
        bookId: bookId,
        kind: EntryKind.gaveCredit,
        lines: Verbs.gaveCredit(
          toWhom: c.account(toWhom),
          gave: c.account(gave),
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        partyId: toWhom,
      ),
    );
  }

  /// Verb 4 — *Took on credit*: Dr [took] (money or expense category) ·
  /// Cr [fromWhom] (party).
  Future<Entry> tookCredit({
    required String bookId,
    required String fromWhom,
    required String took,
    required int paise,
    required LocalDate date,
    String? note,
  }) async {
    final c = await chartOf(bookId);
    return post(
      _draft(
        bookId: bookId,
        kind: EntryKind.tookCredit,
        lines: Verbs.tookCredit(
          fromWhom: c.account(fromWhom),
          took: c.account(took),
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        partyId: fromWhom,
      ),
    );
  }

  /// Verb 5 — *Transfer* within a book: Dr [to] · Cr [from], two money
  /// accounts (or one *Due to/from*, 02 §6).
  Future<Entry> transfer({
    required String bookId,
    required String from,
    required String to,
    required int paise,
    required LocalDate date,
    String? note,
    String? channel,
  }) async {
    final c = await chartOf(bookId);
    return post(
      _draft(
        bookId: bookId,
        kind: EntryKind.transfer,
        lines: Verbs.transfer(
          from: c.account(from),
          to: c.account(to),
          amount: Paise(paise),
        ),
        date: date,
        note: note,
        channel: channel,
      ),
    );
  }

  /// Verb 6, guided — *Opening balances* (02 §4): one `adjustment` per
  /// account against *Opening Balance*. [balances] maps account id → signed
  /// paise as the user answered by class: money = *balance today* (negative
  /// = overdraft); party = + *you will get* / − *you will give*; advance =
  /// held. Zero balances post nothing. The entries need not net to zero —
  /// Opening Balance absorbs the difference.
  ///
  /// [date] defaults to the book's start date (ADR 2026-09-09d §4): an opening
  /// balance describes the position on the day the books began, whenever the
  /// account happens to be added. Pass a later date only when that month is
  /// already locked — the 02 §8.1 pattern, the fix lands in the open period.
  Future<List<Entry>> openingBalances(
    String bookId, {
    required Map<String, int> balances,
    LocalDate? date,
  }) async {
    final when = date ?? await startDateOf(bookId) ?? today();
    final c = await chartOf(bookId);
    final opening = c
        .byClass(AccountClass.equitySystem)
        .firstWhere(
          (a) => a.systemRole == SystemRole.openingBalance,
          orElse: () =>
              throw StateError('book $bookId has no Opening Balance account'),
        );
    final out = <Entry>[];
    for (final MapEntry(key: accountId, value: paise) in balances.entries) {
      if (paise == 0) continue;
      final account = c.account(accountId);
      out.add(
        await post(
          _draft(
            bookId: bookId,
            kind: EntryKind.adjustment,
            lines: Verbs.openingBalance(
              account: account,
              balance: Paise(paise),
              openingAccount: opening,
            ),
            date: when,
            partyId: _partyOf(account),
          ),
        ),
      );
    }
    return out;
  }

  // ── corrections (02 §5) ───────────────────────────────────────────────────

  /// Amends the head of an open-period entry: a new envelope, kind unchanged,
  /// `refs.amends = original`, complete replacement payload; fields not
  /// passed — including ones this client does not understand — are copied
  /// (03 §3.3.4). Rejects a non-head target (`amendNotHead`) or a locked
  /// period (`amendInLockedPeriod` → offer *Fix an old entry* = [reverse]).
  Future<Entry> amend(
    String entryId, {
    List<Line>? lines,
    LocalDate? accountingDate,
    String? note,
    String? partyId,
  }) async {
    _requireOpen();
    final (original, state) = await _projected(entryId);
    final violations = <Violation>[];
    if (original.supersededBy != null || state.headOf(entryId) != entryId) {
      violations.add(
        Violation(ViolationKind.amendNotHead, '$entryId is not the head'),
      );
    }
    final period = original.entry.accountingDate.yearMonth;
    if (state.periods.currentStatus(period) == PeriodStatus.locked) {
      violations.add(
        Violation(
          ViolationKind.amendInLockedPeriod,
          '$period is locked — reverse instead (02 §5)',
        ),
      );
    }
    if (violations.isNotEmpty) throw PostRejected(entryId, violations);
    return post(
      original.entry.amendWith(
        newId: newId(),
        hlc: _clock,
        lines: lines,
        accountingDate: accountingDate,
        note: note,
        partyId: partyId,
        createdByUser: identity.userId,
        createdByDevice: identity.deviceId,
      ),
    );
  }

  /// Reverses an entry (02 §5): the auto-built mirror — every line negated —
  /// dated [date] in the open period, `refs.reverses = original`, posted,
  /// never flagged. Both stay in history; the original shows as `void`.
  Future<Entry> reverse(
    String entryId, {
    required LocalDate date,
    String? note,
  }) async {
    _requireOpen();
    final (original, state) = await _projected(entryId);
    if (original.reversedBy != null) {
      throw PostRejected(entryId, [
        Violation(
          ViolationKind.alreadyReversed,
          '$entryId is already reversed by ${original.reversedBy}',
        ),
      ]);
    }
    if (state.headOf(entryId) != entryId) {
      throw PostRejected(entryId, [
        Violation(
          ViolationKind.amendNotHead,
          '$entryId was amended — reverse the head ${state.headOf(entryId)}',
        ),
      ]);
    }
    return post(
      original.entry.reversal(
        newId: newId(),
        hlc: _clock,
        accountingDate: date,
        createdByUser: identity.userId,
        createdByDevice: identity.deviceId,
        note: note,
      ),
    );
  }

  Future<(ProjectedEntry, LedgerState)> _projected(String entryId) async {
    final row = await (db.select(
      db.entriesP,
    )..where((t) => t.id.equals(entryId))).getSingleOrNull();
    if (row == null) throw ArgumentError.value(entryId, 'entryId', 'unknown');
    final state = await _stateOf(row.bookId);
    final p = state.entries[entryId];
    if (p == null) throw ArgumentError.value(entryId, 'entryId', 'unknown');
    return (p, state);
  }

  // ── the write path proper ─────────────────────────────────────────────────

  /// Seals [object] (built once the `author_seq` is known) under the book's
  /// current key, appends the envelope and queues it for push. One
  /// transaction: seq allocation, mirror row and outbox row land together.
  Future<EnvelopeRecord> _author({
    required String bookId,
    required String objectId,
    required String objectType,
    required Hlc hlc,
    required Map<String, Object?> Function(int authorSeq) object,
  }) {
    final id = _identity!;
    final device = _device!;
    final key = _currentKey(bookId);
    return db.transaction(() async {
      final seq = await mirror.nextAuthorSeq(bookId, id.deviceId);
      final envelopeId = newId();
      final env = EnvelopeBuilder.seal(
        suite,
        tenantId: id.tenantId,
        bookId: bookId,
        objectId: objectId,
        objectType: objectType,
        envelopeId: envelopeId,
        hlc: hlc.raw,
        authorSeq: seq,
        object: object(seq),
        bookKey: key,
        author: device,
      );
      final blob = env.blob;
      final rec = EnvelopeRecord(
        envelopeId: envelopeId,
        bookId: bookId,
        objectId: objectId,
        objectType: objectType,
        keyVersion: key.ref.keyVersion,
        hlc: hlc.raw,
        authorDevice: id.deviceId,
        authorSeq: seq,
        blob: blob,
        blobHash: env.blobHash(suite),
        // Our own signature over our own device: trusted by construction; the
        // sync engine sets the flag for others' envelopes after ChainVerifier.
        verified: true,
      );
      await mirror.append(rec);
      await mirror.enqueue(
        envelopeId: envelopeId,
        bookId: bookId,
        blob: blob,
        createdAt: now().millisecondsSinceEpoch,
      );
      return rec;
    });
  }

  Future<BookRecompute> _rebuild(String bookId) async {
    final report = (await recompute.run(bookId: bookId)).single;
    _last[bookId] = report;
    return report;
  }

  /// Full rebuild of one book (settings → *Recompute*; 02 §9).
  Future<BookRecompute> rebuild(String bookId) => _rebuild(bookId);

  // ── read side (03 §3.2 streams) ───────────────────────────────────────────

  /// Every account of [bookId] with its live balance, A–Z by name (07 §6).
  Stream<List<AccountBalance>> watchAccounts(String bookId) =>
      _watchAccountRows(bookId).map((rows) {
        final out = rows.toList()
          ..sort(
            (a, b) => a.account.name.toLowerCase().compareTo(
              b.account.name.toLowerCase(),
            ),
          );
        return out;
      });

  Stream<List<AccountBalance>> _watchAccountRows(String bookId) {
    final q = db.select(db.accountsP).join([
      leftOuterJoin(
        db.balances,
        db.balances.accountId.equalsExp(db.accountsP.id),
      ),
    ])..where(db.accountsP.bookId.equals(bookId));
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          AccountBalance(
            account: _accountOf(r.readTable(db.accountsP)),
            balancePaise: r.readTableOrNull(db.balances)?.balancePaise ?? 0,
            archived: r.readTable(db.accountsP).archived == 1,
            usualCategoryId: r.readTable(db.accountsP).usualCategoryId,
          ),
      ],
    );
  }

  static Account _accountOf(AccountsPData a) => AccountPayload.fromJson({
    'id': a.id,
    'book_id': a.bookId,
    'name': a.name,
    'class': a.accountClass,
    if (a.moneySubtype != null) 'money_subtype': a.moneySubtype,
    if (a.systemRole != null) 'system_role': a.systemRole,
    if (a.memberId != null) 'member_id': a.memberId,
    if (a.counterpartBookId != null) 'counterpart_book_id': a.counterpartBookId,
    'created_order': a.createdOrder,
  }).account;

  /// The Home position card (07 §4; 02 §9), live.
  Stream<Position> watchPosition(String bookId) =>
      _watchAccountRows(bookId).map((rows) {
        var total = 0, cash = 0, get = 0, give = 0, advances = 0, transit = 0;
        final banks = <AccountBalance>[];
        final ordered = rows.toList()
          ..sort(
            (a, b) => a.account.createdOrder.compareTo(b.account.createdOrder),
          );
        for (final r in ordered) {
          final a = r.account;
          final b = r.balancePaise;
          switch (a.accountClass) {
            case AccountClass.money:
              total += b;
              if (a.subtype == MoneySubtype.cash) {
                cash += b;
              } else if (a.subtype != MoneySubtype.cashCollection) {
                banks.add(r);
              }
            case AccountClass.party:
              if (b > 0) get += b;
              if (b < 0) give -= b;
            case AccountClass.advance:
              advances += b;
            case AccountClass.equitySystem:
              if (a.systemRole == SystemRole.dueToFrom) transit += b;
            case AccountClass.partner:
            case AccountClass.categoryIncome:
            case AccountClass.categoryExpense:
              break;
          }
        }
        return Position(
          bookId: bookId,
          totalMoneyPaise: total,
          cashPaise: cash,
          banks: banks,
          youWillGetPaise: get,
          youWillGivePaise: give,
          advancesOutPaise: advances,
          inTransitPaise: transit,
        );
      });

  /// The A/C statement of [accountId] (07 §6; design-system §5): heads of
  /// accepted amend chains only, advance requests still pending excluded,
  /// reversed entries and their mirrors both present (02 §9), ordered by
  /// `(accounting_date, hlc, entry_id)` with the running balance.
  Stream<List<StatementRow>> watchStatement(String accountId) {
    final l = db.entryLinesP;
    final e = db.entriesP;
    final q = db.customSelect(
      'SELECT l.entry_id, l.account_id, l.amount_paise, l.line_index, '
      'e.accounting_date, e.kind, e.status, e.review_state, e.note, '
      'e.channel, e.hlc '
      'FROM entry_lines_p l JOIN entries_p e ON e.id = l.entry_id '
      'WHERE l.entry_id IN '
      '(SELECT entry_id FROM entry_lines_p WHERE account_id = ?) '
      "AND e.superseded_by IS NULL AND e.status NOT IN ('pending','rejected') "
      'ORDER BY e.accounting_date, e.hlc, e.id, l.line_index',
      variables: [Variable.withString(accountId)],
      readsFrom: {l, e},
    );
    return q.watch().map((rows) {
      final out = <StatementRow>[];
      final others = <String, List<String>>{};
      final own = <String, QueryRow>{};
      final order = <String>[];
      for (final r in rows) {
        final entryId = r.read<String>('entry_id');
        if (!others.containsKey(entryId)) {
          others[entryId] = [];
          order.add(entryId);
        }
        if (r.read<String>('account_id') == accountId) {
          own[entryId] = r;
        } else {
          others[entryId]!.add(r.read<String>('account_id'));
        }
      }
      var running = 0;
      for (final entryId in order) {
        final r = own[entryId];
        if (r == null) continue;
        final amount = r.read<int>('amount_paise');
        running += amount;
        out.add(
          StatementRow(
            entryId: entryId,
            accountId: accountId,
            date: LocalDate.parse(r.read<String>('accounting_date')),
            kind: EntryKind.parse(r.read<String>('kind')),
            status: r.read<String>('status'),
            reviewState: r.read<String>('review_state'),
            amountPaise: amount,
            runningBalancePaise: running,
            counterAccountIds: List.unmodifiable(others[entryId]!),
            hlc: r.read<int>('hlc'),
            note: r.readNullable<String>('note'),
            channel: r.readNullable<String>('channel'),
          ),
        );
      }
      return out;
    });
  }

  /// One entry with its lines, or null.
  Future<EntryView?> entry(String id) async {
    final row = await (db.select(
      db.entriesP,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final lines =
        await (db.select(db.entryLinesP)
              ..where((t) => t.entryId.equals(id))
              ..orderBy([(t) => OrderingTerm.asc(t.lineIndex)]))
            .get();
    return EntryView(
      id: row.id,
      bookId: row.bookId,
      kind: EntryKind.parse(row.kind),
      status: row.status,
      date: LocalDate.parse(row.accountingDate),
      lines: [
        for (final l in lines)
          Line(accountId: l.accountId, amount: Paise(l.amountPaise)),
      ],
      reviewState: row.reviewState,
      createdByUser: row.createdByUser,
      hlc: row.hlc,
      note: row.note,
      channel: row.channel,
      partyId: row.partyId,
      amends: row.amends,
      reverses: row.reverses,
      supersededBy: row.supersededBy,
    );
  }

  /// Live health of [bookId]'s projection for S1.4 and the status chip.
  /// Emits nothing until the book is projected.
  Stream<BookHealth> watchHealth(String bookId) {
    final q = db.customSelect(
      'SELECT b.integrity_ok, b.needs_rebootstrap, '
      '(SELECT COUNT(*) FROM envelopes_local '
      ' WHERE book_id = ?1 AND held = 1) AS held, '
      '(SELECT COUNT(*) FROM author_gaps WHERE book_id = ?1) AS gaps, '
      '(SELECT COUNT(*) FROM envelopes_local '
      ' WHERE book_id = ?1 AND quarantined = 1) AS quarantined '
      'FROM books_p b WHERE b.id = ?1',
      variables: [Variable.withString(bookId)],
      readsFrom: {db.booksP, db.envelopesLocal, db.authorGaps},
    );
    return q
        .watchSingleOrNull()
        .where((r) => r != null)
        .map(
          (r) => BookHealth(
            bookId: bookId,
            integrityOk: r!.read<int>('integrity_ok') == 1,
            needsRebootstrap: r.read<int>('needs_rebootstrap') == 1,
            heldCount: r.read<int>('held'),
            authorGapCount: r.read<int>('gaps'),
            quarantinedCount: r.read<int>('quarantined'),
          ),
        );
  }

  /// Outbox rows still to push — the `Saved on phone · will sync (N)` count
  /// (07 §1 rule 7).
  Stream<int> watchPendingPushes() {
    final c = db.outbox.envelopeId.count();
    return (db.selectOnly(db.outbox)
          ..addColumns([c])
          ..where(db.outbox.pushState.isNotValue(PushState.observed.name)))
        .map((r) => r.read(c) ?? 0)
        .watchSingle();
  }

  /// Zeroises in-memory key material. The database is the caller's to close.
  void dispose() {
    for (final k in _keySource.keys.values) {
      k.dispose();
    }
    _keySource.keys.clear();
    _umk?.dispose();
    _device?.dispose();
    _umk = null;
    _device = null;
    _umkVerified = null;
    _identity = null;
  }
}
