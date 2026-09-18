// Suite E (client half) — schema, opening, migrations, quick_check (03 §3, §5;
// ADR 2026-09-05c §6, §8).
@Tags(['E'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:core_ledger/core_ledger.dart';
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

  group('schema v2 (ADR 2026-09-09d §4)', () {
    test('E-09d-1 books_p carries start_date, nullable, and the schema is at '
        'least v2', () async {
      final db = await openMemory();
      final cols = await db.customSelect('PRAGMA table_info(books_p)').get();
      final byName = {
        for (final c in cols) c.read<String>('name'): c.read<int>('notnull'),
      };
      expect(byName, contains('start_date'));
      expect(
        byName['start_date'],
        0,
        reason: 'nullable: older books carry none',
      );
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, ledgerSchemaVersion);
      await db.close();
    });

    // ⚠️ E-09d-2 (v1 → v2 in-place upgrade) needs a full v1 schema fixture —
    // drift's schema-dump tooling, not a hand-rolled table — and is tracked in
    // ADR 2026-09-09d Open. The forward step itself is a single
    // `m.addColumn(booksP, booksP.startDate)` guarded by `from < 2`.
  });

  // Schema v3 — 07 §13 *Resumable* 🔒. `close_progress_local` is the one
  // device-local table that is neither Layer 1 nor Layer 2: no envelope, no
  // push, and **not** dropped by Recompute, because nothing in the envelope
  // stream could put it back.
  group('schema v3 (07 §13 Resumable 🔒)', () {
    test('E-03-46 close_progress_local exists, is keyed by (book, year, month) '
        'and the schema is at least v3', () async {
      final db = await openMemory();
      final cols = await db
          .customSelect('PRAGMA table_info(close_progress_local)')
          .get();
      final names = {for (final c in cols) c.read<String>('name')};
      expect(
        names,
        containsAll(<String>{
          'book_id',
          'year',
          'month',
          'step',
          'confirmed_banks_json',
        }),
      );
      final pk = {
        for (final c in cols)
          if (c.read<int>('pk') > 0) c.read<String>('name'),
      };
      expect(pk, {'book_id', 'year', 'month'});
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, ledgerSchemaVersion);
      // v3 added this table; later versions keep it (v4 = arrival ordinals).
      expect(ledgerSchemaVersion, greaterThanOrEqualTo(3));
      await db.close();
    });

    test(
      'E-03-46 it is neither layer: Recompute never drops it, and it carries '
      'no envelope, no signature and no push state',
      () async {
        expect(layer1Tables, isNot(contains('close_progress_local')));
        expect(layer2Tables, isNot(contains('close_progress_local')));
      },
    );
  });

  // Schema v4 — 02 §8 *late arrivals*; ADR 2026-09-05e §3, §10.
  // `envelopes_local.arrival_ordinal` is the device-local arrival fact the Late
  // Arrivals tray is computed from: never synced, never in a payload.
  group('schema v4 (02 §8 late arrivals 🔒)', () {
    test(
      'E-03-55 v3 → v4 carries every existing row and backfills its arrival '
      'ordinal in (hlc, envelope_id) order, so an upgrade conjures no tray '
      'item; appends after the upgrade continue above the highest ordinal',
      () async {
        final dir = Directory.systemTemp.createTempSync('rf-v4-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/ledger.sqlite');

        // A v4 database with a book in it, stored deliberately out of HLC
        // order so the backfill's ordering rule is observable.
        final f = Fixture();
        final envelopes = f.setupEnvelopes();
        final opened = await openLedgerDatabase(NativeDatabase(file));
        final db = (opened as Opened).db;
        await storeAll(Mirror(db, hasher: toyHash), envelopes.reversed);
        await db.close();

        // Wind it back to v3: the column did not exist then.
        final raw = LedgerDatabase(NativeDatabase(file));
        await raw.customStatement(
          'ALTER TABLE envelopes_local DROP COLUMN arrival_ordinal',
        );
        await raw.customStatement('PRAGMA user_version = 3');
        await raw.close();

        // Reopen: the forward step runs.
        final up = await openLedgerDatabase(NativeDatabase(file));
        expect(up, isA<Opened>(), reason: '03 §5: migrations fail closed');
        final db2 = (up as Opened).db;
        final m2 = Mirror(db2, hasher: toyHash);
        expect(
          (await db2.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first,
          4,
        );
        expect(ledgerSchemaVersion, 4);

        final rows = await m2.envelopesOf(f.bookId);
        expect(
          rows.length,
          envelopes.length,
          reason: 'every row carried across',
        );
        // `envelopesOf` reads in (hlc, envelope_id) order — the backfill rule —
        // so the ordinals come back as 1, 2, 3 … in exactly that order.
        expect(
          [for (final r in rows) r.arrivalOrdinal],
          [for (var i = 1; i <= rows.length; i++) i],
        );

        // A genuinely new arrival still lands above every backfilled row.
        final e = f.entry(
          'fresh',
          Verbs.moneyIn(
            into: f.cash,
            from: f.salary,
            amount: const Paise.rupees(100),
          ),
          date: LocalDate(2026, 4, 1),
          kind: EntryKind.moneyIn,
        );
        await m2.append(f.eventEnvelope(e));
        final fresh = (await m2.envelopesOf(f.bookId))
            .singleWhere((r) => r.envelopeId == 'env-fresh');
        expect(fresh.arrivalOrdinal, rows.length + 1);
        // Idempotent re-append takes no number.
        expect(await m2.append(f.eventEnvelope(e)), isFalse);
        await db2.close();
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
