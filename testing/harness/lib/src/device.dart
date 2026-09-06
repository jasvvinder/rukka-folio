import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';

import 'network.dart';
import 'scheduler.dart';

/// A deterministic 32-bit FNV-1a over the blob. The mirror only needs *a*
/// hash to detect corruption in the rig; `core_crypto` supplies BLAKE2b at M3.
Uint8List fnvHash(Uint8List bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return Uint8List.fromList([
    h >> 24 & 0xff,
    h >> 16 & 0xff,
    h >> 8 & 0xff,
    h & 0xff,
  ]);
}

/// One phone in the rig: the real `packages/data` stack (in-memory SQLite,
/// mirror, Recompute) plus its own `author_seq` allocation. Devices share
/// nothing but the envelopes the [Relay] delivers; there is no server yet
/// (M4) — the relay simply forwards every authored envelope to every other
/// device under the seeded network's delays, reorders and drops.
final class SimulatedDevice {
  SimulatedDevice._(this.id, this.db)
    : mirror = Mirror(db, hasher: fnvHash),
      _clock = Hlc.compose(physicalMs: 0, counter: 0) {
    recompute = Recompute(
      db,
      mirror: mirror,
      opener: const JsonPayloadOpener(),
    );
  }

  /// Opens a device with a fresh, migrated, quick-checked in-memory database.
  static Future<SimulatedDevice> open(String id) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final r = await openLedgerDatabase(NativeDatabase.memory());
    if (r is! Opened) throw StateError('device $id could not open: $r');
    return SimulatedDevice._(id, r.db);
  }

  /// Device id — the `author_device` on everything it authors.
  final String id;

  /// The device's database.
  final LedgerDatabase db;

  /// Envelope mirror + outbox.
  final Mirror mirror;

  /// Projection rebuilder.
  late final Recompute recompute;

  Hlc _clock;

  /// Every envelope this device has authored, in order (what a relay forwards).
  final List<EnvelopeRecord> authored = [];

  /// Next HLC: ticks against the injected physical reading [physicalMs]
  /// (the scheduler's virtual clock in the rig) — never the wall clock.
  Hlc nextHlc(int physicalMs) => _clock = _clock.tick(physicalMs: physicalMs);

  /// Authors the book's config and chart — the all-time envelopes every book
  /// starts with. Returns the records to broadcast.
  Future<List<EnvelopeRecord>> authorSetup(
    BookConfig config,
    Iterable<Account> accounts, {
    required int physicalMs,
  }) async {
    final out = <EnvelopeRecord>[
      await _author(
        config.id,
        config.id,
        'book_config',
        config.toJson(),
        nextHlc(physicalMs),
      ),
    ];
    for (final a in accounts) {
      out.add(
        await _author(
          config.id,
          a.id,
          'account',
          AccountPayload(a).toJson(),
          nextHlc(physicalMs),
        ),
      );
    }
    return out;
  }

  /// Authors a ledger event: allocates this device's next `author_seq`,
  /// stores the envelope in its own mirror, and returns the record to relay.
  /// The event must already carry this device's id and an HLC from [nextHlc].
  Future<EnvelopeRecord> author(LedgerEvent event) async {
    if (event.authorDevice != null && event.authorDevice != id) {
      throw ArgumentError('event authored by ${event.authorDevice}, not $id');
    }
    final payload = Map<String, Object?>.of(encodeEvent(event));
    return _author(
      event.bookId,
      event.id,
      objectTypeOf(event),
      payload,
      event.hlc,
    );
  }

  Future<EnvelopeRecord> _author(
    String bookId,
    String objectId,
    String objectType,
    Map<String, Object?> payload,
    Hlc hlc,
  ) async {
    final seq = await mirror.nextAuthorSeq(bookId, id);
    // ADR 05b §3: the seq travels inside the ciphertext; the mirror row's
    // column is its plaintext mirror (03 §3.1). Both carry it.
    payload['author_seq'] = seq;
    final blob = encodeJsonPayload(payload);
    final rec = EnvelopeRecord(
      envelopeId: 'env-$objectId',
      bookId: bookId,
      objectId: objectId,
      objectType: objectType,
      keyVersion: 1,
      hlc: hlc.raw,
      authorDevice: id,
      authorSeq: seq,
      blob: blob,
      blobHash: fnvHash(blob),
      verified: true,
    );
    await mirror.append(rec);
    await recompute.run(bookId: bookId);
    authored.add(rec);
    return rec;
  }

  /// Receives an envelope from the network: appends it (idempotent) and
  /// rebuilds the book's projections.
  Future<BookRecompute> receive(EnvelopeRecord rec) async {
    await mirror.append(rec);
    final reports = await recompute.run(bookId: rec.bookId);
    return reports.single;
  }

  /// Deterministic dump of every projection table.
  Future<String> dump() => db.dumpProjections();

  /// `books_p.integrity_ok` for [bookId] (null when the book is unknown).
  Future<bool?> integrityOk(String bookId) async {
    final r = await (db.select(
      db.booksP,
    )..where((t) => t.id.equals(bookId))).getSingleOrNull();
    return r == null ? null : r.integrityOk == 1;
  }

  /// Stored balance in paise, or null when the account has no row.
  Future<int?> balance(String accountId) async {
    final r = await (db.select(
      db.balances,
    )..where((t) => t.accountId.equals(accountId))).getSingleOrNull();
    return r?.balancePaise;
  }

  /// The mirror row for an envelope, or null.
  Future<EnvelopesLocalData?> envelopeRow(String envelopeId) => (db.select(
    db.envelopesLocal,
  )..where((t) => t.envelopeId.equals(envelopeId))).getSingleOrNull();

  /// The `entries_p` row for an entry, or null.
  Future<EntriesPData?> entryRow(String entryId) => (db.select(
    db.entriesP,
  )..where((t) => t.id.equals(entryId))).getSingleOrNull();

  /// Author gaps as the mirror derives them (03 §3.1 `author_gaps`).
  Future<List<SeqGap>> gaps(String bookId) =>
      mirror.recomputeAuthorGaps(bookId);

  /// The book's `LedgerState` and chart as this device's Recompute composed
  /// them — the same state its projection rows were written from, so a test
  /// can apply `monthLockPreconditions` / `yearClosePreconditions` to exactly
  /// what this device knows (mirror-level author gaps included).
  Future<(LedgerState, Chart)> state(String bookId) =>
      recompute.stateOf(bookId);

  /// Closes the database.
  Future<void> close() => db.close();
}

