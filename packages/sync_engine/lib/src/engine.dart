// The sync engine (05 §3–§5, §9; ADR 2026-09-05b §1–§7; ADR 2026-09-06 §3).
//
// One `sync()` is one round: meta/key channel first (05 §3 ordering rule),
// then per book: re-seal stale outbox rows, push in batches, pull by `seq`
// cursor, verify through the guard, project. Everything the server says is a
// claim: rows are believed only through their signed records, envelopes only
// after the chain passes and the blob decrypts once, and the device never
// wipes on the server's bare word. The clock and the network are injected —
// nothing here reads `DateTime.now()`, `Random()` or `dart:io`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart'
    show BookKeyRef, SignedRecordKind, suiteVersion;
import 'package:data/data.dart';
import 'package:drift/drift.dart' show Value, Variable;

import 'backoff.dart';
import 'events.dart';
import 'guard.dart';
import 'revocation.dart';
import 'status.dart';
import 'transport.dart';
import 'trust.dart';
import 'wire.dart';

/// The engine's life state. Only [active] syncs.
enum EngineMode {
  /// Syncing.
  active,

  /// Suspended on the server's *unsigned* word (ADR 05b §2): nothing wiped,
  /// sync stops; the next round that authenticates cleanly resumes.
  suspended,

  /// 426 — stop until the app updates.
  updateRequired,

  /// This device's verified revocation arrived — keys and mirror dropped.
  wiped,
}

/// What one `sync()` round did (counts only — never content).
final class SyncReport {
  /// Creates the report.
  const SyncReport({
    required this.pushed,
    required this.acked,
    required this.pulled,
    required this.verified,
    required this.quarantined,
    required this.keyWait,
    required this.epochChanged,
    required this.offline,
  });

  /// Envelopes sent in push batches.
  final int pushed;

  /// Envelopes acked this round.
  final int acked;

  /// Envelopes received from pulls.
  final int pulled;

  /// Envelopes marked verified this round.
  final int verified;

  /// Envelopes quarantined this round.
  final int quarantined;

  /// Envelopes waiting for a key at the end of the round.
  final int keyWait;

  /// Whether `store_epoch` changed (cursors reset, full re-pull).
  final bool epochChanged;

  /// Whether a transport call found no connectivity.
  final bool offline;

  @override
  String toString() =>
      'SyncReport(pushed $pushed, acked $acked, pulled $pulled, verified '
      '$verified, quarantined $quarantined, keyWait $keyWait'
      '${epochChanged ? ', epoch changed' : ''}${offline ? ', offline' : ''})';
}

/// A role fact as a verified `book_role` record states it (D-05b-1: the
/// record's value is the one the client keeps).
final class RoleFact {
  /// Creates the fact.
  const RoleFact({
    required this.recordId,
    required this.seq,
    required this.role,
    required this.limits,
  });

  /// Record.
  final String recordId;

  /// Record `seq`.
  final int seq;

  /// `role` — null when the record removed the role.
  final String? role;

  /// `limits` (plaintext JSON, 03 §4): `{auto_post_limit_paise: int}`.
  final Map<String, Object?>? limits;
}

/// A pulled envelope whose key has not arrived (05 §4 `key_wait`). Kept
/// outside the mirror: a mirror row needs the inner `author_seq`, which only
/// decryption yields. The book's cursor never passes a waiting envelope, so a
/// restart re-pulls it (idempotent) rather than losing it.
final class _Waiting {
  _Waiting(this.envelope, this.sinceMs);
  final WireEnvelope envelope;
  final int sinceMs;
  String get bookId => envelope.bookId;
  int get keyVersion => envelope.keyVersion;
}

final class _GapKey {
  const _GapKey(this.bookId, this.author, this.expected);
  final String bookId;
  final String author;
  final int expected;

  @override
  bool operator ==(Object o) =>
      o is _GapKey &&
      o.bookId == bookId &&
      o.author == author &&
      o.expected == expected;

  @override
  int get hashCode => Object.hash(bookId, author, expected);
}

/// The sync engine for one device in one tenant.
final class SyncEngine {
  /// Creates the engine. [recompute] rebuilds projections after a pull when
  /// given (the app and the harness pass one; wire tests may not).
  SyncEngine({
    required this.db,
    required this.mirror,
    required this.transport,
    required this.clock,
    required this.guard,
    required this.trust,
    required this.deviceId,
    required this.userId,
    required this.tenantId,
    this.recompute,
    this.jitter,
    Backoff backoff = const Backoff(),
    this.authorGapInboxMs = 24 * 60 * 60 * 1000,
    this.keyWaitInboxMs = 24 * 60 * 60 * 1000,
    this.unobservedInboxMs = 30 * 24 * 60 * 60 * 1000,
  }) : _backoff = backoff,
       _initialBackoff = backoff;

  /// The device's database.
  final LedgerDatabase db;

  /// Mirror + outbox facade.
  final Mirror mirror;

  /// The network door (injected).
  final SyncTransport transport;

  /// The clock (injected).
  final Clock clock;

  /// Verification seam.
  final EnvelopeGuard guard;

  /// Trust state the guard reads and this engine feeds.
  final RecordTrustStore trust;

  /// This device.
  final String deviceId;

  /// This device's user.
  final String userId;

  /// The tenant.
  final String tenantId;

  /// Projection rebuilder, if any.
  final Recompute? recompute;

  /// Backoff jitter source (null = none).
  final Jitter? jitter;

  /// Author gap → Inbox after this long (ADR 05b §3: 24 h).
  final int authorGapInboxMs;

  /// `key_wait` → Inbox after this long (05 §4: 24 h).
  final int keyWaitInboxMs;

  /// Acked-un-observed → Inbox after this long (ADR 05b §6: 30 days).
  final int unobservedInboxMs;

  // ── observable state ────────────────────────────────────────────────────

  /// Every event raised, in order.
  final List<SyncEvent> events = [];

  /// Listener for events as they happen.
  void Function(SyncEvent event)? onEvent;

