// Suite E (client half) — the envelope mirror and outbox (03 §3.1; ADR
// 2026-09-05b §3, §4, §6; ADR 2026-09-05c §2).
@Tags(['E'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late LedgerDatabase db;
  late Mirror m;
  late Fixture f;

  setUp(() async {
    db = await openMemory();
    m = Mirror(db, hasher: toyHash);
    f = Fixture();
  });
  tearDown(() => db.close());

  group('envelope mirror', () {
    test(
      'E-03-4 the mirror is append-only: the envelope itself can never be '
      'updated or deleted, only its flag columns; a repeat append is a no-op',
      () async {
        final e = f.envelope('o1', 'entry', {'id': 'o1'}, hlc: 10);
        expect(await m.append(e), isTrue);
        expect(await m.append(e), isFalse, reason: 'idempotent on retry');
        expect(
          () => db.customStatement(
            "UPDATE envelopes_local SET blob = x'00' WHERE envelope_id = 'env-o1'",
          ),
          throwsA(anything),
        );
        expect(
          () => db.customStatement(
            "UPDATE envelopes_local SET hlc = 99 WHERE envelope_id = 'env-o1'",
          ),
          throwsA(anything),
        );
        expect(
          () => db.customStatement(
            "DELETE FROM envelopes_local WHERE envelope_id = 'env-o1'",
          ),
          throwsA(anything),
        );
        // Flags may change.
        await m.markVerified('env-o1');
        await m.quarantine('env-o1', 'test');
        await m.hold('env-o1', targetId: 'ghost');
        await m.release('env-o1');
        await m.setSeq('env-o1', 42);
        final row = (await m.envelopesOf(f.bookId)).single;
        expect(
          (row.verified, row.quarantined, row.held, row.heldFor, row.seq),
          (1, 1, 0, null, 42),
        );
        expect(() => m.markVerified('env-none'), throwsStateError);
      },
    );

    test('E-05c-1 a blob is re-hashed on read: a stored hash that does not '
        'match is corruption (BlobCorrupt), never a quarantine', () async {
      final good = f.envelope('o1', 'entry', {'id': 'o1'}, hlc: 10);
      final bad = f.envelope(
        'o2',
        'entry',
        {'id': 'o2'},
        hlc: 11,
        blobHash: Uint8List.fromList([1, 2, 3, 4]),
      );
      await storeAll(m, [good, bad]);
      expect(await m.readBlob('env-o1'), isA<BlobOk>());
      expect(
        await m.readBlob('env-o2'),
        isA<BlobCorrupt>().having((c) => c.envelopeId, 'id', 'env-o2'),
      );
      final rows = await m.envelopesOf(f.bookId);
      expect(rows.every((r) => r.quarantined == 0), isTrue);
    });

    test('E-03-8 unknown payload fields round-trip through storage byte for '
        'byte (03 §3.3 rule 4)', () async {
      final e = f.entry(
        'e9',
        Verbs.moneyOut(
          from: f.cash,
          forWhat: f.kirana,
          amount: const Paise.rupees(10),
        ),
        date: LocalDate(2026, 4, 9),
        extra: {
          'future_field': {
            'x': 1,
            'y': ['a', 'b'],
          },
          'channel': 'upi',
        },
      );
      final payload = encodeEvent(e);
      final env = f.envelope(e.id, 'entry', payload, hlc: e.hlc.raw);
      await m.append(env);
      final read = await m.readBlob(env.envelopeId) as BlobOk;
      expect(read.bytes, env.blob, reason: 'stored bytes untouched');
      final decoded =
          jsonDecode(utf8.decode(read.bytes)) as Map<String, Object?>;
      expect(decoded['future_field'], {
        'x': 1,
        'y': ['a', 'b'],
      });
      // And the engine keeps them when it re-serialises.
      expect(Entry.fromJson(decoded).toJson()['future_field'], {
        'x': 1,
        'y': ['a', 'b'],
      });
    });

    test(
      'E-03-7 author_gaps is derived from the mirror: every missing '
      'author_seq below the highest seen, with the HLC since when it is known',
      () async {
        await storeAll(m, [
          f.envelope(
            'a1',
            'entry',
            {},
            hlc: 10,
            authorDevice: 'phone-a',
            authorSeq: 1,
          ),
          f.envelope(
            'a3',
            'entry',
            {},
            hlc: 30,
            authorDevice: 'phone-a',
            authorSeq: 3,
          ),
          f.envelope(
            'a5',
            'entry',
            {},
            hlc: 25,
            authorDevice: 'phone-a',
            authorSeq: 5,
          ),
          f.envelope(
            'b1',
            'entry',
            {},
            hlc: 12,
            authorDevice: 'phone-b',
            authorSeq: 1,
          ),
          f.envelope(
            'b2',
            'entry',
            {},
            hlc: 13,
            authorDevice: 'phone-b',
            authorSeq: 2,
          ),
        ]);
        final gaps = await m.recomputeAuthorGaps(f.bookId);
        expect(
          gaps.map((g) => (g.authorDevice, g.expectedSeq, g.sinceHlc)).toList(),
          [('phone-a', 2, 25), ('phone-a', 4, 25)],
        );
        final rows = await db.select(db.authorGaps).get();
        expect(rows.length, 2);
        // Gap closes when the envelope arrives.
        await m.append(
          f.envelope(
            'a2',
            'entry',
            {},
            hlc: 20,
            authorDevice: 'phone-a',
            authorSeq: 2,
          ),
        );
        await m.append(
          f.envelope(
            'a4',
            'entry',
            {},
            hlc: 28,
            authorDevice: 'phone-a',
            authorSeq: 4,
          ),
        );
        expect(await m.recomputeAuthorGaps(f.bookId), isEmpty);
        expect(await db.select(db.authorGaps).get(), isEmpty);
      },
    );

    test('E-03-6 author_seq_local hands out 1, 2, 3 … per (book, device), '
        'atomically under concurrent requests', () async {
      final seqs = await Future.wait(
        List.generate(20, (_) => m.nextAuthorSeq('b1', 'dev-a')),
      );
      seqs.sort();
      expect(seqs, List.generate(20, (i) => i + 1));
      expect(await m.nextAuthorSeq('b1', 'dev-b'), 1, reason: 'per device');
      expect(await m.nextAuthorSeq('b2', 'dev-a'), 1, reason: 'per book');
      expect(await m.nextAuthorSeq('b1', 'dev-a'), 21);
    });
  });

  group('outbox (03 §3.1, ADR 05b §6)', () {
    test(
      'E-03-5 queued → inflight → acked → observed; illegal moves throw; '
      'only observed rows are pruned; rejected keeps its reason for Inbox',
      () async {
        final blob = Uint8List.fromList([1, 2]);
        await m.enqueue(
          envelopeId: 'x1',
          bookId: 'b1',
          blob: blob,
          createdAt: 1,
        );
        await m.enqueue(
          envelopeId: 'x2',
          bookId: 'b1',
          blob: blob,
          createdAt: 2,
        );
        await m.enqueue(
          envelopeId: 'x3',
          bookId: 'b1',
          blob: blob,
          createdAt: 3,
        );

        expect(
          () => m.transition('x1', PushState.acked, ackedSeq: 5),
          throwsStateError,
          reason: 'queued → acked skips inflight',
        );
        await m.transition('x1', PushState.inflight);
        expect(
          () => m.transition('x1', PushState.acked),
          throwsArgumentError,
          reason: 'acked needs seq',
        );
        await m.transition('x1', PushState.acked, ackedSeq: 5);
        expect((await m.outboxRows()).first.ackedSeq, 5);
        expect(
          await m.pruneObserved(),
          0,
          reason: 'acked is not observed — never pruned (read-your-writes)',
        );
        await m.transition('x1', PushState.observed);
        expect(
          () => m.transition('x1', PushState.queued),
          throwsStateError,
          reason: 'observed is terminal',
        );

        await m.transition('x2', PushState.inflight);
        expect(
          () => m.transition('x2', PushState.rejected),
          throwsArgumentError,
        );
        await m.transition(
          'x2',
          PushState.rejected,
          rejectReason: 'rejected:shape',
        );
        expect(
          (await m.outboxRows(state: PushState.rejected)).single.rejectReason,
          'rejected:shape',
        );

        expect(await m.pruneObserved(), 1);
        final left = await m.outboxRows();
        expect(left.map((r) => r.envelopeId).toList(), ['x2', 'x3']);
        expect(
          () => m.transition('nope', PushState.inflight),
          throwsStateError,
        );
      },
    );

    test(
      'E-05b-1 a changed store epoch resets every pull cursor and returns '
      'acked outbox rows to queued; the same epoch changes nothing',
      () async {
        final blob = Uint8List.fromList([1]);
        await m.enqueue(
          envelopeId: 'x1',
          bookId: 'b1',
          blob: blob,
          createdAt: 1,
        );
        await m.transition('x1', PushState.inflight);
        await m.transition('x1', PushState.acked, ackedSeq: 9);
        await m.enqueue(
          envelopeId: 'x2',
          bookId: 'b1',
          blob: blob,
          createdAt: 2,
        );
        await db
            .into(db.syncCursors)
            .insert(SyncCursorsCompanion.insert(bookId: 'b1', lastSeq: 120));
        await db
            .into(db.syncCursors)
            .insert(SyncCursorsCompanion.insert(bookId: 'b2', lastSeq: 8));

        expect(await m.storeEpoch(), isNull);
        expect(
          await m.observeStoreEpoch('epoch-1'),
          isFalse,
          reason: 'first sight is not a restore',
        );
        expect(await m.observeStoreEpoch('epoch-1'), isFalse);
        expect((await db.select(db.syncCursors).get()).length, 2);

        expect(
          await m.observeStoreEpoch('epoch-2'),
          isTrue,
          reason: 'server was restored',
        );
        expect(await m.storeEpoch(), 'epoch-2');
        expect(
          await db.select(db.syncCursors).get(),
          isEmpty,
          reason: 'all cursors reset',
        );
        final rows = await m.outboxRows();
        expect(
          rows.map((r) => (r.envelopeId, r.pushState, r.ackedSeq)).toList(),
          [('x1', 'queued', null), ('x2', 'queued', null)],
        );
      },
    );
  });
}
