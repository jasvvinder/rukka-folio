// Suite E (client half) — the core_crypto boundary: BLAKE2b blob hashes and
// sealed envelopes through Mirror + Recompute (04 §4; ADR 05b §3; ADR 05c §2).
@Tags(['E'])
library;

import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:sodium/sodium.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// Synthetic ids (canonical uuids — core_crypto binds them into the AAD).
const tenant = '11111111-1111-4111-8111-111111111111';
const book = '22222222-2222-4222-8222-222222222222';
const device = '33333333-3333-4333-8333-333333333331';
const cashObj = '55555555-5555-4555-8555-555555555501';
const salaryObj = '55555555-5555-4555-8555-555555555502';
const configObj = '55555555-5555-4555-8555-555555555500';
const entryObj = '55555555-5555-4555-8555-555555555510';

Sodium? _sodium;
Future<CryptoSuite> suite() async {
  final s = _sodium ??= await SodiumInit.init();
  var counter = 0;
  // Deterministic RNG for the test: BLAKE2b(counter).
  return CryptoSuite(
    s,
    random: (n) {
      final out = Uint8List(n);
      var o = 0;
      while (o < n) {
        final block = s.crypto.genericHash(
          message: Uint8List(8)..buffer.asByteData().setInt64(0, counter++),
          outLen: 32,
        );
        final take = n - o < 32 ? n - o : 32;
        out.setRange(o, o + take, block);
        o += take;
      }
      return out;
    },
  );
}

/// A book sealed with core_crypto: config, two accounts, one ₹1,200 money-out.
final class SealedBook {
  SealedBook(this.s, this.key, this.author, this.records);

  final CryptoSuite s;
  final BookKey key;
  final DeviceKeyPair author;
  final List<EnvelopeRecord> records;

  KeySource get keys =>
      InMemoryKeySource(keys: {key.ref: key}, tenants: {book: tenant});
}

Future<SealedBook> sealedBook() async {
  final s = await suite();
  final key = BookKey.generate(s, bookId: book, keyVersion: 1);
  final author = DeviceKeyPair.generate(s, deviceId: device);
  addTearDown(key.dispose);
  addTearDown(author.dispose);
  final f = Fixture(bookId: book);
  final config = BookConfig(
    id: book,
    tenantId: tenant,
    type: BookType.family,
    name: 'Sharma family',
  );
  final entry = f.entry(
    'e1',
    [
      Line(accountId: f.kirana.id, amount: const Paise.rupees(1200)),
      Line(accountId: f.cash.id, amount: const Paise.rupees(-1200)),
    ],
    date: LocalDate(2026, 5, 3),
    device: device,
  );
  var seq = 0;
  var hlc = 1;
  EnvelopeRecord seal(
    String objectId,
    String objectType,
    Map<String, Object?> obj,
  ) {
    final n = ++seq;
    final env = EnvelopeBuilder.seal(
      s,
      tenantId: tenant,
      bookId: book,
      objectId: objectId,
      objectType: objectType,
      envelopeId: '66666666-6666-4666-8666-${n.toString().padLeft(12, '0')}',
      hlc: hlc++,
      authorSeq: n,
      object: obj,
      bookKey: key,
      author: author,
    );
    return EnvelopeRecord(
      envelopeId: env.envelopeId,
      bookId: book,
      objectId: objectId,
      objectType: objectType,
      keyVersion: 1,
      hlc: env.hlc,
      authorDevice: device,
      authorSeq: n,
      blob: env.blob,
      blobHash: env.blobHash(s),
      verified: true,
    );
  }

  return SealedBook(s, key, author, [
    seal(configObj, 'book_config', config.toJson()),
    seal(cashObj, 'account', AccountPayload(f.cash).toJson()),
    seal(salaryObj, 'account', AccountPayload(f.kirana).toJson()),
    seal(entryObj, 'entry', encodeEvent(entry)),
  ]);
}