  EngineMode _mode = EngineMode.active;

  /// Life state.
  EngineMode get mode => _mode;

  /// Books this engine syncs beside those the mirror and outbox already know.
  final Set<String> subscribedBooks = {};

  /// Books whose pushes stopped on `rejected:quota`; reads continue.
  final Set<String> quotaStoppedBooks = {};

  /// Books whose pushes stopped on `no_role` / `membership_not_active` /
  /// `unknown_book` until a new record says otherwise.
  final Set<String> pushBlockedBooks = {};

  bool _tenantFrozen = false;

  /// Whether pushes are stopped tenant-wide (`rejected:tenant_frozen`).
  bool get tenantFrozen => _tenantFrozen;

  Backoff _backoff;
  final Backoff _initialBackoff;
  int _retryPushAtMs = 0;
  bool _offline = false;
  String? _metaCursor;
  final Set<AttentionReason> _open = {};
  final Map<String, _Waiting> _keyWait = {};
  final Map<_GapKey, int> _gapFirstSeen = {};
  final Map<String, int> _ackedAtMs = {};
  final Map<String, int> _ackedSeqs = {};
  final Map<String, int> _lostCandidates = {};
  final Set<String> _staleRetried = {};
  final Set<String> _seenRecordIds = {};
  final Map<String, int?> _lastCutoff = {};
  final Map<String, int> _announcedKeyVersion = {};
  final Map<(String, String), RoleFact> _roles = {};
  final Map<String, (String, int)> _membershipStatus = {};
  bool _restored = false;
  bool _unsignedClaim = false;
  TransportFailure? _refusal;
  final Map<String, int> _batchCap = {};
  final Map<String, int> _batchBytesCap = {};

  /// Current backoff state (tests read the attempt count).
  Backoff get backoff => _backoff;

  /// Engine time before which pushes are not retried.
  int get retryPushAtMs => _retryPushAtMs;

  /// Envelope ids waiting for a book key.
  Set<String> get keyWaiting => Set.unmodifiable(_keyWait.keys);

  /// The verified role fact for (book, user), or null.
  RoleFact? roleOf(String bookId, String userId) => _roles[(bookId, userId)];

  /// Highest book-key version announced by a verified `key_rotation` record.
  int? announcedKeyVersion(String bookId) => _announcedKeyVersion[bookId];

  /// Connectivity changed (05 §3): reset the backoff.
  void connectivityChanged() {
    _backoff = _initialBackoff.reset();
    _retryPushAtMs = 0;
  }

  /// The Inbox handled a reason; it reappears when raised again.
  void dismiss(AttentionReason reason) => _open.remove(reason);

  /// Re-bootstraps [bookId] (05 §8; ADR 05c §6): drops the book's mirror
  /// rows and cursor — never the outbox — so the next round re-pulls it whole.
  /// Returns the rows dropped.
  Future<int> rebootstrapBook(String bookId) async {
    final n = await mirror.rebootstrapBook(bookId);
    _keyWait.removeWhere((_, w) => w.bookId == bookId);
    _gapFirstSeen.removeWhere((k, _) => k.bookId == bookId);
    return n;
  }

  /// The plan was upgraded (or the admin fixed the role): pushes and pulls of
  /// [bookId] resume.
  void resumeBook(String bookId) {
    quotaStoppedBooks.remove(bookId);
    pushBlockedBooks.remove(bookId);
    pullBlockedBooks.remove(bookId);
    _open.remove(AttentionReason.quota);
    if (pullBlockedBooks.isEmpty) _open.remove(AttentionReason.bookUnavailable);
  }

  /// Books whose pull the server refused (404 `unknown_book` / 403 `no_role`)
  /// until a new record or [resumeBook] says otherwise. Nothing is dropped.
  final Set<String> pullBlockedBooks = {};

  /// The freeze lifted: pushes resume tenant-wide.
  void freezeLifted() {
    _tenantFrozen = false;
    _open.remove(AttentionReason.tenantFrozen);
  }

  void _emit(SyncEvent e) {
    events.add(e);
    onEvent?.call(e);
  }

  int get _now => clock.nowMs();

  // ── status (05 §9: exactly five states) ─────────────────────────────────

  /// The status surface. Computed from persisted state + open reasons.
  Future<SyncStatus> status() async {
    final reasons = <AttentionReason>[..._open];
    void add(AttentionReason r) {
      if (!reasons.contains(r)) reasons.add(r);
    }

    if (_mode == EngineMode.updateRequired) add(AttentionReason.updateRequired);
    if (_mode == EngineMode.suspended) add(AttentionReason.suspended);
    final now = _now;
    for (final w in _keyWait.values) {
      if (now - w.sinceMs > keyWaitInboxMs) add(AttentionReason.keyWaitOverdue);
    }
    String? waitingFor;
    int? earliest;
    for (final MapEntry(key: g, value: since) in _gapFirstSeen.entries) {
      if (now - since > authorGapInboxMs) {
        add(AttentionReason.authorGapOverdue);
      } else if (earliest == null || since < earliest) {
        earliest = since;
        waitingFor = g.author;
      }
    }
    final rows = await mirror.outboxRows();
    var pending = 0;
    for (final r in rows) {
      final s = PushState.values.byName(r.pushState);
      if (s == PushState.queued || s == PushState.inflight) pending++;
      if (s == PushState.rejected) add(AttentionReason.rejection);
      if (s == PushState.acked) {
        final at = _ackedAtMs[r.envelopeId] ?? r.createdAt;
        if (now - at > unobservedInboxMs) {
          add(AttentionReason.unobservedOverdue);
        }
      }
    }
    if (reasons.isNotEmpty) return NeedsAttention(List.unmodifiable(reasons));
    if (waitingFor != null) return WaitingFor(waitingFor);
    if (_offline) return const Offline();
    if (pending > 0) return SavedWillSync(pending);
    return const Synced();
  }

  // ── the round ───────────────────────────────────────────────────────────