/// One delivered envelope, in the order the scheduler ran it.
final class Arrival {
  /// Creates an arrival.
  const Arrival(this.at, this.to, this.record, this.delivery);

  /// Virtual arrival time.
  final int at;

  /// Receiving device id.
  final String to;

  /// The envelope.
  final EnvelopeRecord record;

  /// The network's decision for it.
  final Delivery delivery;
}

/// The content-blind relay standing in for the server until M4: every
/// authored envelope is sent to every other device through the [Network];
/// arrivals are collected in scheduler order and applied to devices by
/// [deliverPending] (the scheduler is synchronous, the data layer is not).
final class Relay {
  /// Creates a relay over [scheduler] and [network] for [devices].
  Relay(this.scheduler, this.network, this.devices);

  /// The virtual clock.
  final Scheduler scheduler;

  /// Seeded generator or its replay.
  final Network network;

  /// Devices by id.
  final Map<String, SimulatedDevice> devices;

  final List<Arrival> _arrivals = [];
  int _delivered = 0;

  /// Every arrival the scheduler has executed so far.
  List<Arrival> get arrivals => List.unmodifiable(_arrivals);

  /// Decisions the network took, in send order (the replay log).
  List<Delivery> get decisions => List.unmodifiable(_decisions);
  final List<Delivery> _decisions = [];

  /// Schedules [record] from [from] to every other device at the current
  /// virtual time; the network decides delay/drop and records it.
  void broadcast(String from, EnvelopeRecord record) {
    for (final to in devices.keys) {
      if (to == from) continue;
      _decisions.add(
        network.send(
          scheduler,
          from: from,
          to: to,
          label: record.envelopeId,
          onArrive: (s, d) => _arrivals.add(Arrival(s.now, to, record, d)),
        ),
      );
    }
  }

  /// Applies every arrival not yet applied, in arrival order. Call after
  /// `scheduler.run(...)`. Returns the reports, one per applied arrival.
  Future<List<BookRecompute>> deliverPending() async {
    final out = <BookRecompute>[];
    while (_delivered < _arrivals.length) {
      final a = _arrivals[_delivered++];
      out.add(await devices[a.to]!.receive(a.record));
    }
    return out;
  }
}
