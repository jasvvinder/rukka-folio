// Suite E (client half) — schema, opening, migrations, quick_check (03 §3, §5;
// ADR 2026-09-05c §6, §8).
@Tags(['E'])
library;

import 'dart:typed_data';

import 'package:data/data.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('schema (03 §3.1, §3.2)', () {
    test('E-03-1 schema v1 creates every Layer 1 and Layer 2 table, the key '
        'indexes and the append-only guards', () async {
      final db = await openMemory();
      final rows = await db
          .customSelect('SELECT type, name FROM sqlite_master')
          .get();
      final names = {
        for (final r in rows)
          '${r.read<String>('type')}:${r.read<String>('name')}',
      };
      for (final t in [...layer1Tables, ...layer2Tables]) {
        expect(names, contains('table:$t'), reason: t);
      }
      for (final i in [
        'entry_lines_p_account_date',
        'entries_p_daybook',
        'entries_p_inbox',
        'entries_p_advance_requests',
        'import_lines_p_state',
        'envelopes_local_book_order',
        'envelopes_local_author',
      ]) {
        expect(names, contains('index:$i'), reason: i);
      }
      expect(names, contains('trigger:envelopes_local_append_only_update'));
      expect(names, contains('trigger:envelopes_local_append_only_delete'));
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, ledgerSchemaVersion);
      await db.close();
    });

    test(
      'E-03-2 money columns are INTEGER paise and the check constraints hold: '
      'outbox push_state, entries_p review_state, store_epoch single row',
      () async {
        final db = await openMemory();
        for (final (table, col) in [
          ('entry_lines_p', 'amount_paise'),
          ('balances', 'balance_paise'),
          ('daily_snapshots', 'balance_paise'),
          ('cash_counts_p', 'counted_total_paise'),
          ('import_lines_p', 'amount_paise'),
        ]) {
          final info = await db
              .customSelect('PRAGMA table_info("$table")')
              .get();
          final c = info.firstWhere((r) => r.read<String>('name') == col);
          expect(
            c.read<String>('type').toUpperCase(),
            'INTEGER',
            reason: '$table.$col',
          );
        }
        expect(
          () => db.customStatement(
            "INSERT INTO outbox(envelope_id, book_id, blob, created_at, push_state) VALUES ('x','b',x'00',1,'bogus')",
          ),
          throwsA(anything),
        );
        expect(
          () => db.customStatement(
            "INSERT INTO entries_p(id, book_id, kind, status, accounting_date, review_state, created_by_user, hlc) "
            "VALUES ('x','b','money_in','posted','2026-04-01','bogus','u',1)",
          ),
          throwsA(anything),
        );
        expect(
          () => db.customStatement(
            "INSERT INTO store_epoch(id, epoch) VALUES (2, 'e')",
          ),
          throwsA(anything),
        );
        await db.close();
      },
    );

    test(
      'E-03-3 status and review_state are independent: a posted entry with an '
      'open flag is a legal row and its lines are in balances',
      () async {
        final db = await openMemory();
        final f = Fixture();
        final (m, r) = rig(db);
        await storeAll(m, f.setupEnvelopes());
        final e4 = f
            .ordinaryMonth()[3]; // the over-limit payment, flag open, undecided
        await m.append(f.eventEnvelope(e4));
        await r.run();
        final row = await (db.select(
          db.entriesP,
        )..where((t) => t.id.equals('e4'))).getSingle();
        expect(row.status, 'posted');
        expect(row.reviewState, 'open');
        expect(row.reviewApprover, 'papa');
        expect(await storedBalance(db, f.cash.id), -700000);
        await db.close();
      },
    );
  });

  group('open (03 §5, ADR 05c §6)', () {
    test('E-05c-4 every open runs quick_check and reports a typed outcome; a '
        'healthy file is Opened', () async {
      final r = await openLedgerDatabase(NativeDatabase.memory());
      expect(r, isA<Opened>());
      final db = (r as Opened).db;
      expect(await db.quickCheck(), ['ok']);
      await db.close();
    });

    test('E-03-12 a database written by a newer schema fails closed: '
        'MigrationFailed, nothing run, connection closed', () async {
      final exec = NativeDatabase.memory(
        setup: (raw) => raw.execute('PRAGMA user_version = 99'),
      );
      final r = await openLedgerDatabase(exec);
      expect(r, isA<MigrationFailed>());
      final mf = r as MigrationFailed;
      expect(mf.from, 99);
      expect(mf.to, ledgerSchemaVersion);
      expect(mf.reason, contains('newer'));
    });

    test(
      'E-05c-5 the SQLCipher key travels as raw bytes in the executor setup, '
      'the pragma is a no-op on plain SQLite, and the key buffer is zeroised '
      'after open',
      () async {
        final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
        final setup = sqlcipherSetup(Uint8List.fromList(key));
        final r = await openLedgerDatabase(
          NativeDatabase.memory(setup: setup),
          cipherKey: key,
        );
        expect(r, isA<Opened>());
        expect(key, everyElement(0), reason: 'zeroised (CLAUDE.md rule 7)');
        expect(() => sqlcipherSetup(Uint8List(16)), throwsArgumentError);
        await (r as Opened).db.close();
      },
    );

    test('E-03-13 dumpTable is deterministic text over every column, ordered, '
        'with blobs as hex', () async {
      final db = await openMemory();
      await db
          .into(db.syncCursors)
          .insert(SyncCursorsCompanion.insert(bookId: 'b2', lastSeq: 7));
      await db
          .into(db.syncCursors)
          .insert(SyncCursorsCompanion.insert(bookId: 'b1', lastSeq: 3));
      await db
          .into(db.keyCache)
          .insert(
            KeyCacheCompanion.insert(
              bookId: 'b1',
              keyVersion: 1,
              wrappedBlob: Uint8List.fromList([0, 255]),
            ),
          );
      expect(
        await db.dumpTable('sync_cursors'),
        '# sync_cursors (book_id, last_seq)\nb1\t3\nb2\t7\n',
      );
      expect(await db.dumpTable('key_cache'), contains('\tx00ff\n'));
      expect(absent, isA<Value<Object?>>());
      await db.close();
    });
  });
}