  /// One sync round. Safe to call at any cadence (05 §7); idempotent.
  Future<SyncReport> sync() async {
    await _restore();
    var pushed = 0;
    var acked = 0;
    var pulled = 0;
    var verified = 0;
    var quarantined = 0;
    var epochChanged = false;
    _offline = false;
    if (_mode == EngineMode.wiped || _mode == EngineMode.updateRequired) {
      return _report(0, 0, 0, 0, 0, false);
    }
    // 1. Meta / keys first (05 §3 ordering rule) — also the only path out of
    //    `suspended`: a clean, authenticated meta round with no claim standing.
    final metaOk = await _metaRound();
    if (metaOk == _RouteResult.epochChanged) epochChanged = true;
    if (_mode != EngineMode.active) {
      return _report(0, 0, 0, 0, 0, epochChanged);
    }
    if (metaOk == _RouteResult.offline) {
      return _report(0, 0, 0, 0, 0, epochChanged);
    }
    // 2. Per book: push then pull.
    final books = await _books();
    for (var pass = 0; pass < 2; pass++) {
      var repush = false;
      for (final book in books) {
        final p = await _pushBook(book);
        pushed += p.pushed;
        acked += p.acked;
        if (p.result == _RouteResult.epochChanged) {
          epochChanged = true;
          repush = true;
        }
        if (p.result == _RouteResult.offline || _mode != EngineMode.active) {
          return _report(
            pushed,
            acked,
            pulled,
            verified,
            quarantined,
            epochChanged,
          );
        }
        final q = await _pullBook(book);
        pulled += q.pulled;
        verified += q.verified;
        quarantined += q.quarantined;
        if (q.result == _RouteResult.epochChanged) {
          epochChanged = true;
          repush = true;
        }
        if (q.result == _RouteResult.offline || _mode != EngineMode.active) {
          return _report(
            pushed,
            acked,
            pulled,
            verified,
            quarantined,
            epochChanged,
          );
        }
      }
      if (!repush) break;
    }
    await mirror.pruneObserved();
    return _report(pushed, acked, pulled, verified, quarantined, epochChanged);
  }