void main() {
  test('E-04-1 blake2bHasher is BLAKE2b-256 of the blob (ADR 05c §2): the mirror accepts an intact sealed blob and reports a flipped byte as BlobCorrupt', () async {
    final b = await sealedBook();
    final db = await openMemory();
    final m = Mirror(db, hasher: blake2bHasher(b.s));
    final r = b.records.last;
    expect(blake2bHasher(b.s)(r.blob), b.s.blake2b256(r.blob));
    expect(r.blobHash.length, 32);
    await m.append(r);
    final rows = await m.envelopesOf(book);
    expect(m.readBlobOfRow(rows.single), isA<BlobOk>());

    // Same row, one blob byte flipped on disk → corruption, never quarantine.
    final flipped = Uint8List.fromList(r.blob)..[120] ^= 0x01;
    final db2 = await openMemory();
    final m2 = Mirror(db2, hasher: blake2bHasher(b.s));
    await m2.append(
      EnvelopeRecord(
        envelopeId: r.envelopeId,
        bookId: r.bookId,
        objectId: r.objectId,
        objectType: r.objectType,
        keyVersion: r.keyVersion,
        hlc: r.hlc,
        authorDevice: r.authorDevice,
        authorSeq: r.authorSeq,
        blob: flipped,
        blobHash: r.blobHash,
        verified: true,
      ),
    );
    expect(
      m2.readBlobOfRow((await m2.envelopesOf(book)).single),
      isA<BlobCorrupt>(),
    );
  });

  test('E-04-2 a book sealed by core_crypto replays through Mirror + Recompute with CryptoPayloadOpener: author_seq comes from inside the ciphertext, balances are right, integrity 1', () async {
    final b = await sealedBook();
    final db = await openMemory();
    final m = Mirror(db, hasher: blake2bHasher(b.s));
    final rc = Recompute(
      db,
      mirror: m,
      opener: CryptoPayloadOpener(b.s, b.keys),
    );
    await storeAll(m, b.records);
    final report = (await rc.run()).single;
    expect(report.quarantined, isEmpty);
    expect(report.corrupt, isEmpty);
    expect(report.authorGaps, 0);
    expect(report.integrityOk, isTrue);
    expect(report.eventsApplied, 1);
    final f = Fixture(bookId: book);
    expect(await storedBalance(db, f.cash.id), -1200 * 100);
    expect(await storedBalance(db, f.kirana.id), 1200 * 100);
    // The opener surfaces the wrapper's author_seq at the top level.
    final row = (await m.envelopesOf(book))
        .firstWhere((r) => r.objectType == 'entry');
    final json = CryptoPayloadOpener(b.s, b.keys).open(
      row.envelopeBlob,
      BlobHeader(
        envelopeId: row.envelopeId,
        bookId: row.bookId,
        objectId: row.objectId,
        objectType: row.objectType,
        keyVersion: row.keyVersion,
        authorDevice: row.authorDevice,
        hlc: row.hlc,
      ),
    );
    expect(json['author_seq'], 4);
    expect(json['id'], 'e1');
  });

  test('E-04-3 a routing column changed after sealing (book_id → another book) fails the AAD and Recompute quarantines the row (04 §4, §10); a missing key is KeyUnavailable, not a decrypt failure', () async {
    final b = await sealedBook();
    final db = await openMemory();
    final m = Mirror(db, hasher: blake2bHasher(b.s));
    // The other book happens to hold the same key bytes, so the refusal is the
    // AAD (Poly1305), not a key-version bookkeeping check.
    const otherBook = '22222222-2222-4222-8222-222222222223';
    const otherRef = BookKeyRef(bookId: otherBook, keyVersion: 1);
    final keys = InMemoryKeySource(
      keys: {b.key.ref: b.key, otherRef: BookKey(otherRef, b.key.key)},
      tenants: {book: tenant, otherBook: tenant},
    );
    final rc = Recompute(db, mirror: m, opener: CryptoPayloadOpener(b.s, keys));
    final entry = b.records.last;
    await storeAll(m, [
      ...b.records.take(3),
      // The server "moves" the entry to another book: same blob, other book_id.
      EnvelopeRecord(
        envelopeId: entry.envelopeId,
        bookId: otherBook,
        objectId: entry.objectId,
        objectType: entry.objectType,
        keyVersion: entry.keyVersion,
        hlc: entry.hlc,
        authorDevice: entry.authorDevice,
        authorSeq: entry.authorSeq,
        blob: entry.blob,
        blobHash: entry.blobHash,
        verified: true,
      ),
    ]);
    final reports = await rc.run();
    final moved = reports.firstWhere((r) => r.bookId == otherBook);
    expect(moved.quarantined, [entry.envelopeId]);
    expect(moved.integrityOk, isFalse);
    final row = (await m.envelopesOf(otherBook)).single;
    expect(row.quarantined, 1);
    expect(
      row.quarantineReason,
      startsWith('payload: EnvelopeOpenFailed(aeadFailed'),
    );

    // Key not yet delivered → typed KeyUnavailable (05 §4 key_wait), no AEAD attempt.
    expect(
      () => CryptoPayloadOpener(b.s, InMemoryKeySource(tenants: {book: tenant}))
          .open(
            entry.blob,
            BlobHeader(
              envelopeId: entry.envelopeId,
              bookId: book,
              objectId: entry.objectId,
              objectType: entry.objectType,
              keyVersion: 1,
              authorDevice: device,
              hlc: entry.hlc,
            ),
          ),
      throwsA(isA<KeyUnavailable>()),
    );
  });
}
