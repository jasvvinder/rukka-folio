// Suite E, client half — the signed-record mirror (03 §3.1
// `signed_records_local`; ADR 2026-09-05b §1; ADR 2026-09-05d §7).
//
// The table already existed; what is tested here is the store over it, because
// this is where a `verification_event` rests between the ceremony that made it
// and the seal that depends on it (04 §8.2 🔒). Two properties carry the
// weight: the signed bytes are never rewritten (rule 6 / 03 §3.3.4), and a
// second `append` under an id already stored changes nothing — a relayed
// record cannot displace a locally authored one.
//
// Synthetic data only (CLAUDE.md rule 4): no payload here is financial.
import 'dart:convert';
import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _sig(int fill) => Uint8List(64)..fillRange(0, 64, fill);

SignedRecordRow _row(
  String id, {
  String kind = 'verification_event',
  String tenantId = 't1',
  String payload = '{"subject_user_id":"u2"}',
  String authorDevice = 'dev-a',
  int sigFill = 7,
  int hlc = 1000,
  int? seq,
  bool verified = false,
}) => SignedRecordRow(
  id: id,
  tenantId: tenantId,
  kind: kind,
  payload: _bytes(payload),
  authorDevice: authorDevice,
  sig: _sig(sigFill),
  hlc: hlc,
  seq: seq,
  verified: verified,
);

void main() {
  late LedgerDatabase db;
  late SignedRecordMirror records;

  setUp(() async {
    db = await openMemory();
    records = SignedRecordMirror(db);
  });

  tearDown(() => db.close());

  test('E-03-57 a signed record round-trips byte-for-byte: the payload bytes '
      'that were signed come back unchanged, unknown fields and all '
      '(03 §3.3.4 🔒)', () async {
    // A payload from a build that knows a field this one does not.
    const json =
        '{"subject_user_id":"u2","umk_ed":"AAA","from_the_future":{"k":1}}';
    await records.append(_row('r1', payload: json, verified: true));

    final back = await records.byId('r1');
    expect(back, isNotNull);
    expect(utf8.decode(back!.payload), json);
    expect(back.sig, _sig(7));
    expect(back.tenantId, 't1');
    expect(back.kind, 'verification_event');
    expect(back.authorDevice, 'dev-a');
    expect(back.hlc, 1000);
    expect(back.seq, isNull);
    expect(back.verified, isTrue);
  });

  test(
    'E-03-58 believedOnly returns the verified rows and nothing else — an '
    'unverified record is stored but not believed (C-05d-7, one layer down)',
    () async {
      await records.append(_row('r1', hlc: 1, verified: true));
      await records.append(_row('r2', hlc: 2));

      expect(
        (await records.ofKind(
          'verification_event',
          believedOnly: true,
        )).map((r) => r.id),
        ['r1'],
      );
      expect((await records.ofKind('verification_event')).map((r) => r.id), [
        'r1',
        'r2',
      ]);
    },
  );

  test(
    'E-03-59 records come back in (hlc, id) order however they were stored — '
    'the fold that picks the current key is deterministic',
    () async {
      await records.append(_row('r9', hlc: 5));
      await records.append(_row('r1', hlc: 9));
      await records.append(_row('r3', hlc: 5));
      await records.append(_row('r2', hlc: 1));

      expect((await records.ofKind('verification_event')).map((r) => r.id), [
        'r2',
        'r3',
        'r9',
        'r1',
      ]);
    },
  );

  test('E-03-60 a second append under a stored id changes nothing: the first '
      'bytes, signature, author and hlc survive, so a relayed record cannot '
      'displace a locally authored one', () async {
    await records.append(_row('r1', payload: '{"subject_user_id":"u2"}'));
    await records.append(
      _row(
        'r1',
        payload: '{"subject_user_id":"attacker"}',
        authorDevice: 'dev-evil',
        sigFill: 9,
        hlc: 9999,
        verified: true,
      ),
    );

    final back = (await records.byId('r1'))!;
    expect(utf8.decode(back.payload), '{"subject_user_id":"u2"}');
    expect(back.authorDevice, 'dev-a');
    expect(back.sig, _sig(7));
    expect(back.hlc, 1000);
    expect(back.verified, isFalse);
    expect((await records.ofKind('verification_event')).length, 1);
  });

  test('E-03-61 markVerified and attachSeq move only their own column; the seq '
      'first stored wins and the signed bytes are never touched', () async {
    await records.append(_row('r1'));
    await records.markVerified('r1');
    await records.attachSeq('r1', 41);
    await records.attachSeq('r1', 77);

    final back = (await records.byId('r1'))!;
    expect(back.verified, isTrue);
    expect(back.seq, 41);
    expect(utf8.decode(back.payload), '{"subject_user_id":"u2"}');
    expect(back.sig, _sig(7));
  });

  test('E-03-62 ofKind filters by kind and by tenant — a record of another '
      'tenant is never folded into this one', () async {
    await records.append(_row('r1', hlc: 1));
    await records.append(_row('r2', hlc: 2, tenantId: 't2'));
    await records.append(_row('r3', hlc: 3, kind: 'device_added'));

    expect((await records.ofKind('verification_event')).map((r) => r.id), [
      'r1',
      'r2',
    ]);
    expect(
      (await records.ofKind(
        'verification_event',
        tenantId: 't1',
      )).map((r) => r.id),
      ['r1'],
    );
    expect((await records.ofKind('device_added')).map((r) => r.id), ['r3']);
  });

  test(
    'E-03-64 append says whether it wrote: true the first time, false for an '
    'id already stored — the caller of a fresh uuid can therefore refuse to '
    'believe an in-memory row the store does not hold',
    () async {
      expect(await records.append(_row('r1')), isTrue);
      expect(await records.append(_row('r1', payload: '{"x":1}')), isFalse);
      expect(await records.append(_row('r2')), isTrue);
    },
  );

  test('E-03-63 a record with no rows for its kind yields an empty list, not a '
      'throw — a fresh install simply believes nobody yet', () async {
    expect(await records.ofKind('verification_event'), isEmpty);
    expect(await records.byId('nope'), isNull);
  });
}