  SyncReport _report(
    int pushed,
    int acked,
    int pulled,
    int verified,
    int quarantined,
    bool epochChanged,
  ) => SyncReport(
    pushed: pushed,
    acked: acked,
    pulled: pulled,
    verified: verified,
    quarantined: quarantined,
    keyWait: _keyWait.length,
    epochChanged: epochChanged,
    offline: _offline,
  );

  Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    // Verified records survive restarts: re-feed trust from the local table.
    final rows = await (db.select(
      db.signedRecordsLocal,
    )..where((t) => t.verified.equals(1))).get();
    rows.sort((a, b) => (a.seq ?? 0).compareTo(b.seq ?? 0));
    for (final r in rows) {
      _applyVerifiedRecord(
        WireSignedRecord(
          id: r.id,
          suiteVersion: suiteVersion,
          tenantId: r.tenantId,
          kind: r.kind,
          payloadJson: r.payload,
          authorDeviceId: r.authorDevice,
          authorSig: r.sig,
          hlc: r.hlc,
          seq: r.seq ?? 0,
        ),
        fromStore: true,
      );
    }
  }

  Future<Set<String>> _books() async {
    final out = <String>{...subscribedBooks, ...await mirror.bookIds()};
    for (final r in await mirror.outboxRows()) {
      out.add(r.bookId);
    }
    for (final MapEntry(key: (book, user), value: _) in _roles.entries) {
      if (user == userId) out.add(book);
    }
    return out;
  }

  /// `acked` rows and their seqs — snapshotted so a restore can tell a
  /// re-acked duplicate (same `seq`) from a lost write (new `seq`).
  Future<void> _snapshotAcked() async {
    for (final r in await mirror.outboxRows(state: PushState.acked)) {
      if (r.ackedSeq != null) _ackedSeqs[r.envelopeId] = r.ackedSeq!;
    }
  }

  Future<OutboxData?> _outboxRow(String envelopeId) => (db.select(
    db.outbox,
  )..where((t) => t.envelopeId.equals(envelopeId))).getSingleOrNull();

  /// Records the server epoch; returns true when cursors were reset.
  Future<bool> _epoch(String epoch) async {
    await _snapshotAcked();
    final reset = await mirror.observeStoreEpoch(epoch);
    if (reset) {
      // Every acked row is queued again (ADR 05b §6); remember what the
      // server had acked so a re-ack under a new `seq` is recognised as lost.
      _lostCandidates.addAll(_ackedSeqs);
      _ackedAtMs.clear();
    }
    return reset;
  }

  /// Runs [call]; maps transport failures to engine state. Returns null on
  /// failure (the caller stops the route). A route-level refusal (404/403
  /// [RouteRefused], 413 [BatchTooLarge]) is left in [_refusal] for the
  /// caller, which knows what the route was doing.
  Future<T?> _guarded<T>(Future<T> Function() call) async {
    _refusal = null;
    try {
      return await call();
    } on TransportOffline {
      _offline = true;
      return null;
    } on RouteRefused catch (e) {
      _refusal = e;
      return null;
    } on BatchTooLarge catch (e) {
      _refusal = e;
      return null;
    } on UpdateRequired {
      _mode = EngineMode.updateRequired;
      _open.add(AttentionReason.updateRequired);
      _emit(UpdateRequiredEvent(_now));
      return null;
    } on AuthFailed catch (e) {
      if (e.code == AuthFailed.deviceRevoked) {
        _suspend('401 device_revoked');
      } else {
        _offline = true; // a plain 401 is a refresh problem, not a fact
      }
      return null;
    }
  }

  void _suspend(String source) {
    if (_mode == EngineMode.suspended) return;
    _mode = EngineMode.suspended;
    _open.add(AttentionReason.suspended);
    _emit(Suspended(_now, source));
  }

  // ── meta / keys (05 §5) ─────────────────────────────────────────────────

  Future<_RouteResult> _metaRound() async {
    var epochChanged = false;
    while (true) {
      final res = await _guarded(
        () => transport.meta(MetaRequest(after: _metaCursor)),
      );
      if (res == null) {
        return _offline ? _RouteResult.offline : _RouteResult.stopped;
      }
      if (await _epoch(res.storeEpoch)) epochChanged = true;
      await _applyMeta(res);
      _metaCursor = res.next ?? _metaCursor;
      if (!res.hasMore) break;
    }
    if (_unsignedClaim) {
      _suspend('devices row');
    } else if (_mode == EngineMode.suspended) {
      // Authenticated cleanly and no claim stands: ADR 05b §2 — resolves.
      _mode = EngineMode.active;
      _open.remove(AttentionReason.suspended);
      _emit(Resumed(_now));
    }
    if (_mode == EngineMode.active) await _enforceCutoffs();
    return epochChanged ? _RouteResult.epochChanged : _RouteResult.ok;
  }

  /// Applies one meta page. A `devices` row about *this* device sets or
  /// clears the unsigned-revocation claim (ADR 05b §2); the claim persists
  /// across empty pages until a row retracts it or a record settles it.
  Future<void> _applyMeta(MetaResponse m) async {
    // Certificates before records: the chain needs them.
    for (final d in m.devices) {
      trust.deviceOwners[d.id] = d.userId;
    }
    for (final c in m.deviceCerts) {
      final d = m.devices.where((x) => x.id == c.deviceId).firstOrNull;
      if (d == null) continue;
      final cert = guard.buildCert(c, d);
      if (cert != null) trust.certs[c.deviceId] = cert;
    }
    for (final g in m.guardianSets) {
      trust.guardianHistory.removeWhere(
        (v) =>
            v.subjectUserId == g.subjectUserId &&
            v.shareSetVersion == g.shareSetVersion,
      );
      trust.guardianHistory.add(
        GuardianSetVersion(
          subjectUserId: g.subjectUserId,
          shareSetVersion: g.shareSetVersion,
          k: g.k,
          guardianUserIds: g.guardianUserIds.toSet(),
        ),
      );
    }
    // Records, in seq order (a revocation's cut-off gates later records).
    final records = List.of(m.signedRecords)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    for (final r in records) {
      await _applyRecord(r);
      if (_mode == EngineMode.wiped) return;
    }
    // Keys → drain key_wait.
    for (final k in m.wrappedKeys) {
      final ref = guard.acceptWrappedKey(k);
      if (ref != null) await _keyArrived(ref);
    }
    // Rows are the server's projection: check them against the records.
    for (final d in m.devices) {
      final revokedByRecord = trust.revocationSeqOf(d.id) != null;
      if (d.id == deviceId) {
        _unsignedClaim = d.claimsRevoked && !revokedByRecord;
      } else if (d.claimsRevoked && !revokedByRecord) {
        _emit(MetaMismatch(_now, 'devices', d.id, 'revoked without a record'));
      }
    }
    for (final row in m.bookRoles) {
      final fact = _roles[(row.bookId, row.userId)];
      if (fact == null) {
        _emit(MetaMismatch(_now, 'book_roles', row.id, 'no signed record'));
      } else if (fact.role != row.role ||
          !_jsonEquals(fact.limits, row.limits)) {
        _emit(
          MetaMismatch(
            _now,
            'book_roles',
            row.id,
            'row differs from record ${fact.recordId}',
          ),
        );
      }
    }
    for (final row in m.memberships) {
      final fact = _membershipStatus[row.userId];
      if (fact != null && fact.$1 != row.status) {
        _emit(
          MetaMismatch(
            _now,
            'memberships',
            row.id,
            'status differs from record',
          ),
        );
      }
    }
  }

  Future<void> _applyRecord(WireSignedRecord r) async {
    if (_seenRecordIds.contains(r.id)) return;
    final verdict = guard.checkRecord(r);
    final ok = verdict is RecordVerified;
    await db
        .into(db.signedRecordsLocal)
        .insertOnConflictUpdate(
          SignedRecordsLocalCompanion.insert(
            id: r.id,
            tenantId: r.tenantId,
            kind: r.kind,
            payload: r.payloadJson,
            authorDevice: r.authorDeviceId,
            sig: r.authorSig,
            hlc: r.hlc,
            seq: Value(r.seq),
            verified: Value(ok ? 1 : 0),
          ),
        );
    if (!ok) {
      _emit(RecordIgnored(_now, r.id, (verdict as RecordRejected).reason));
      return;
    }
    _seenRecordIds.add(r.id);
    _applyVerifiedRecord(r, fromStore: false);
    if (r.kind == SignedRecordKind.deviceRevocation ||
        r.kind == SignedRecordKind.memberRemoval) {
      await _ownFate(r.id);
    }
  }

  Map<String, Object?>? _payload(WireSignedRecord r) {
    try {
      final d = jsonDecode(utf8.decode(r.payloadJson));
      return d is Map<String, Object?> ? d : null;
    } on FormatException {
      return null;
    }
  }

  /// Feeds a verified record into trust / role facts. Payload keys as the
  /// server projects them (`_shared/records.ts`): `membership_status
  /// {user_id, status}`, `member_removal {user_id}`, `book_role {book_id,
  /// user_id, role?, auto_post_limit_paise?}` (projected onto the row as
  /// `limits:{auto_post_limit_paise}`; a `limits` map in the payload is
  /// accepted as written), `device_revocation {revoked_device_id,
  /// subject_user_id, share_set_version?}` (the ADR's body). `key_rotation
  /// {book_id, key_version}`, `device_added` and `designation` are stored by
  /// the server but not projected; only `key_rotation` is read here.
  void _applyVerifiedRecord(WireSignedRecord r, {required bool fromStore}) {
    if (fromStore) _seenRecordIds.add(r.id);
    final p = _payload(r);
    if (p == null) return;
    switch (r.kind) {
      case SignedRecordKind.deviceRevocation:
        final revoked = p['revoked_device_id'];
        final subject = p['subject_user_id'];
        if (revoked is! String || subject is! String) return;
        final authorUser = trust.userOf(r.authorDeviceId);
        if (authorUser == null) {
          _emit(RecordIgnored(_now, r.id, 'author user unknown'));
          return;
        }
        if (trust.revocations.any((x) => x.recordId == r.id)) return;
        trust.revocations.add(
          RevocationRecord(
            recordId: r.id,
            seq: r.seq,
            authorDeviceId: r.authorDeviceId,
            authorUserId: authorUser,
            revokedDeviceId: revoked,
            subjectUserId: subject,
            shareSetVersion: p['share_set_version'] as int?,
          ),
        );
        for (final ig in trust.countFor(revoked).ignored) {
          if (ig.recordId == r.id) {
            _emit(RecordIgnored(_now, r.id, ig.reason.name));
          }
        }
      case SignedRecordKind.memberRemoval:
        final removed = p['user_id'];
        if (removed is! String) return;
        if (trust.removals.any((x) => x.recordId == r.id)) return;
        trust.removals.add(
          RemovalRecord(recordId: r.id, seq: r.seq, removedUserId: removed),
        );
        // The server projects a removal as membership `removed`.
        final cur = _membershipStatus[removed];
        if (cur == null || r.seq > cur.$2) {
          _membershipStatus[removed] = ('removed', r.seq);
        }
      case SignedRecordKind.keyRotation:
        final book = p['book_id'];
        final v = p['key_version'];
        if (book is String && v is int) {
          final cur = _announcedKeyVersion[book];
          if (cur == null || v > cur) _announcedKeyVersion[book] = v;
        }
      case SignedRecordKind.bookRole:
        final book = p['book_id'];
        final user = p['user_id'];
        final role = p['role'];
        if (book is! String || user is! String) return;
        if (role != null && role is! String) return;
        final cur = _roles[(book, user)];
        if (cur == null || r.seq > cur.seq) {
          _roles[(book, user)] = RoleFact(
            recordId: r.id,
            seq: r.seq,
            role: role as String?,
            limits: _limitsOf(p),
          );
          if (user == userId && role != null) {
            pushBlockedBooks.remove(book);
            pullBlockedBooks.remove(book);
            if (pullBlockedBooks.isEmpty) {
              _open.remove(AttentionReason.bookUnavailable);
            }
          }
        }
      case SignedRecordKind.membershipStatus:
        final user = p['user_id'];
        final status = p['status'];
        if (user is! String || status is! String) return;
        final cur = _membershipStatus[user];
        if (cur == null || r.seq > cur.$2) {
          _membershipStatus[user] = (status, r.seq);
        }
      default:
        break; // unknown kinds are stored, never interpreted (rule 6)
    }
  }

  /// The `limits` a `book_role` record carries, in the row's shape: an
  /// explicit `limits` map as written, else `{auto_post_limit_paise: int}`
  /// from the top-level key the server reads (integer paise; a decimal string
  /// is accepted, a float never — rule 1).
  static Map<String, Object?>? _limitsOf(Map<String, Object?> p) {
    final explicit = p['limits'];
    if (explicit is Map<String, Object?>) return explicit;
    final raw = p[WireBookRole.autoPostLimitPaise];
    final paise = switch (raw) {
      final int n => n,
      final String s => int.tryParse(s),
      _ => null,
    };
    return paise == null ? null : {WireBookRole.autoPostLimitPaise: paise};
  }

  /// A verified revocation/removal may be about us (05 §5).
  Future<void> _ownFate(String recordId) async {
    if (trust.countFor(deviceId).effectiveSeq != null) {
      await _wipe(recordId);
      return;
    }
    for (final rm in trust.removals) {
      if (rm.removedUserId == userId) {
        guard.dropAllKeys();
        _emit(KeysDropped(_now, recordId));
        return;
      }
    }
  }

  Future<void> _wipe(String recordId) async {
    guard.dropAllKeys();
    for (final book in await mirror.bookIds()) {
      await mirror.rebootstrapBook(book);
    }
    _keyWait.clear();
    _gapFirstSeen.clear();
    _mode = EngineMode.wiped;
    _emit(Wiped(_now, recordId));
  }

  Future<void> _keyArrived(BookKeyRef ref) async {
    // Drain key_wait for this (book, version).
    final ids = [
      for (final MapEntry(key: id, value: w) in _keyWait.entries)
        if (w.bookId == ref.bookId && w.keyVersion == ref.keyVersion) id,
    ];
    for (final id in ids) {
      final w = _keyWait[id];
      if (w == null) continue;
      await _admit(w.envelope);
    }
    // A stale-rejected outbox row of this book may now re-seal (05 §3).
    for (final r in await mirror.outboxRows(state: PushState.rejected)) {
      if (r.bookId == ref.bookId &&
          r.rejectReason == PushOutcome.rejectedKeyVersionStale) {
        await mirror.transition(r.envelopeId, PushState.queued);
        _staleRetried.remove(r.envelopeId);
      }
    }
  }

  /// Re-derives every cut-off from the record set (never cached as final)
  /// and quarantines what now sits at or past it (ADR 2026-09-06 §3).
  Future<void> _enforceCutoffs() async {
    final authors = await db
        .customSelect('SELECT DISTINCT author_device FROM envelopes_local')
        .get();
    final devices = {
      for (final a in authors) a.read<String>('author_device'),
      for (final r in trust.revocations) r.revokedDeviceId,
    };
    for (final d in devices) {
      final cut = trust.revocationSeqOf(d);
      final prev = _lastCutoff[d];
      if (_lastCutoff.containsKey(d) ? prev != cut : cut != null) {
        if (cut != null) _emit(CutoffChanged(_now, d, prev, cut));
      }
      _lastCutoff[d] = cut;
      if (cut == null) continue;
      final rows = await db
          .customSelect(
            'SELECT envelope_id FROM envelopes_local WHERE author_device = ? '
            'AND quarantined = 0 AND (seq IS NULL OR seq >= ?)',
            variables: [Variable.withString(d), Variable.withInt(cut)],
          )
          .get();
      for (final r in rows) {
        final id = r.read<String>('envelope_id');
        await mirror.quarantine(id, 'revoked');
        _keyWait.remove(id);
        _emit(Quarantined(_now, id, 'revoked'));
        _open.add(AttentionReason.quarantine);
      }
    }
  }

  // ── push (05 §3) ────────────────────────────────────────────────────────

  Future<_PushResult> _pushBook(String book) async {
    var pushed = 0;
    var acked = 0;
    var epochChanged = false;
    if (_tenantFrozen || quotaStoppedBooks.contains(book)) {
      return _PushResult(_RouteResult.stopped, 0, 0);
    }
    if (pushBlockedBooks.contains(book)) {
      return _PushResult(_RouteResult.stopped, 0, 0);
    }
    if (_now < _retryPushAtMs) return _PushResult(_RouteResult.stopped, 0, 0);
    while (true) {
      final rows = [
        for (final r in await mirror.outboxRows(state: PushState.queued))
          if (r.bookId == book) r,
      ];
      if (rows.isEmpty) break;
      // Build a batch ≤ 100 envelopes / 1 MB (05 §3; the server refuses a
      // larger one whole with 413), re-sealing stale rows first.
      final maxN = _batchCap[book] ?? PushRequest.maxEnvelopes;
      final maxBytes = _batchBytesCap[book] ?? PushRequest.maxBytes;
      final batch = <WireEnvelope>[];
      var bytes = 0;
      for (final r in rows) {
        final w = await _outboxWire(r);
        if (w == null) continue;
        if (batch.isNotEmpty &&
            (batch.length >= maxN || bytes + w.size > maxBytes)) {
          break;
        }
        batch.add(w);
        bytes += w.size;
      }
      if (batch.isEmpty) break;
      for (final w in batch) {
        await mirror.transition(w.envelopeId, PushState.inflight);
      }
      final res = await _guarded(
        () => transport.push(PushRequest(envelopes: batch)),
      );
      pushed += batch.length;
      if (res == null) {
        for (final w in batch) {
          await mirror.transition(w.envelopeId, PushState.queued);
        }
        if (_refusal is BatchTooLarge) {
          // The whole batch was refused, nothing judged: shrink and retry
          // now. A lone envelope the server calls too large is terminal
          // (the per-envelope `too_large` row of 05 §3), so this cannot loop.
          _emit(BatchRefused(_now, book, batch.length, bytes));
          if (batch.length == 1) {
            await _reject(
              batch.single.envelopeId,
              PushResult(
                envelopeId: batch.single.envelopeId,
                result: PushOutcome.rejectedTooLarge,
                check: BatchTooLarge.code,
              ),
            );
            continue;
          }
          _batchCap[book] = (batch.length ~/ 2).clamp(1, maxN - 1);
          if (bytes > 0) {
            _batchBytesCap[book] = (bytes ~/ 2).clamp(1, maxBytes);
          }
          continue;
        }
        if (_refusal is RouteRefused) {
          // 404/403/400 on the push route as a whole — rows stay queued.
          _emit(
            PullRefused(
              _now,
              book,
              (_refusal! as RouteRefused).code ?? '',
              route: 'push',
            ),
          );
          pushBlockedBooks.add(book);
          _open.add(AttentionReason.bookUnavailable);
          return _PushResult(_RouteResult.stopped, pushed, acked);
        }
        if (_offline) {
          _backoff = _backoff.next();
          _retryPushAtMs = _now + _backoff.delayWith(jitter);
          return _PushResult(_RouteResult.offline, pushed, acked);
        }
        return _PushResult(_RouteResult.stopped, pushed, acked);
      }
      _backoff = _backoff.reset();
      _retryPushAtMs = 0;
      if (await _epoch(res.storeEpoch)) epochChanged = true;
      var stop = false;
      var retryNow = false;
      final byId = {for (final w in batch) w.envelopeId: w};
      for (final r in res.results) {
        final w = byId.remove(r.envelopeId);
        if (w == null) continue;
        final outcome = await _handleResult(book, w, r);
        switch (outcome) {
          case _Outcome.acked:
            acked++;
          case _Outcome.retryNow:
            retryNow = true;
          case _Outcome.stopBook:
            stop = true;
          case _Outcome.terminal:
            break;
        }
      }
      // Results the server did not mention go back to queued (no data loss).
      for (final id in byId.keys) {
        await mirror.transition(id, PushState.queued);
      }
      if (stop) break;
      if (!retryNow && byId.isEmpty && rows.length <= batch.length) break;
    }
    return _PushResult(
      epochChanged ? _RouteResult.epochChanged : _RouteResult.ok,
      pushed,
      acked,
    );
  }

  Future<_Outcome> _handleResult(
    String book,
    WireEnvelope w,
    PushResult r,
  ) async {
    final id = w.envelopeId;
    switch (r.result) {
      case PushOutcome.acked:
        final seq = r.seq;
        if (seq == null) {
          await mirror.transition(id, PushState.queued);
          return _Outcome.terminal;
        }
        await mirror.transition(id, PushState.acked, ackedSeq: seq);
        _ackedAtMs[id] = _now;
        final before = _lostCandidates.remove(id);
        if (before != null && before != seq) {
          // Acked before the restore, gone after it: re-pushed just now.
          _emit(WriteLost(_now, id));
          _open.add(AttentionReason.writeLost);
        }
        _ackedSeqs[id] = seq;
        try {
          await mirror.setSeq(id, seq);
        } on StateError {
          // The author's own mirror row is optional for the outbox.
        }
        return _Outcome.acked;
      case PushOutcome.rejectedRateLimited:
        await mirror.transition(id, PushState.queued);
        if (_retryPushAtMs <= _now) {
          _backoff = _backoff.next();
          final wait = r.retryAfterMs ?? _backoff.delayWith(jitter);
          _retryPushAtMs = _now + wait;
          _emit(Throttled(_now, _retryPushAtMs));
        }
        return _Outcome.stopBook;
      case PushOutcome.rejectedQuota:
        await mirror.transition(id, PushState.queued);
        if (quotaStoppedBooks.add(book)) _emit(QuotaStopped(_now, book));
        _open.add(AttentionReason.quota);
        return _Outcome.stopBook;
      case PushOutcome.rejectedTenantFrozen:
        await mirror.transition(id, PushState.queued);
        if (!_tenantFrozen) {
          _tenantFrozen = true;
          _emit(TenantFrozen(_now));
        }
        _open.add(AttentionReason.tenantFrozen);
        return _Outcome.stopBook;
      case PushOutcome.rejectedKeyVersionStale:
        final highest = guard.highestKeyVersion(book);
        if (!_staleRetried.contains(id) &&
            highest != null &&
            highest > w.keyVersion) {
          _staleRetried.add(id);
          await mirror.transition(id, PushState.queued);
          return _Outcome.retryNow;
        }
        await _reject(id, r);
        return _Outcome.terminal;
      case PushOutcome.rejectedHlcFuture:
        // Re-stamping is an authoring act (new envelope_id, same object) the
        // app performs; the engine surfaces the clock problem.
        await _reject(id, r);
        _open.add(AttentionReason.clockWarning);
        return _Outcome.terminal;
      case PushOutcome.rejectedNoRole:
      case PushOutcome.membershipNotActive:
      case PushOutcome.rejectedUnknownBook:
        await _reject(id, r);
        pushBlockedBooks.add(book);
        return _Outcome.stopBook;
      default:
        // too_large, version, shape, anything unknown: terminal per envelope.
        await _reject(id, r);
        return _Outcome.terminal;
    }
  }

  Future<void> _reject(String id, PushResult r) async {
    await mirror.transition(id, PushState.rejected, rejectReason: r.result);
    _open.add(AttentionReason.rejection);
    _emit(PushRejected(_now, id, r.result, check: r.check));
  }

  /// The wire form of an outbox row, re-sealed under the highest key when
  /// its `key_version` is stale (05 §3). The header comes from the author's
  /// own mirror row; the blob from the mirror too, so a re-seal is always
  /// computed from the original (the mirror is append-only and keeps `v`).
  Future<WireEnvelope?> _outboxWire(OutboxData r) async {
    final row = await (db.select(
      db.envelopesLocal,
    )..where((t) => t.envelopeId.equals(r.envelopeId))).getSingleOrNull();
    if (row == null) {
      // ⚠️ SPEC: the outbox holds only the blob (03 §3.1); the header lives
      // in the author's mirror row. After a re-bootstrap the row returns with
      // the pull, so the push waits a round instead of refusing.
      return null;
    }
    var w = _wireOfRow(row, row.envelopeBlob, row.keyVersion);
    final highest = guard.highestKeyVersion(r.bookId);
    if (highest != null && highest > row.keyVersion) {
      final resealed = guard.reseal(w, toVersion: highest);
      if (resealed != null) {
        await (db.update(db.outbox)
              ..where((t) => t.envelopeId.equals(r.envelopeId)))
            .write(OutboxCompanion(envelopeBlob: Value(resealed.blob)));
        _emit(Resealed(_now, r.envelopeId, row.keyVersion, highest));
        w = resealed;
      }
    } else if (!_sameBytes(r.envelopeBlob, row.envelopeBlob)) {
      // Already re-sealed in an earlier round; push that copy.
      w = _wireOfRow(row, r.envelopeBlob, highest ?? row.keyVersion);
    }
    return w;
  }

  WireEnvelope _wireOfRow(EnvelopesLocalData row, Uint8List blob, int kv) =>
      WireEnvelope(
        envelopeId: row.envelopeId,
        seq: row.seq,
        tenantId: tenantId,
        bookId: row.bookId,
        objectId: row.objectId,
        objectType: row.objectType,
        keyVersion: kv,
        suiteVersion: suiteVersion,
        payloadSchema: guard.payloadSchema,
        authorDevice: row.authorDevice,
        hlc: row.hlc,
        blobHash: guard.hash(blob),
        blob: blob,
      );

  // ── pull (05 §4) ────────────────────────────────────────────────────────

  Future<int> _cursor(String book) async {
    final row = await (db.select(
      db.syncCursors,
    )..where((t) => t.bookId.equals(book))).getSingleOrNull();
    return row?.lastSeq ?? 0;
  }

  Future<void> _setCursor(String book, int seq) => db
      .into(db.syncCursors)
      .insertOnConflictUpdate(
        SyncCursorsCompanion.insert(bookId: book, lastSeq: seq),
      );

  Future<_PullResult> _pullBook(String book) async {
    var pulled = 0;
    var verified = 0;
    var quarantined = 0;
    var epochChanged = false;
    var changed = false;
    var restarts = 0;
    var after = await _cursor(book);
    _RouteResult? aborted;
    if (pullBlockedBooks.contains(book)) {
      return const _PullResult(_RouteResult.stopped, 0, 0, 0);
    }
    while (true) {
      final res = await _guarded(
        () => transport.pull(PullRequest(bookId: book, afterSeq: after)),
      );
      if (res == null) {
        // A dropped page ends paging, never the bookkeeping below: rows that
        // already landed must still reach the projector this round.
        if (_refusal case final RouteRefused r) {
          // 404 unknown_book (also a non-member's tenant or an uncertified
          // device) / 403 no_role: the book is not ours *now*. Cursor and
          // mirror stay; pushes would be refused the same way, so they stop
          // too until a record (or the app) says otherwise. Inbox, as 05 §3
          // maps `unknown_book` / `no_role`.
          _emit(PullRefused(_now, book, r.code ?? '${r.status}'));
          pullBlockedBooks.add(book);
          pushBlockedBooks.add(book);
          _open.add(AttentionReason.bookUnavailable);
        }
        aborted = _offline ? _RouteResult.offline : _RouteResult.stopped;
        break;
      }
      if (await _epoch(res.storeEpoch)) {
        epochChanged = true;
        if (restarts++ < 1) {
          after = 0;
          continue;
        }
      }
      var stopAt = res.nextSeq;
      for (final e in res.envelopes) {
        pulled++;
        if (!_sameBytes(guard.hash(e.blob), e.blobHash)) {
          // Corruption in transit: do not store, do not pass the cursor.
          _emit(BlobCorruptOnPull(_now, e.envelopeId));
          stopAt = e.seq! - 1;
          break;
        }
        final seq = e.seq!;
        if (e.authorDevice == deviceId) {
          await _observeOwn(e.envelopeId, seq);
        }
        final existing = await (db.select(
          db.envelopesLocal,
        )..where((t) => t.envelopeId.equals(e.envelopeId))).getSingleOrNull();
        if (existing != null) {
          if (existing.seq == null) await mirror.setSeq(e.envelopeId, seq);
          continue;
        }
        switch (await _admit(e)) {
          case EnvelopeVerified():
            verified++;
            changed = true;
          case EnvelopeQuarantine():
            quarantined++;
            changed = true;
          case EnvelopeKeyWait():
          case EnvelopeCorrupt():
            break;
        }
      }
      if (stopAt > after) after = stopAt;
      // The persisted cursor never passes an envelope still waiting for its
      // key: a restart re-pulls from there (appends are idempotent).
      var floor = after;
      for (final w in _keyWait.values) {
        if (w.bookId == book && w.envelope.seq! - 1 < floor) {
          floor = w.envelope.seq! - 1;
        }
      }
      if (floor > await _cursor(book)) await _setCursor(book, floor);
      if (stopAt < res.nextSeq || !res.hasMore) break;
    }
    await _readYourWrites(book, after);
    // Author gaps (mirror-derived) and projections.
    final gaps = await mirror.recomputeAuthorGaps(book);
    final present = <_GapKey>{};
    for (final g in gaps) {
      final k = _GapKey(g.bookId, g.authorDevice, g.expectedSeq);
      present.add(k);
      _gapFirstSeen.putIfAbsent(k, () => _now);
    }
    _gapFirstSeen.removeWhere(
      (k, _) => k.bookId == book && !present.contains(k),
    );
    if (changed && recompute != null) await recompute!.run(bookId: book);
    return _PullResult(
      aborted ?? (epochChanged ? _RouteResult.epochChanged : _RouteResult.ok),
      pulled,
      verified,
      quarantined,
    );
  }

  /// Verifies a pulled envelope through the guard and stores it: a verified
  /// one as a `verified` mirror row (with the inner `author_seq`), a refused
  /// one as a quarantined row (reason kept, never summed), a key-less one in
  /// the `key_wait` queue.
  Future<EnvelopeVerdict> _admit(WireEnvelope e) async {
    final v = guard.checkEnvelope(e);
    EnvelopeRecord rec(int authorSeq, bool verified) => EnvelopeRecord(
      envelopeId: e.envelopeId,
      bookId: e.bookId,
      objectId: e.objectId,
      objectType: e.objectType,
      keyVersion: e.keyVersion,
      hlc: e.hlc,
      authorDevice: e.authorDevice,
      authorSeq: authorSeq,
      blob: e.blob,
      blobHash: e.blobHash,
      seq: e.seq,
      verified: verified,
    );
    switch (v) {
      case EnvelopeVerified(:final authorSeq):
        await mirror.append(rec(authorSeq, true));
        _keyWait.remove(e.envelopeId);
      case EnvelopeQuarantine(:final reason):
        // ⚠️ SPEC: a quarantined envelope may be undecryptable, so its
        // `author_seq` is unknown; 0 marks "not counted" (03 §3.1 owner).
        if (await mirror.append(rec(0, false))) {
          await mirror.quarantine(e.envelopeId, reason);
        }
        _keyWait.remove(e.envelopeId);
        _emit(Quarantined(_now, e.envelopeId, reason));
        _open.add(AttentionReason.quarantine);
      case EnvelopeKeyWait(:final keyVersion):
        if (!_keyWait.containsKey(e.envelopeId)) {
          _keyWait[e.envelopeId] = _Waiting(e, _now);
          _emit(KeyWait(_now, e.envelopeId, e.bookId, keyVersion));
        }
      case EnvelopeCorrupt():
        _emit(BlobCorruptOnPull(_now, e.envelopeId));
    }
    return v;
  }

  /// Own envelope back in own pull → `observed` (ADR 05b §6).
  Future<void> _observeOwn(String id, int seq) async {
    final row = await _outboxRow(id);
    if (row == null) return;
    var s = PushState.values.byName(row.pushState);
    if (s == PushState.observed) return;
    if (s == PushState.rejected) return;
    if (s == PushState.queued) {
      await mirror.transition(id, PushState.inflight);
      s = PushState.inflight;
    }
    if (s == PushState.inflight) {
      await mirror.transition(id, PushState.acked, ackedSeq: seq);
    }
    await mirror.transition(id, PushState.observed);
    _ackedAtMs.remove(id);
    _ackedSeqs.remove(id);
    _lostCandidates.remove(id);
  }

  /// Cursor past an acked `seq` without seeing it → re-push + `write_lost`.
  Future<void> _readYourWrites(String book, int cursor) async {
    for (final r in await mirror.outboxRows(state: PushState.acked)) {
      if (r.bookId != book) continue;
      final s = r.ackedSeq;
      if (s != null && s <= cursor) {
        await mirror.transition(r.envelopeId, PushState.queued);
        _emit(WriteLost(_now, r.envelopeId));
        _open.add(AttentionReason.writeLost);
      }
    }
  }
}

enum _RouteResult { ok, epochChanged, offline, stopped }

enum _Outcome { acked, retryNow, stopBook, terminal }

final class _PushResult {
  const _PushResult(this.result, this.pushed, this.acked);
  final _RouteResult result;
  final int pushed;
  final int acked;
}

final class _PullResult {
  const _PullResult(this.result, this.pulled, this.verified, this.quarantined);
  final _RouteResult result;
  final int pulled;
  final int verified;
  final int quarantined;
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_jsonEquals(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
